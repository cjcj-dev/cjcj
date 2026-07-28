#!/usr/bin/env python3
"""Fail closed unless a packaged standard-library closure is sticky.

The STICKY_STD manifest binds the exact std libraries and CJO files. Every
Cangjie-compiled ELF, Mach-O, or COFF object in every bound machine-code
artifact must contain only valid STICKY attestation records. Pure native FFI
libraries and native members mixed into Cangjie archives must be named
explicitly.
"""

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path


ELF_GC_FLAGS_SECTION = ".cjmetadata.gcflags"
MACHO_GC_FLAGS_SECTION = "__CJ_METADATA,__cjgcflags"
COFF_GC_FLAGS_SECTION = ".cjgcflg"
GC_FLAGS_RECORD_SIZE = 20
STICKY_MAGIC = 0x53424A43
STICKY_VERSION = 1
STICKY_KIND = 2
STD_LIBRARY = re.compile(r"^libcangjie-std(?:[-.].*)?\.(?:a|so|dylib)$")
WINDOWS_STD_DLL = re.compile(r"^libcangjie-std(?:[-.].*)?\.dll$")
SUPPORTED_PLATFORMS = {
    "linux_x86_64_cjnative",
    "linux_aarch64_cjnative",
    "darwin_aarch64_cjnative",
    "darwin_x86_64_cjnative",
    "windows_x86_64_cjnative",
}
COFF_MACHINES = {0x014C, 0x01C0, 0x01C4, 0x8664, 0xAA64}
COFF_BIGOBJ_CLASS_ID = bytes.fromhex("c7a1bad1eeba a94b af20 faf66aa4dcb8".replace(" ", ""))
BSD_ARCHIVE_SYMBOL_TABLES = {"__.SYMDEF", "__.SYMDEF SORTED", "__.SYMDEF_64", "__.SYMDEF_64 SORTED"}


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


def macho_sections(data, origin):
    magic_formats = {
        b"\xfe\xed\xfa\xce": (">", False),
        b"\xce\xfa\xed\xfe": ("<", False),
        b"\xfe\xed\xfa\xcf": (">", True),
        b"\xcf\xfa\xed\xfe": ("<", True),
    }
    format_info = magic_formats.get(data[:4])
    if format_info is None:
        return None
    endian, is_64 = format_info
    header_format = endian + ("IiiIIIII" if is_64 else "IiiIIII")
    header_size = struct.calcsize(header_format)
    if len(data) < header_size:
        raise ClosureError(f"truncated Mach-O header: {origin}")
    header = struct.unpack_from(header_format, data)
    command_count, commands_size = header[4], header[5]
    commands_end = header_size + commands_size
    if commands_end > len(data):
        raise ClosureError(f"Mach-O load commands outside file: {origin}")

    result = {}
    command_offset = header_size
    for _ in range(command_count):
        if command_offset + 8 > commands_end:
            raise ClosureError(f"truncated Mach-O load command: {origin}")
        command, command_size = struct.unpack_from(endian + "II", data, command_offset)
        if command_size < 8 or command_offset + command_size > commands_end:
            raise ClosureError(f"malformed Mach-O load command: {origin}")
        segment_command = 0x19 if is_64 else 0x1
        if command == segment_command:
            segment_size = 72 if is_64 else 56
            section_size = 80 if is_64 else 68
            if command_size < segment_size:
                raise ClosureError(f"truncated Mach-O segment command: {origin}")
            section_count_offset = command_offset + (64 if is_64 else 48)
            section_count = struct.unpack_from(endian + "I", data, section_count_offset)[0]
            if segment_size + section_count * section_size > command_size:
                raise ClosureError(f"Mach-O sections outside segment command: {origin}")
            for index in range(section_count):
                section_offset = command_offset + segment_size + index * section_size
                section_name = data[section_offset:section_offset + 16].split(b"\0", 1)[0]
                segment_name = data[section_offset + 16:section_offset + 32].split(b"\0", 1)[0]
                name = (segment_name + b"," + section_name).decode("ascii", errors="replace")
                if is_64:
                    size = struct.unpack_from(endian + "Q", data, section_offset + 40)[0]
                    file_offset = struct.unpack_from(endian + "I", data, section_offset + 48)[0]
                    flags = struct.unpack_from(endian + "I", data, section_offset + 64)[0]
                else:
                    size, file_offset = struct.unpack_from(endian + "II", data, section_offset + 36)
                    flags = struct.unpack_from(endian + "I", data, section_offset + 56)[0]
                is_zerofill = flags & 0xFF in (0x1, 0xC, 0x12)
                if not is_zerofill and file_offset + size > len(data):
                    raise ClosureError(f"Mach-O section outside file: {origin}:{name}")
                raw = b"" if is_zerofill else data[file_offset:file_offset + size]
                result[name] = result.get(name, b"") + raw
        command_offset += command_size
    if command_offset != commands_end:
        raise ClosureError(f"Mach-O load command size mismatch: {origin}")
    return endian, result


