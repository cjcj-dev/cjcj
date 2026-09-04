#!/usr/bin/env python3
"""Check CPointer generic payload lowering, ABI, and verifier-report deltas."""

from __future__ import annotations

import argparse
import collections
import csv
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Callable


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "cjcjcg_cpointer_payload_fixtures"
REPORT_FIELDS = (
    "module", "function", "rule", "instruction", "dest_as", "src_as",
    "length", "dest_root", "src_root", "source_type",
)
PROVENANCE_RULE = "Bare memcpy/memmove payload provenance is unknown"


class Checks:
    def __init__(self) -> None:
        self.results: list[dict[str, object]] = []

    def check(self, name: str, passed: bool, detail: str) -> None:
        self.results.append({"name": name, "passed": passed, "detail": detail})
        print(f"{'PASS' if passed else 'FAIL'} {name}: {detail}")

    def run(self, name: str, action: Callable[[], None]) -> None:
        try:
            action()
        except (AssertionError, OSError, ValueError) as error:
            self.check(name, False, str(error))
        else:
            self.check(name, True, "ok")


def brace_block(text: str, marker: str) -> str:
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError(f"unterminated block after {marker}")


def function_slice(ir: str, needle: str) -> str:
    definitions = list(re.finditer(r"^define\b[^\n]*\{[\s\S]*?^}", ir, re.MULTILINE))
    matches = [match.group(0) for match in definitions if needle in match.group(0).splitlines()[0]]
    if not matches:
        raise AssertionError(f"missing generated function {needle}")
    return "\n".join(matches)


def source_checks(checks: Checks, source_root: pathlib.Path, expectation: str) -> None:
    builder = (source_root / "packages/codegen/src/IRBuilder.cj").read_text()
    dispatcher = (source_root / "packages/codegen/src/IntrinsicsDispatcher.cj").read_text()
    wrapper = brace_block(builder, "public func CallGCReadGenericPayload(")
    read = brace_block(dispatcher, "private func CPointerRead(")
    write = brace_block(dispatcher, "private func CPointerWrite(")
    read_generic = brace_block(read, "if (resultTy.IsGeneric())")
    write_generic = brace_block(write, "if (valueTy.IsGeneric())")

    wrapper_tokens = (
        'GCREAD_GENERIC_PAYLOAD_INTRINSIC_NAME: String = "llvm.cj.gcread.generic.payload"',
        "LLVMPointerType(i8Type, 0u32)",
        "LLVMPointerType(i8Type, 1u32)",
        "LLVMInt32TypeInContext(GetLLVMContext().raw)",
        "LLVMVoidTypeInContext(GetLLVMContext().raw)",
        "cgMod.GetOrInsertFunction(GCREAD_GENERIC_PAYLOAD_INTRINSIC_NAME, functionType)",
        "CreateZExtOrTrunc(size, sizeType",
        "CreateCall(function, functionType, args)",
    )
    exact_declaration = "CreateIntrinsicCallNoInvoke" not in wrapper
    checks.check("source.wrapper-abi", all(token in builder if token.startswith("GCREAD_") else token in wrapper
        for token in wrapper_tokens) and exact_declaration,
        "void(dst=i8*AS0,obj=i8*AS1,size=i32) exact external declaration")

    read_typed = "CallGCWriteGenericPayloadFromSrc(ret, gep, resultTySize, typeInfoOfResult)" in read_generic
    read_raw = "CreateMemCpy" in read_generic
    write_typed = "CallGCReadGenericPayload(addr, value.GetRawValue(), valueTySize)" in write_generic
    write_raw = "GetPayloadFromObject" in write_generic or "CreateMemCpy" in write_generic
    expect_read = expectation != "read-cut"
    expect_write = expectation != "write-cut"
    checks.check("source.read", read_typed == expect_read and read_raw != expect_read,
        f"expected={'helper' if expect_read else 'memcpy'} helper={int(read_typed)} raw={int(read_raw)}")
    checks.check("source.write", write_typed == expect_write and write_raw != expect_write,
        f"expected={'helper' if expect_write else 'memcpy'} helper={int(write_typed)} raw={int(write_raw)}")

    read_order = [read_generic.find(token) for token in (
        "ptr.read.offset", 'name: "ele.ptr"', "CJ_MCC_AsanRead",
    )]
    write_order = [write_generic.find(token) for token in (
        "ptr.write.offset", 'name: "ele.ptr"', "CJ_MCC_AsanWrite",
    )]
    checks.check("source.read-asan-order", all(index >= 0 for index in read_order) and read_order == sorted(read_order),
        f"positions={read_order}")
    checks.check("source.write-asan-order", all(index >= 0 for index in write_order) and write_order == sorted(write_order),
        f"positions={write_order}")


