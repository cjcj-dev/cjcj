#!/usr/bin/env python3
"""Package and verify a pinned Linux language SDK with a separate host runtime.

The manifest records bytes, not inferred build history. Source provenance is an
explicit producer input. Consumers must get its digest from their reviewed pin,
never from the downloaded directory itself.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys
import tarfile

TUPLE = "linux_x86_64_cjnative"
ALIASES = {"sdk/bin/cjc": "cjcj-stage1", "sdk/bin/cjc-frontend": "cjcj-stage1"}
ROLES = {
    "compiler": "sdk/bin/cjcj-stage1",
    "stdlib": f"sdk/lib/{TUPLE}/libcangjie-std-core.a",
    "llc": "sdk/third_party/llvm/bin/llc",
    "opt": "sdk/third_party/llvm/bin/opt",
    "host_runtime": f"host/runtime/lib/{TUPLE}/libcangjie-runtime.so",
    "host_boundscheck": f"host/runtime/lib/{TUPLE}/libboundscheck.so",
}
# H48 retained SDK contains stale backend manifests and a target SO whose source
# cannot be recovered. Neither is an input to this language-toolchain handoff.
# The producer of the target runtime supplies its own pinned build separately.
EXCLUDED = (
    f"sdk/runtime/lib/{TUPLE}/libcangjie-runtime.so",
    f"sdk/runtime/lib/{TUPLE}/libboundscheck.so",
    "sdk/third_party/llvm/lib/libboundscheck.so",
    "sdk/third_party/llvm/MANIFEST",
    "sdk/third_party/llvm/SHA256SUMS",
    "sdk/third_party/llvm/lib/STATIC_LLVM.txt",
    "sdk/third_party/llvm/fixed-llc",
    f"sdk/lib/{TUPLE}/libcangjie-ast-support.a",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(file):
    h = hashlib.sha256()
    with open(file, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(file, value):
    file.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def inventory(root):
    result = {}
    for file in sorted(root.rglob("*")):
        name = file.relative_to(root).as_posix()
        if name == "language-tuple.json":
            continue
        if file.is_symlink():
            require(name in ALIASES and os.readlink(file) == ALIASES[name],
                    f"TUPLE_LINK_MISMATCH {name}")
            result[name] = {"link": os.readlink(file)}
        elif file.is_file():
            result[name] = {"sha256": digest(file), "mode": file.stat().st_mode & 0o777}
        else:
            require(file.is_dir(), f"TUPLE_FILE_TYPE {name}")
    return result


def validate_provenance(value):
    for name in ("compiler", "llvm"):
        component = value["sources"][name]
        require(re.fullmatch(r"[0-9a-f]{40}", component["commit"]), f"TUPLE_SOURCE_SHA {name}")
        require(component["repository"].startswith("https://"), f"TUPLE_SOURCE_REPOSITORY {name}")
    require(value["qualification"] == "H48-provenance-partial", "TUPLE_QUALIFICATION")
    require(value["sources"]["stdlib"]["commit"] == "unrecorded", "TUPLE_STD_SOURCE_NOT_RECORDED")
    require(value["sources"]["stdlib"]["follow_up"] == "cjcj-dev/cjcj#135", "TUPLE_STD_SOURCE_DEBT")
    for name in ("compiler", "llc", "opt"):
        require(value["sources"]["stdlib"]["inputs_sha256"][name] == value["role_sha256"][name],
                f"TUPLE_STD_INPUT {name}")
    require(value["host_sdk"]["identity"], "TUPLE_HOST_IDENTITY")
    require(value["execution"]["kind"] in ("github-actions", "retained-build"), "TUPLE_EXECUTION")
    if value["execution"]["kind"] == "github-actions":
        for field in ("run_id", "run_attempt"):
            require(int(value["execution"][field]) > 0, f"TUPLE_EXECUTION_{field}")
    else:
        require(value["execution"]["evidence"], "TUPLE_RETAINED_BUILD_EVIDENCE")
    for role in ROLES:
        require(re.fullmatch(r"[0-9a-f]{64}", value["role_sha256"][role]), f"TUPLE_ROLE_PIN {role}")


def verify(root, expected_manifest, expected_compiler):
    require(re.fullmatch(r"[0-9a-f]{64}", expected_manifest), "TUPLE_MANIFEST_PIN_REQUIRED")
    require(digest(root / "language-tuple.json") == expected_manifest, "TUPLE_MANIFEST_DIGEST_MISMATCH")
    manifest = json.loads((root / "language-tuple.json").read_text())
    require(manifest["schema"] == 1 and manifest["platform"] == TUPLE, "TUPLE_SCHEMA_MISMATCH")
    validate_provenance(manifest["provenance"])
    require(manifest["roles"] == ROLES, "TUPLE_ROLES_MISMATCH")
    require(manifest["excluded"] == list(EXCLUDED), "TUPLE_EXCLUSION_CONTRACT")
    for name in EXCLUDED:
        require(not (root / name).exists(), f"TUPLE_EXCLUDED_PAYLOAD {name}")
    actual = inventory(root)
    require(actual.keys() == manifest["files"].keys(), "TUPLE_FILE_SET_MISMATCH")
    for name, record in actual.items():
        require(record == manifest["files"][name], f"TUPLE_PAYLOAD_MISMATCH {name}")
    for role, name in ROLES.items():
        require(actual[name].get("sha256") == manifest["provenance"]["role_sha256"][role],
                f"TUPLE_ROLE_IDENTITY_MISMATCH {role}")
    payloads = manifest["provenance"]["payloads"]
    require(payloads.keys() == actual.keys(), "TUPLE_PAYLOAD_PROVENANCE_SET")
    for name, record in actual.items():
        receipt = payloads[name]
        require(receipt["origin"] in ("compiler", "llvm", "stdlib", "official-sdk"),
                f"TUPLE_PAYLOAD_ORIGIN {name}")
        expected_file = ROLES["compiler"] if name in ALIASES else name
        require(receipt["sha256"] == manifest["files"][expected_file]["sha256"],
                f"TUPLE_PROVENANCE_DIGEST {name}")
    require(actual[ROLES["compiler"]]["sha256"] == expected_compiler, "TUPLE_COMPILER_IDENTITY_MISMATCH")
    for name in ALIASES:
        require(actual.get(name) == {"link": ALIASES[name]}, f"TUPLE_COMPILER_ENTRY_MISMATCH {name}")
    return manifest


def pack(args):
    provenance = json.loads(args.provenance.read_text())
    validate_provenance(provenance)
    require(not args.output.exists(), "TUPLE_OUTPUT_EXISTS")
    root = args.output / "tuple"
    root.mkdir(parents=True)
    # Physical copies only; the compiler basename dispatch needs two local aliases.
    for name in ("bin", "include", "lib", "modules", "runtime", "third_party", "tools"):
        shutil.copytree(args.sdk / name, root / "sdk" / name, symlinks=False)
    for name in ALIASES:
        file = root / name
        file.unlink(missing_ok=True)
        file.symlink_to(ALIASES[name])
    for name in EXCLUDED:
        file = root / name
        if file.is_dir():
            shutil.rmtree(file)
        else:
            file.unlink(missing_ok=True)
    host = root / "host/runtime/lib" / TUPLE
    host.mkdir(parents=True)
    for name in ("libcangjie-runtime.so", "libboundscheck.so"):
        shutil.copy2(args.host / name, host / name)
    manifest = {"schema": 1, "platform": TUPLE, "provenance": provenance,
                "roles": ROLES, "excluded": list(EXCLUDED), "files": inventory(root)}
    write_json(root / "language-tuple.json", manifest)
    manifest_sha = digest(root / "language-tuple.json")
    verify(root, manifest_sha, provenance["role_sha256"]["compiler"])
    source = provenance["sources"]["compiler"]["commit"]
    archive = args.output / f"h48-language-tuple-linux-x86_64-{source}-provenance-partial.tar.gz"
    with tarfile.open(archive, "w:gz", dereference=False) as tar:
        tar.add(root, arcname="tuple")
    shutil.copy2(root / "language-tuple.json", args.output / "language-tuple.json")
    (args.output / "SHA256SUMS").write_text(
        f"{digest(archive)}  {archive.name}\n{manifest_sha}  language-tuple.json\n")
    print(f"TUPLE_PACKED archive={archive} manifest_sha256={manifest_sha}")


def unpack(args):
    require(digest(args.archive) == args.archive_sha256, "TUPLE_ARCHIVE_DIGEST_MISMATCH")
    require(not args.output.exists(), "TUPLE_OUTPUT_EXISTS")
    # No links may participate in path traversal during extraction. The only two
    # permitted links target a file in their own directory; install them last.
    with tarfile.open(args.archive, "r:gz") as tar:
        members = tar.getmembers()
        names = set()
        for entry in members:
            parts = Path(entry.name).parts
            require(parts and parts[0] == "tuple" and ".." not in parts
                    and not Path(entry.name).is_absolute() and entry.name not in names,
                    "TUPLE_ARCHIVE_PATH")
            names.add(entry.name)
            relative = "/".join(parts[1:])
            require(entry.isfile() or entry.isdir() or
                    (entry.issym() and ALIASES.get(relative) == entry.linkname), "TUPLE_ARCHIVE_TYPE")
        args.output.mkdir(parents=True)
        for entry in members:
            if not entry.issym():
                tar.extract(entry, args.output)
        for entry in members:
            if entry.issym():
                (args.output / entry.name).symlink_to(entry.linkname)
    verify(args.output / "tuple", args.manifest_sha256, args.compiler_sha256)
    print("TUPLE_UNPACKED_VERIFIED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    producer = commands.add_parser("pack")
    for name in ("sdk", "host", "provenance", "output"):
        producer.add_argument(f"--{name}", type=Path, required=True)
    consumer = commands.add_parser("verify")
    consumer.add_argument("--root", type=Path, required=True)
    consumer.add_argument("--env", action="store_true")
    extract = commands.add_parser("unpack")
    extract.add_argument("--archive", type=Path, required=True)
    extract.add_argument("--archive-sha256", required=True)
    extract.add_argument("--output", type=Path, required=True)
    for command in (consumer, extract):
        command.add_argument("--manifest-sha256", required=True)
        command.add_argument("--compiler-sha256", required=True)
    args = parser.parse_args()
    if args.command == "pack":
        pack(args)
    elif args.command == "unpack":
        unpack(args)
    else:
        verify(args.root, args.manifest_sha256, args.compiler_sha256)
        if args.env:
            root = args.root.resolve()
            values = {"CJC": root / "sdk/bin/cjc", "CANGJIE_HOME": root / "sdk",
                      "GC_UNIT_CJC_RUNTIME_LIB_DIR": root / "host/runtime/lib" / TUPLE}
            for key, value in values.items():
                print(f"export {key}={shlex.quote(str(value))}")
        else:
            print("TUPLE_VERIFIED")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(f"LANGUAGE_TUPLE_REJECTED: {error}", file=sys.stderr)
        sys.exit(2)