def universal_members(data, origin):
    magic_formats = {
        b"\xca\xfe\xba\xbe": (">", False),
        b"\xbe\xba\xfe\xca": ("<", False),
        b"\xca\xfe\xba\xbf": (">", True),
        b"\xbf\xba\xfe\xca": ("<", True),
    }
    format_info = magic_formats.get(data[:4])
    if format_info is None:
        return None
    endian, is_64 = format_info
    if len(data) < 8:
        raise ClosureError(f"truncated universal Mach-O header: {origin}")
    member_count = struct.unpack_from(endian + "I", data, 4)[0]
    entry_format = endian + ("iiQQII" if is_64 else "iiIII")
    entry_size = struct.calcsize(entry_format)
    if member_count == 0 or member_count > 64 or 8 + member_count * entry_size > len(data):
        raise ClosureError(f"malformed universal Mach-O member table: {origin}")
    members = []
    ranges = []
    for index in range(member_count):
        entry = struct.unpack_from(entry_format, data, 8 + index * entry_size)
        cpu_type, cpu_subtype, offset, size = entry[:4]
        if size == 0 or offset + size > len(data):
            raise ClosureError(f"universal Mach-O member outside file: {origin}:fat[{index}]")
        if any(offset < other_end and other_start < offset + size for other_start, other_end in ranges):
            raise ClosureError(f"overlapping universal Mach-O members: {origin}:fat[{index}]")
        ranges.append((offset, offset + size))
        members.append((f"fat[{index}:cpu={cpu_type}:subtype={cpu_subtype}]", data[offset:offset + size]))
    return members


def coff_string_table(data, pointer_to_symbols, symbol_count, origin):
    if pointer_to_symbols == 0:
        return b""
    offset = pointer_to_symbols + symbol_count * 18
    if offset + 4 > len(data):
        raise ClosureError(f"COFF string table outside file: {origin}")
    size = struct.unpack_from("<I", data, offset)[0]
    if size < 4 or offset + size > len(data):
        raise ClosureError(f"malformed COFF string table: {origin}")
    return data[offset + 4:offset + size]


def coff_section_name(raw_name, string_table, origin):
    short_name = raw_name.split(b"\0", 1)[0]
    if not short_name.startswith(b"/") or not short_name[1:].isdigit():
        return short_name.decode("ascii", errors="replace")
    offset = int(short_name[1:])
    if offset < 4:
        raise ClosureError(f"bad COFF section-name offset: {origin}")
    offset -= 4
    if offset >= len(string_table):
        raise ClosureError(f"COFF section name outside string table: {origin}")
    end = string_table.find(b"\0", offset)
    if end < 0:
        raise ClosureError(f"unterminated COFF section name: {origin}")
    return string_table[offset:end].decode("ascii", errors="replace")