def compile_fixture(checks: Checks, compiler: pathlib.Path, output: pathlib.Path,
                    run_library_path: str | None) -> None:
    output.mkdir(parents=True, exist_ok=True)
    executable = output / "cpointer_payload"
    proc = subprocess.run([
        str(compiler), "-g", "--dump-ir", "--dump-to-screen", "-o", str(executable),
        str(FIXTURES / "cpointer_payload.cj"),
    ], cwd=ROOT, env=os.environ.copy(), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False)
    (output / "compile.log").write_text(proc.stdout)
    (output / "compile.rc").write_text(f"{proc.returncode}\n")
    checks.check("fixture.compile", proc.returncode == 0 and "define " in proc.stdout,
        f"rc={proc.returncode} ir={int('define ' in proc.stdout)}")
    if proc.returncode != 0:
        return
    run_env = os.environ.copy()
    if run_library_path:
        run_env["LD_LIBRARY_PATH"] = run_library_path
    run = subprocess.run([str(executable)], cwd=ROOT, env=run_env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    (output / "run.log").write_text(run.stdout)
    (output / "run.rc").write_text(f"{run.returncode}\n")
    checks.check("fixture.identity", run.returncode == 0 and "CPOINTER_PAYLOAD_OK" in run.stdout,
        f"rc={run.returncode} token={int('CPOINTER_PAYLOAD_OK' in run.stdout)}")
    read = function_slice(proc.stdout, "readGeneric")
    write = function_slice(proc.stdout, "writeGeneric")
    checks.check("fixture.read-call", "_CNatXPG_4readH" in read, "generic wrapper calls CPointer.read")
    checks.check("fixture.write-call", "_CNatXPG_5writeH" in write, "generic wrapper calls CPointer.write")


def core_checks(checks: Checks, core_ir_path: pathlib.Path, expectation: str) -> None:
    ir = core_ir_path.read_text()
    read = function_slice(ir, "_CNatXPG_4readH")
    write = function_slice(ir, "_CNatXPG_5writeH")
    read_helper = "llvm.cj.gcwrite.generic.payload" in read
    read_raw = bool(re.search(r"llvm\.memcpy\.p1[^\n]*\.p0", read))
    write_helper = "llvm.cj.gcread.generic.payload" in write
    write_raw = bool(re.search(r"llvm\.memcpy\.p0[^\n]*\.p1", write))
    expect_read = expectation != "read-cut"
    expect_write = expectation != "write-cut"
    checks.check("ir.read", read_helper == expect_read and read_raw != expect_read,
        f"expected={'helper' if expect_read else 'memcpy'} helper={int(read_helper)} raw={int(read_raw)}")
    checks.check("ir.write", write_helper == expect_write and write_raw != expect_write,
        f"expected={'helper' if expect_write else 'memcpy'} helper={int(write_helper)} raw={int(write_raw)}")


def call_signature(path: pathlib.Path) -> tuple[str, str, str]:
    line = next(line.strip() for line in path.read_text().splitlines()
        if "call void @llvm.cj.gcread.generic.payload" in line)
    match = re.search(r"payload\((.+)\)$", line)
    if not match:
        raise ValueError(f"cannot parse payload call in {path}")
    args = [arg.strip() for arg in match.group(1).split(",")]
    if len(args) != 3:
        return tuple(args)  # type: ignore[return-value]
    return tuple(arg.rsplit(" ", 1)[0] for arg in args)  # type: ignore[return-value]


def abi_rules(path: pathlib.Path) -> collections.Counter[str]:
    signature = call_signature(path)
    failures: collections.Counter[str] = collections.Counter()
    if len(signature) != 3:
        failures["expects-dst-obj-size"] += 1
        return failures
    dst, obj, size = signature
    if "*" not in dst or "addrspace(1)" in dst:
        failures["dst-native"] += 1
    if "*" not in obj or "addrspace(1)" not in obj:
        failures["obj-managed"] += 1
    if size != "i32":
        failures["size-i32"] += 1
    return failures


def abi_checks(checks: Checks, opt: pathlib.Path, output: pathlib.Path) -> None:
    expected = {
        "abi-good.ll": collections.Counter(),
        "abi-bad-dst.ll": collections.Counter({"dst-native": 1}),
        "abi-bad-obj.ll": collections.Counter({"obj-managed": 1}),
    }
    output.mkdir(parents=True, exist_ok=True)
    for name, wanted in expected.items():
        found = abi_rules(FIXTURES / name)
        checks.check(f"abi.rules.{name}", found == wanted,
            f"violations={dict(found)} expected={dict(wanted)}")
        proc = subprocess.run([
            str(opt), "-passes=cj-ir-verifier", "-disable-output", str(FIXTURES / name),
        ], cwd=ROOT, env=os.environ.copy(), text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, check=False)
        (output / f"{name}.opt.log").write_text(proc.stdout)
        (output / f"{name}.opt.rc").write_text(f"{proc.returncode}\n")
        should_pass = name == "abi-good.ll"
        checks.check(f"abi.strict.{name}", (proc.returncode == 0) == should_pass,
            f"rc={proc.returncode} expected={'zero' if should_pass else 'nonzero'}")


def read_report(path: pathlib.Path) -> list[tuple[str, ...]]:
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if tuple(reader.fieldnames or ()) != REPORT_FIELDS:
            raise ValueError(f"{path}: expected exact ten-field header")
        return [tuple(row[field] for field in REPORT_FIELDS) for row in reader]


def target(row: tuple[str, ...]) -> str:
    values = dict(zip(REPORT_FIELDS, row))
    if not values["rule"].startswith(PROVENANCE_RULE) or values["instruction"] not in {"memcpy", "memmove"}:
        return ""
    function = values["function"]
    if "_CNatXPG_4readH" in function and values["dest_as"] == "1" and values["src_as"] == "0":
        return "read"
    if "_CNatXPG_5writeH" in function and values["dest_as"] == "0" and values["src_as"] == "1":
        return "write"
    return ""


def subtract(left: collections.Counter[tuple[str, ...]],
             right: collections.Counter[tuple[str, ...]]) -> list[tuple[str, ...]]:
    return list((left - right).elements())


def report_checks(checks: Checks, baseline_path: pathlib.Path, candidate_path: pathlib.Path,
                  expectation: str) -> None:
    baseline_rows = read_report(baseline_path)
    candidate_rows = read_report(candidate_path)
    baseline = collections.Counter(baseline_rows)
    candidate = collections.Counter(candidate_rows)
    removed = subtract(baseline, candidate)
    added = subtract(candidate, baseline)
    baseline_targets = collections.Counter(target(row) for row in baseline_rows if target(row))
    candidate_targets = collections.Counter(target(row) for row in candidate_rows if target(row))
    removed_targets = collections.Counter(target(row) or "other" for row in removed)
    expected_removed = {
        "green": {"read", "write"}, "read-cut": {"write"}, "write-cut": {"read"},
    }[expectation]
    checks.check("report.baseline-positive", baseline_targets["read"] > 0 and baseline_targets["write"] > 0,
        f"read={baseline_targets['read']} write={baseline_targets['write']}")
    checks.check("report.new-empty", not added, f"NEW={len(added)}")
    checks.check("report.other-stable", removed_targets["other"] == 0,
        f"removed_other={removed_targets['other']}")
    for direction in ("read", "write"):
        if direction in expected_removed:
            passed = candidate_targets[direction] == 0 and removed_targets[direction] == baseline_targets[direction]
            detail = (f"baseline={baseline_targets[direction]} candidate={candidate_targets[direction]} "
                      f"removed={removed_targets[direction]}")
        else:
            passed = candidate_targets[direction] == baseline_targets[direction] and removed_targets[direction] == 0
            detail = f"baseline={baseline_targets[direction]} candidate={candidate_targets[direction]} kept=1"
        checks.check(f"report.{direction}", passed, detail)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=pathlib.Path, default=ROOT)
    parser.add_argument("--expect", choices=("green", "read-cut", "write-cut"), default="green")
    parser.add_argument("--compiler", type=pathlib.Path)
    parser.add_argument("--run-library-path")
    parser.add_argument("--core-ir", type=pathlib.Path)
    parser.add_argument("--opt", type=pathlib.Path)
    parser.add_argument("--baseline-report", type=pathlib.Path)
    parser.add_argument("--candidate-report", type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if bool(args.baseline_report) != bool(args.candidate_report):
        parser.error("--baseline-report and --candidate-report must be paired")

    checks = Checks()
    source_checks(checks, args.source_root.resolve(), args.expect)
    if args.compiler:
        compile_fixture(checks, args.compiler.resolve(), args.out.resolve() / "fixture",
                        args.run_library_path)
    if args.core_ir:
        core_checks(checks, args.core_ir.resolve(), args.expect)
    if args.opt:
        abi_checks(checks, args.opt.resolve(), args.out.resolve() / "abi")
    if args.baseline_report:
        report_checks(checks, args.baseline_report.resolve(), args.candidate_report.resolve(), args.expect)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "results.json").write_text(json.dumps(checks.results, indent=2, sort_keys=True) + "\n")
    return 0 if all(bool(result["passed"]) for result in checks.results) else 1


if __name__ == "__main__":
    sys.exit(main())
