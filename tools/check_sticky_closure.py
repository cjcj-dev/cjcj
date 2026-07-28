#!/usr/bin/env python3
"""Fail closed unless a packaged standard-library closure is sticky.

The STICKY_STD manifest binds the exact std libraries and CJO files. Every
Cangjie ELF object in every bound machine-code artifact must contain only valid
STICKY attestation records. Pure native FFI libraries must be named explicitly
by ``nativeLibraries`` and must not contain any Cangjie metadata section.
"""

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path


GC_FLAGS_SECTION = ".cjmetadata.gcflags"
GC_FLAGS_RECORD_SIZE = 20
STICKY_MAGIC = 0x53424A43
STICKY_VERSION = 1
STICKY_KIND = 2
STD_LIBRARY = re.compile(r"^libcangjie-std(?:[-.].*)?\.(?:a|so|dylib)$")


class ClosureError(Exception):
    pass


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_mapping(section, label):
    files = section.get("files")
    hashes = section.get("sha256")
    if not isinstance(files, list) or not isinstance(hashes, dict):
        raise ClosureError(f"{label} must contain files[] and sha256{{}}")
    if sorted(files) != sorted(hashes):
        raise ClosureError(f"{label} files and sha256 keys differ")
    if len(files) != len(set(files)):
        raise ClosureError(f"{label} contains duplicate paths")
    return sorted(files), hashes


def verify_inventory(directory, expected, predicate, label):
    if not directory.is_dir():
        raise ClosureError(f"{label} directory missing: {directory}")
    actual = sorted(path.name for path in directory.iterdir() if path.is_file() and predicate(path.name))
    if actual != sorted(expected):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise ClosureError(f"{label} inventory mismatch: missing={missing} extra={extra}")


def verify_hashes(root, files, hashes, label):
    for name in files:
        path = root / name
        if not path.is_file():
            raise ClosureError(f"{label} missing: {path}")
        actual = sha256(path)
        if actual != hashes[name]:
            raise ClosureError(f"{label} SHA-256 mismatch: {name} {actual} != {hashes[name]}")


def elf_sections(data, origin):
    if not data.startswith(b"\x7fELF"):
        return None
    if len(data) < 16:
        raise ClosureError(f"truncated ELF identification: {origin}")
    elf_class, encoding = data[4], data[5]
    endian = "<" if encoding == 1 else ">" if encoding == 2 else None
    if endian is None or elf_class not in (1, 2):
        raise ClosureError(f"unsupported ELF class/encoding: {origin}")
    header_format = endian + ("HHIIIIIHHHHHH" if elf_class == 1 else "HHIQQQIHHHHHH")
    header_size = 16 + struct.calcsize(header_format)
    if len(data) < header_size:
        raise ClosureError(f"truncated ELF header: {origin}")
    header = struct.unpack_from(header_format, data, 16)
    section_offset, section_entry_size, section_count, names_index = header[5], header[10], header[11], header[12]
    section_format = endian + ("IIIIIIIIII" if elf_class == 1 else "IIQQQQIIQQ")
    minimum_entry_size = struct.calcsize(section_format)
    if section_count == 0 or names_index == 0xFFFF or section_entry_size < minimum_entry_size:
        raise ClosureError(f"unsupported extended/malformed ELF section table: {origin}")
    if section_offset + section_entry_size * section_count > len(data) or names_index >= section_count:
        raise ClosureError(f"ELF section table outside file: {origin}")
    sections = []
    for index in range(section_count):
        entry = struct.unpack_from(section_format, data, section_offset + index * section_entry_size)
        sections.append((entry[0], entry[1], entry[4], entry[5]))
    _, _, names_offset, names_size = sections[names_index]
    if names_offset + names_size > len(data):
        raise ClosureError(f"ELF section-name table outside file: {origin}")
    names = data[names_offset:names_offset + names_size]
    result = {}
    for name_offset, section_type, offset, size in sections:
        if name_offset >= len(names) or (section_type != 8 and offset + size > len(data)):
            raise ClosureError(f"ELF section outside file: {origin}")
        end = names.find(b"\0", name_offset)
        if end < 0:
            raise ClosureError(f"unterminated ELF section name: {origin}")
        name = names[name_offset:end].decode("ascii", errors="replace")
        result[name] = b"" if section_type == 8 else data[offset:offset + size]
    return result