def coff_sections(data, origin):
    is_pe = data.startswith(b"MZ")
    if is_pe:
        if len(data) < 0x40:
            raise ClosureError(f"truncated DOS/PE header: {origin}")
        pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
        if pe_offset + 24 > len(data) or data[pe_offset:pe_offset + 4] != b"PE\0\0":
            raise ClosureError(f"malformed PE signature: {origin}")
        header_offset = pe_offset + 4
        machine, section_count, _, pointer_to_symbols, symbol_count, optional_size, _ = struct.unpack_from(
            "<HHIIIHH", data, header_offset)
        section_table_offset = header_offset + 20 + optional_size
        string_table = b""
    elif data.startswith(b"\0\0\xff\xff"):
        if len(data) >= 56 and data[12:28] == COFF_BIGOBJ_CLASS_ID:
            machine = struct.unpack_from("<H", data, 6)[0]
            section_count, pointer_to_symbols, symbol_count = struct.unpack_from("<III", data, 44)
            section_table_offset = 56
            string_table = coff_string_table(data, pointer_to_symbols, symbol_count, origin)
        elif len(data) >= 20:
            return "<", {}
        else:
            raise ClosureError(f"truncated COFF anonymous object: {origin}")
    else:
        if len(data) < 20:
            return None
        machine, section_count, _, pointer_to_symbols, symbol_count, optional_size, _ = struct.unpack_from(
            "<HHIIIHH", data)
        if machine not in COFF_MACHINES:
            return None
        section_table_offset = 20 + optional_size
        string_table = coff_string_table(data, pointer_to_symbols, symbol_count, origin)
    if machine not in COFF_MACHINES or section_count == 0:
        raise ClosureError(f"unsupported/malformed COFF header: {origin}")
    if section_table_offset + section_count * 40 > len(data):
        raise ClosureError(f"COFF section table outside file: {origin}")

    result = {}
    for index in range(section_count):
        section_offset = section_table_offset + index * 40
        name = coff_section_name(data[section_offset:section_offset + 8], string_table, origin)
        virtual_size, _, raw_size, raw_offset = struct.unpack_from("<IIII", data, section_offset + 8)
        characteristics = struct.unpack_from("<I", data, section_offset + 36)[0]
        size = min(virtual_size, raw_size) if is_pe and virtual_size else raw_size
        is_uninitialized = bool(characteristics & 0x00000080)
        if not is_uninitialized and raw_offset + size > len(data):
            raise ClosureError(f"COFF section outside file: {origin}:{name}")
        raw = b"" if is_uninitialized else data[raw_offset:raw_offset + size]
        result[name] = result.get(name, b"") + raw
    return "<", result


def object_images(data, origin):
    universal = universal_members(data, origin)
    if universal is not None:
        images = []
        for name, body in universal:
            nested = object_images(body, f"{origin}:{name}")
            if nested is None:
                raise ClosureError(f"{origin}:{name}: universal member is not an object")
            images.extend(nested)
        return images

    sections = elf_sections(data, origin)
    if sections is not None:
        encoding = data[5]
        return [(origin, "ELF", "<" if encoding == 1 else ">", sections)]
    parsed = macho_sections(data, origin)
    if parsed is not None:
        endian, sections = parsed
        return [(origin, "Mach-O", endian, sections)]
    parsed = coff_sections(data, origin)
    if parsed is not None:
        endian, sections = parsed
        return [(origin, "COFF", endian, sections)]
    return None


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
            if name not in BSD_ARCHIVE_SYMBOL_TABLES:
                members.append((name, body))
        offset = end + (end & 1)
    return members


def verify_records(raw, origin, endian="<"):
    if not raw or len(raw) % GC_FLAGS_RECORD_SIZE != 0:
        raise ClosureError(f"{origin}: gcflags size {len(raw)} is not a nonzero multiple of 20")
    count = 0
    for offset in range(0, len(raw), GC_FLAGS_RECORD_SIZE):
        flags = raw[offset:offset + 3]
        padding = raw[offset + 3]
        magic, version, kind, fingerprint = struct.unpack_from(endian + "IIII", raw, offset + 4)
        if flags[0] != 1 or flags[1] != 1 or padding != 0:
            raise ClosureError(f"{origin}: record {count} has invalid GC flags/padding")
        if magic != STICKY_MAGIC or version != STICKY_VERSION or kind != STICKY_KIND or fingerprint == 0:
            raise ClosureError(
                f"{origin}: record {count} is not STICKY "
                f"(magic=0x{magic:08x} version={version} kind={kind} fingerprint=0x{fingerprint:08x})"
            )
        count += 1
    return count


def verify_merged_records(raw, origin, endian="<"):
    """Verify gcflags records retained inside a linked .cjmetadata section."""
    encoded_magic = struct.pack(endian + "I", STICKY_MAGIC)
    positions = []
    cursor = 0
    while True:
        position = raw.find(encoded_magic, cursor)
        if position < 0:
            break
        positions.append(position)
        cursor = position + len(encoded_magic)
    if not positions:
        raise ClosureError(f"{origin}: merged Cangjie metadata contains no sticky record magic")
    records = 0
    for position in positions:
        start = position - 4
        end = start + GC_FLAGS_RECORD_SIZE
        if start < 0 or end > len(raw):
            raise ClosureError(f"{origin}: truncated merged gcflags record at offset {start}")
        records += verify_records(raw[start:end], f"{origin}:merged+0x{start:x}", endian)
    return records


