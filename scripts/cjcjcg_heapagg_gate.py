#!/usr/bin/env python3
"""Compile the heap-aggregate fixture and check product-emitted LLVM IR.

The gate deliberately names every checked item.  Fault arms can therefore prove
that disconnecting either product exit turns red only the items carried by that
exit while reference and constant-array controls stay green.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "scripts" / "cjcjcg_heapagg_fixtures" / "heapagg_roots.cj"


def function_slice(ir: str, needle: str) -> str:
    matches = list(re.finditer(r"^define [^\n]*" + re.escape(needle), ir, re.MULTILINE))
    if not matches:
        raise AssertionError(f"missing generated function {needle}")
    start = matches[0].start()
    end = ir.find("\ndefine ", start + 1)
    return ir[start:] if end < 0 else ir[start:end]


def require_recursive_typed_copy(function: str, name: str) -> None:
    if "typed.copy.src.field" not in function or "typed.copy.dst.field" not in function:
        raise AssertionError(f"{name} did not descend through struct fields")
    if "typed.copy.src.element" not in function or "typed.copy.dst.element" not in function:
        raise AssertionError(f"{name} did not descend through the fixed array")
    if "typed.copy.leaf" not in function:
        raise AssertionError(f"{name} emitted no typed leaf loads")
    if re.search(r"llvm\.mem(?:cpy|move)\.p1", function):
        raise AssertionError(f"{name} retained a whole-object managed-destination copy")
    if not re.search(r"store [^\n]*addrspace\(1\)\*", function):
        raise AssertionError(f"{name} emitted no typed leaf store to AS1")


def require_plain_typed_copy(function: str, name: str) -> None:
    if "typed.copy.src.field" not in function or "typed.copy.dst.field" not in function:
        raise AssertionError(f"{name} did not use ArrayImpl's concrete struct fallback")
    if "typed.copy.src.element" not in function or "typed.copy.dst.element" not in function:
        raise AssertionError(f"{name} did not recursively copy its fixed array")


def run_check(name: str, check) -> tuple[str, str]:
    try:
        check()
    except AssertionError as error:
        print(f"FAIL {name}: {error}")
        return name, "FAIL"
    print(f"PASS {name}")
    return name, "PASS"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    output = args.out / "heapagg_roots"
    proc = subprocess.run(
        [
            args.compiler,
            "-g",
            "--dump-ir",
            "--dump-to-screen",
            "-o",
            str(output),
            str(FIXTURE),
        ],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    (args.out / "compile.log").write_text(proc.stdout)
    (args.out / "compile.rc").write_text(f"{proc.returncode}\n")
    if proc.returncode != 0 or "define " not in proc.stdout:
        print(f"FAIL compilerRun: cjc rc={proc.returncode}; no usable product IR")
        return 2

    run = subprocess.run(
        [str(output)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    (args.out / "run.log").write_text(run.stdout)
    (args.out / "run.rc").write_text(f"{run.returncode}\n")
    if run.returncode != 0:
        print(f"FAIL fixtureRun: executable rc={run.returncode}")
        return 2

    checks: list[tuple[str, object]] = []
    checks.append(("callRoot", lambda: require_recursive_typed_copy(
        function_slice(proc.stdout, "callRoot"), "callRoot")))
    checks.append(("phiRoot", lambda: require_recursive_typed_copy(
        function_slice(proc.stdout, "phiRoot"), "phiRoot")))
    checks.append(("argumentSource", lambda: require_recursive_typed_copy(
        function_slice(proc.stdout, "updateFromArgument"), "argumentSource")))
    checks.append(("allocaSource", lambda: require_recursive_typed_copy(
        function_slice(proc.stdout, "updateFromAlloca"), "allocaSource")))
    checks.append(("arrayImplExit", lambda: require_plain_typed_copy(
        function_slice(proc.stdout, "arrayImplExit"), "arrayImplExit")))

    def ref_control() -> None:
        function = function_slice(proc.stdout, "HeapAggRefHolder6update")
        if "llvm.cj.gcwrite.struct" not in function:
            raise AssertionError("reference-bearing aggregate bypassed gcwrite.struct")

    checks.append(("refControl", ref_control))

    def const_array_control() -> None:
        function = function_slice(proc.stdout, "constArrayControl")
        if "$const_array" not in function:
            raise AssertionError("constant-array neighbour lost its $const_array global")
        has_raw = (
            "llvm.memmove.p1" in function
            or "llvm.cj.array.copy" in function
            or "llvm.memcpy" in function
        )
        if not has_raw:
            raise AssertionError("constant-array neighbour lost its bulk copy")
        if "typed.copy." in function:
            raise AssertionError("constant-array neighbour was captured by the typed aggregate copier")

    checks.append(("constArrayControl", const_array_control))
    results = dict(run_check(name, check) for name, check in checks)
    (args.out / "results.json").write_text(json.dumps(results, sort_keys=True, indent=2) + "\n")
    return 0 if all(value == "PASS" for value in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
