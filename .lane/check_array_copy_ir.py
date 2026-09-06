#!/usr/bin/env python3
"""Check product-emitted array-copy calls in one compiler arm."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


CALL_RE = re.compile(
    r"\b(?:call|invoke)\b[^\n]*@"
    r"(llvm\.(?:cj\.array\.copy\.[A-Za-z0-9_.]+|memmove|memcpy)\.[^\s(]+)"
)
TARGET_ZERO_COPY_RE = re.compile(
    r"^\s*(?:call|invoke)\b[^\n]*@"
    r"(llvm\.(?:cj\.array\.copy\.[A-Za-z0-9_.]+|memmove\.p1)[^\s(]*)"
    r"\((.*)\)",
    re.MULTILINE,
)


def calls(path: pathlib.Path) -> list[str]:
    return CALL_RE.findall(path.read_text(errors="replace"))


def has(items: list[str], needle: str) -> bool:
    return any(needle in item for item in items)


def zero_copy_lines(path: pathlib.Path) -> list[tuple[str, str]]:
    return TARGET_ZERO_COPY_RE.findall(path.read_text(errors="replace"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm", choices=("candidate", "broken", "restored"), required=True)
    parser.add_argument("--dir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    observed = {name: calls(args.dir / name / "compile.log") for name in (
        "primitive", "noref_struct", "ref_elements", "zero_layout"
    )}
    failures: list[str] = []

    no_ref_want = "llvm.cj.array.copy.struct" if args.arm == "broken" else "llvm.memmove"
    for name in ("primitive", "noref_struct"):
        if not has(observed[name], no_ref_want):
            failures.append(f"{name}: missing {no_ref_want}; calls={observed[name]}")

    if not has(observed["ref_elements"], "llvm.cj.array.copy.ref"):
        failures.append(f"ref_elements: missing copy.ref; calls={observed['ref_elements']}")
    if not has(observed["ref_elements"], "llvm.cj.array.copy.struct"):
        failures.append(f"ref_elements: missing copy.struct; calls={observed['ref_elements']}")

    # The sibling zero-layout change may remove the call entirely.  Until composed,
    # any target copy still emitted by this isolated change must remain a zero-byte no-op.
    zero_targets = zero_copy_lines(args.dir / "zero_layout" / "compile.log")
    for name, arguments in zero_targets:
        if "i64 0" not in arguments:
            failures.append(f"zero_layout: nonzero target copy {name}({arguments})")

    result = {
        "arm": args.arm,
        "calls": observed,
        "zero_target_calls": zero_targets,
        "failures": failures,
    }
    (args.dir / "ir-results.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    for name, items in observed.items():
        print(f"{name}: {items}")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 1
    print(f"PASS ir-dispatch arm={args.arm}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