def metadata_sections(object_format, sections):
    if object_format == "ELF":
        return sorted(name for name in sections if name == ".cjmetadata" or name.startswith(".cjmetadata."))
    if object_format == "Mach-O":
        return sorted(name for name in sections if name.startswith("__CJ_METADATA,"))
    return sorted(name for name in sections if name.startswith(".cj"))


def gcflags_section_name(object_format):
    return {
        "ELF": ELF_GC_FLAGS_SECTION,
        "Mach-O": MACHO_GC_FLAGS_SECTION,
        "COFF": COFF_GC_FLAGS_SECTION,
    }[object_format]


def verify_object_records(object_origin, object_format, endian, sections):
    metadata = metadata_sections(object_format, sections)
    gcflags_name = gcflags_section_name(object_format)
    gcflags = sections.get(gcflags_name)
    if gcflags is not None:
        return verify_records(gcflags, object_origin, endian)
    if object_format == "ELF" and ".cjmetadata" in sections:
        return verify_merged_records(sections[".cjmetadata"], object_origin, endian)
    if metadata:
        raise ClosureError(f"{object_origin}: Cangjie metadata exists but {gcflags_name} is missing")
    return None


def verify_native_artifact(path):
    data = path.read_bytes()
    members = archive_members(data, str(path))
    objects = members if members is not None else [(path.name, data)]
    native_objects = 0
    for name, body in objects:
        images = object_images(body, f"{path}:{name}")
        if images is None:
            raise ClosureError(f"{path}:{name}: native member is not a recognized object")
        for object_origin, object_format, _, sections in images:
            metadata = metadata_sections(object_format, sections)
            if metadata:
                raise ClosureError(f"{object_origin}: native library contains Cangjie metadata {metadata}")
            native_objects += 1
    if native_objects == 0:
        raise ClosureError(f"{path}: native library contains no object")
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
        images = object_images(body, f"{path}:{name}")
        if images is None:
            raise ClosureError(f"{path}:{name}: archive member is not a recognized object")
        if name in allowed_native:
            for object_origin, object_format, endian, sections in images:
                gcflags_name = gcflags_section_name(object_format)
                if gcflags_name in sections or (object_format == "ELF" and ".cjmetadata" in sections):
                    count = verify_object_records(object_origin, object_format, endian, sections)
                    if count is not None:
                        raise ClosureError(
                            f"{path}:{name}: attested Cangjie member is incorrectly declared native")
            seen_native.add(name)
            continue
        member_records = []
        for object_origin, object_format, endian, sections in images:
            count = verify_object_records(object_origin, object_format, endian, sections)
            member_records.append(count)
        if any(count is None for count in member_records):
            raise ClosureError(f"{path}:{name}: unattested object is not declared native")
        cangjie_objects += len(member_records)
        records += sum(member_records)
    if seen_native != allowed_native:
        raise ClosureError(f"{path}: unused nativeMembers entries={sorted(allowed_native - seen_native)}")
    if cangjie_objects == 0 or records == 0:
        raise ClosureError(f"{path}: no attested Cangjie object found")
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
    if args.platform not in SUPPORTED_PLATFORMS:
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
    if args.platform == "windows_x86_64_cjnative":
        if managed is None:
            raise ClosureError("Windows sticky closure requires a nonempty managed inventory")
        managed_files, managed_hashes = require_mapping(managed, "managed")
        actual_managed = sorted(
            str(path.relative_to(args.sdk)) for path in runtime_root.iterdir()
            if path.is_file() and WINDOWS_STD_DLL.fullmatch(path.name)
        )
        if not managed_files:
            raise ClosureError("Windows sticky closure managed inventory is empty")
        if managed_files != actual_managed:
            missing = sorted(set(managed_files) - set(actual_managed))
            extra = sorted(set(actual_managed) - set(managed_files))
            raise ClosureError(f"managed Windows std DLL inventory mismatch: missing={missing} extra={extra}")
        verify_hashes(args.sdk, managed_files, managed_hashes, "managed artifact")
        managed_paths.extend(args.sdk / name for name in managed_files)
    elif managed is not None:
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