def archive_members(data, origin):
    if data.startswith(b"!<thin>\n"):
        raise ClosureError(f"thin archives are not self-contained: {origin}")
    if not data.startswith(b"!<arch>\n"):
        return None
    offset = 8
    string_table = b""
    members = []
    while offset < len(data):
        if offset + 60 > len(data):
            raise ClosureError(f"truncated archive header: {origin}")
        header = data[offset:offset + 60]
        if header[58:60] != b"`\n":
            raise ClosureError(f"bad archive member marker: {origin}")
        raw_name = header[:16].decode("ascii", errors="replace").strip()
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError as error:
            raise ClosureError(f"bad archive member size: {origin}") from error
        start, end = offset + 60, offset + 60 + size
        if end > len(data):
            raise ClosureError(f"archive member outside file: {origin}")
        body = data[start:end]
        if raw_name == "//":
            string_table = body
        elif raw_name not in ("/", "/SYM64/"):
            if raw_name.startswith("#1/"):
                name_size = int(raw_name[3:])
                name = body[:name_size].rstrip(b"\0").decode("utf-8", errors="replace")
                body = body[name_size:]
            elif raw_name.startswith("/") and raw_name[1:].isdigit():
                name_offset = int(raw_name[1:])
                name_end = string_table.find(b"/\n", name_offset)
                if name_end < 0:
                    raise ClosureError(f"bad GNU archive long name: {origin}")
                name = string_table[name_offset:name_end].decode("utf-8", errors="replace")
            else:
                name = raw_name.rstrip("/")
            members.append((name, body))
        offset = end + (end & 1)
    return members


def verify_records(raw, origin):
    if not raw or len(raw) % GC_FLAGS_RECORD_SIZE != 0:
        raise ClosureError(f"{origin}: gcflags size {len(raw)} is not a nonzero multiple of 20")
    count = 0
    for offset in range(0, len(raw), GC_FLAGS_RECORD_SIZE):
        flags = raw[offset:offset + 3]
        padding = raw[offset + 3]
        magic, version, kind, fingerprint = struct.unpack_from("<IIII", raw, offset + 4)
        if flags[0] != 1 or flags[1] != 1 or padding != 0:
            raise ClosureError(f"{origin}: record {count} has invalid GC flags/padding")
        if magic != STICKY_MAGIC or version != STICKY_VERSION or kind != STICKY_KIND or fingerprint == 0:
            raise ClosureError(
                f"{origin}: record {count} is not STICKY "
                f"(magic=0x{magic:08x} version={version} kind={kind} fingerprint=0x{fingerprint:08x})"
            )
        count += 1
    return count


def verify_native_artifact(path):
    data = path.read_bytes()
    members = archive_members(data, str(path))
    objects = members if members is not None else [(path.name, data)]
    native_objects = 0
    for name, body in objects:
        sections = elf_sections(body, f"{path}:{name}")
        if sections is None:
            raise ClosureError(f"{path}:{name}: non-ELF native member is not attestable")
        metadata = sorted(section for section in sections if section.startswith(".cjmetadata."))
        if metadata:
            raise ClosureError(f"{path}:{name}: native library contains Cangjie metadata {metadata}")
        native_objects += 1
    if native_objects == 0:
        raise ClosureError(f"{path}: native library contains no ELF object")
    return native_objects


def verify_machine_artifact(path, allowed_native=()):
    data = path.read_bytes()
    members = archive_members(data, str(path))
    objects = members if members is not None else [(path.name, data)]
    allowed_native = set(allowed_native)
    seen_native = set()
    records = 0
    cangjie_objects = 0
    for name, body in objects:
        sections = elf_sections(body, f"{path}:{name}")
        if sections is None:
            raise ClosureError(f"{path}:{name}: non-ELF archive member is not attestable")
        has_cangjie_metadata = any(section.startswith(".cjmetadata.") for section in sections)
        gcflags = sections.get(GC_FLAGS_SECTION)
        if gcflags is None:
            if name in allowed_native and not has_cangjie_metadata:
                seen_native.add(name)
                continue
            if has_cangjie_metadata:
                raise ClosureError(f"{path}:{name}: Cangjie metadata exists but {GC_FLAGS_SECTION} is missing")
            raise ClosureError(f"{path}:{name}: unattested ELF member is not declared native")
        if name in allowed_native:
            raise ClosureError(f"{path}:{name}: attested Cangjie member is incorrectly declared native")
        cangjie_objects += 1
        records += verify_records(gcflags, f"{path}:{name}")
    if seen_native != allowed_native:
        raise ClosureError(f"{path}: unused nativeMembers entries={sorted(allowed_native - seen_native)}")
    if cangjie_objects == 0 or records == 0:
        raise ClosureError(f"{path}: no attested Cangjie ELF object found")
    return cangjie_objects, records


