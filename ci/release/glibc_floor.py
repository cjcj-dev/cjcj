#!/usr/bin/env python3
"""Compare Linux release ELF version needs with an untouched official SDK.

P8: cangjie_build/docs/linux.md:55-60 describes the old Linux build hosts.
The ABI ceiling comes from each official file, not the builder's libc version.
Only version *needs* count; exported version definitions do not require libc.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOTS = ("bin", "tools/bin", "runtime/lib", "third_party/llvm/bin")
# sdk_build.sh installs the self-host entry under this name. Both entry symlinks
# and its backing ELF have the ABI contract of the official bin/cjc.
REFERENCE_NAMES = {"bin/cjcj-stage1": "bin/cjc"}


def digest(file):
    value = hashlib.sha256()
    with file.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def contained(file, root):
    resolved = file.resolve(strict=True)
    try:
        resolved.relative_to(root)
    except ValueError:
        raise ValueError("path escapes SDK: {}".format(file))
    return resolved


def files_below(directory, root, ancestors=()):
    resolved = contained(directory, root)
    if resolved in ancestors:
        raise ValueError("directory symlink cycle: {}".format(directory))
    if not resolved.is_dir():
        raise ValueError("required scan directory is not a directory: {}".format(directory))
    for file in sorted(directory.iterdir()):
        target = contained(file, root)
        if target.is_dir():
            yield from files_below(file, root, ancestors + (resolved,))
        elif target.is_file():
            yield file
        else:
            raise ValueError("unsupported SDK entry: {}".format(file))


def version_key(name):
    return tuple(int(part) for part in name[len("GLIBC_"):].split("."))


def inspect_elf(file):
    with file.open("rb") as stream:
        header = stream.read(20)
    if header[:4] != b"\x7fELF":
        return None
    if len(header) != 20 or header[4] not in (1, 2) or header[5] not in (1, 2):
        raise ValueError("invalid ELF header: {}".format(file))
    result = subprocess.run(
        ["readelf", "--version-info", "--wide", str(file)],
        env=dict(os.environ, LC_ALL="C"), universal_newlines=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True,
    )
    if result.stderr.strip():
        raise ValueError("readelf diagnostic for {}: {}".format(file, result.stderr.strip()))
    # GNU readelf separates version definitions, symbols, and needs. Exported
    # GLIBC_* names in definitions must never raise the dependency ceiling.
    needs = set()
    in_needs = False
    for line in result.stdout.splitlines():
        if line.startswith("Version "):
            in_needs = line.startswith("Version needs section ")
        if in_needs:
            match = re.search(r"\bName: (GLIBC_[A-Za-z0-9_.]+)\b", line)
            if match:
                needs.add(match.group(1))
    numeric = sorted((name for name in needs if re.fullmatch(r"GLIBC_[0-9]+(?:\.[0-9]+)+", name)), key=version_key)
    return {
        "sha256": digest(file),
        "elf_class": header[4],
        "machine": int.from_bytes(header[18:20], "little" if header[5] == 1 else "big"),
        "needs": sorted(needs),
        "maximum": numeric[-1] if numeric else None,
        "non_numeric": sorted(needs - set(numeric)),
    }


def compare_sdk(candidate, official):
    candidate = Path(candidate).resolve(strict=True)
    official = Path(official).resolve(strict=True)
    rows = []
    for scope in ROOTS:
        # Fail on missing scopes instead of reporting an empty scan as green.
        try:
            contained(official / scope, official)
            files = list(files_below(candidate / scope, candidate))
        except (OSError, ValueError) as error:
            rows.append({"path": scope, "status": "error", "reason": str(error)})
            continue
        for file in files:
            relative = file.relative_to(candidate).as_posix()
            reference_name = REFERENCE_NAMES.get(relative, relative)
            row = {"path": relative, "reference": reference_name}
            try:
                actual = inspect_elf(file)
                row["candidate"] = actual
                reference = official / reference_name
                if actual is None:
                    # A script replacing an official ELF is not evidence that
                    # the compiler's ABI requirements have disappeared.
                    if reference.exists():
                        contained(reference, official)
                        if inspect_elf(reference) is not None:
                            raise ValueError("official ELF replaced by non-ELF")
                    row.update(status="not-elf", reason="non-ELF payload (script, PE, Mach-O or data)")
                else:
                    contained(reference, official)
                    expected = inspect_elf(reference)
                    row["official"] = expected
                    if expected is None:
                        raise ValueError("no official ELF counterpart")
                    if (actual["machine"], actual["elf_class"]) != (expected["machine"], expected["elf_class"]):
                        raise ValueError("ELF architecture differs from official counterpart")
                    unknown = set(actual["non_numeric"]) - set(expected["non_numeric"])
                    if unknown or "GLIBC_PRIVATE" in actual["needs"]:
                        row.update(status="rejected", reason="unsupported GLIBC requirements: {}".format(sorted(unknown | ({"GLIBC_PRIVATE"} & set(actual["needs"])))))
                    elif actual["maximum"] and (not expected["maximum"] or version_key(actual["maximum"]) > version_key(expected["maximum"])):
                        row.update(status="rejected", reason="{} exceeds official {}".format(actual["maximum"], expected["maximum"]))
                    else:
                        row["status"] = "accepted"
            except (OSError, ValueError, subprocess.CalledProcessError) as error:
                row.update(status="error", reason=str(error))
            rows.append(row)
    elf_count = sum(row.get("candidate") is not None for row in rows)
    failures = [row["path"] for row in rows if row["status"] in ("rejected", "error")]
    if elf_count == 0:
        failures.append("no ELF payload inspected")
    return {
        "schema": 1, "candidate_root": str(candidate), "official_root": str(official),
        "scopes": list(ROOTS), "elf_count": elf_count, "failures": failures,
        "passed": not failures, "files": rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--official", required=True)
    parser.add_argument("--json", required=True, help="persistent per-file result, including SHA256 identities")
    args = parser.parse_args()
    try:
        report = compare_sdk(args.candidate, args.official)
    except (OSError, ValueError) as error:
        report = {"schema": 1, "passed": False, "failures": [str(error)], "files": []}
    Path(args.json).write_text(json.dumps(report, indent=2) + "\n")
    for row in report["files"]:
        if row["status"] in ("error", "rejected"):
            print("GLIBC_FLOOR_REJECT {}: {}".format(row["path"], row["reason"]), file=sys.stderr)
    print("GLIBC_FLOOR {} elf={} failures={} report={}".format(
        "PASS" if report["passed"] else "FAIL", report.get("elf_count", 0), len(report["failures"]), args.json))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