def require_string_list(value, label, permitted):
    if not isinstance(value, list) or len(value) != len(set(value)):
        raise ClosureError(f"{label} must be a unique string list")
    if any(not isinstance(name, str) for name in value):
        raise ClosureError(f"{label} must contain only strings")
    unexpected = sorted(set(value) - set(permitted))
    if unexpected:
        raise ClosureError(f"{label} names undeclared libraries: {unexpected}")
    return set(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path, help="STICKY_STD.json closure manifest")
    parser.add_argument("--sdk", required=True, type=Path, help="packaged SDK root")
    parser.add_argument("--platform", default="linux_x86_64_cjnative")
    parser.add_argument("--managed", action="append", default=[], type=Path,
                        help="additional machine artifact to attest; repeat as needed")
    args = parser.parse_args()
    if args.platform != "linux_x86_64_cjnative":
        raise ClosureError(f"unsupported attestation target: {args.platform}")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if (manifest.get("closure"), manifest.get("role"), manifest.get("provenance")) != (
            "single-sticky", "final", "official-cjc-sticky-lowering"):
        raise ClosureError("manifest is not a final official-cjc single-sticky closure")

    std_files, std_hashes = require_mapping(manifest.get("sticky", {}), "sticky")
    cjo_files, cjo_hashes = require_mapping(manifest.get("cjo", {}), "cjo")
    native_libraries = require_string_list(manifest.get("nativeLibraries"), "nativeLibraries", std_files)
    lib_root = args.sdk / "lib" / args.platform
    cjo_root = args.sdk / "modules" / args.platform / "std"
    runtime_root = args.sdk / "runtime" / "lib" / args.platform
    shared_files = sorted(name for name in std_files if name.endswith((".so", ".dylib")))
    native_members = manifest.get("nativeMembers", {})
    if not isinstance(native_members, dict) or any(name not in std_files for name in native_members):
        raise ClosureError("nativeMembers must map only declared std libraries to member-name lists")
    for name, members in native_members.items():
        if not isinstance(members, list) or len(members) != len(set(members)):
            raise ClosureError(f"nativeMembers[{name}] must be a unique member-name list")
    if native_libraries & set(native_members):
        raise ClosureError("a library cannot appear in both nativeLibraries and nativeMembers")

    verify_inventory(lib_root, std_files, lambda name: bool(STD_LIBRARY.fullmatch(name)), "std library")
    verify_inventory(cjo_root, cjo_files, lambda name: name.endswith(".cjo"), "std CJO")
    verify_inventory(runtime_root, shared_files, lambda name: bool(STD_LIBRARY.fullmatch(name)), "runtime std mirror")
    verify_hashes(lib_root, std_files, std_hashes, "std library")
    verify_hashes(cjo_root, cjo_files, cjo_hashes, "std CJO")
    verify_hashes(runtime_root, shared_files, std_hashes, "runtime std mirror")

    managed = manifest.get("managed")
    managed_paths = []
    if managed is not None:
        managed_files, managed_hashes = require_mapping(managed, "managed")
        verify_hashes(args.sdk, managed_files, managed_hashes, "managed artifact")
        managed_paths.extend(args.sdk / name for name in managed_files)
    managed_paths.extend(args.managed)

    object_count = 0
    native_object_count = 0
    record_count = 0
    for name in std_files:
        path = lib_root / name
        if name in native_libraries:
            objects = verify_native_artifact(path)
            native_object_count += objects
            print(f"NATIVE path={path} objects={objects}")
            continue
        objects, records = verify_machine_artifact(path, native_members.get(name, []))
        object_count += objects
        record_count += records
        print(f"ATTESTED path={path} objects={objects} records={records}")
    for path in managed_paths:
        objects, records = verify_machine_artifact(path)
        object_count += objects
        record_count += records
        print(f"ATTESTED path={path} objects={objects} records={records}")

    print(
        f"STICKY_CLOSURE std={len(std_files)}/{len(std_files)} "
        f"cjo={len(cjo_files)}/{len(cjo_files)} runtime_shared={len(shared_files)}/{len(shared_files)} "
        f"native_libraries={len(native_libraries)} native_objects={native_object_count} "
        f"attested_objects={object_count} sticky_records={record_count} RESULT=PASS"
    )


if __name__ == "__main__":
    try:
        main()
    except (ClosureError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"STICKY_CLOSURE RESULT=FAIL reason={error}", file=sys.stderr)
        raise SystemExit(1)
