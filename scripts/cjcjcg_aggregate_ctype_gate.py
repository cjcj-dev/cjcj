#!/usr/bin/env python3
"""Compile aggregate/CType fixtures and check product-emitted LLVM IR."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "cjcjcg_aggregate_ctype_fixtures"
ALL_CHECKS = {
    "stackNestedRef",
    "heapGCRead",
    "globalGCRead",
    "fixedArrayNoRefControl",
    "nativeAggregateRead",
    "nativeAggregateWrite",
    "illegalCTypeRef",
    "baselessAS1FailClosed",
    "structureString",
    "trackedArrayScalar",
    "trackedArrayStruct",
    "trackedNestedArrayStruct",
    "trackedStructArray",
}


@dataclass
class FixtureRun:
    name: str
    compile_rc: int
    ir: str
    run_rc: int | None


def function_slices(ir: str, needle: str) -> list[str]:
    functions = re.findall(r"^define [^\n]*\n.*?(?=^define |\Z)", ir, re.MULTILINE | re.DOTALL)
    return [function for function in functions if needle in function.split("\n", 1)[0]]


def require_function(ir: str, needle: str, body_needle: str | None = None) -> str:
    matches = function_slices(ir, needle)
    if body_needle is not None:
        matches = [function for function in matches if body_needle in function]
    if not matches:
        suffix = "" if body_needle is None else f" containing {body_needle}"
        raise AssertionError(f"missing generated function {needle}{suffix}")
    return "\n".join(matches)


def require_compiled(run: FixtureRun) -> str:
    if run.compile_rc != 0 or "define " not in run.ir:
        raise AssertionError(f"{run.name} cjc rc={run.compile_rc}; no usable product IR")
    return run.ir


def require_fixture(run: FixtureRun) -> str:
    ir = require_compiled(run)
    if run.run_rc != 0:
        raise AssertionError(f"{run.name} executable rc={run.run_rc}")
    return ir


def require_typed_fields(function: str, name: str, *, managed_leaf: bool) -> None:
    if "typed.copy.src.field" not in function or "typed.copy.dst.field" not in function:
        raise AssertionError(f"{name} did not recurse through struct fields")
    if "typed.copy.leaf" not in function:
        raise AssertionError(f"{name} emitted no typed leaf load")
    if not re.search(r"\bstore\b", function):
        raise AssertionError(f"{name} emitted no typed leaf store")
    if managed_leaf and not re.search(r"load [^\n]*addrspace\(1\)\*", function):
        raise AssertionError(f"{name} lost the managed reference leaf type")


def compile_fixture(compiler: str, out: pathlib.Path, name: str) -> FixtureRun:
    fixture_out = out / name
    fixture_out.mkdir(parents=True, exist_ok=True)
    temps = fixture_out / "temps"
    temps.mkdir(parents=True, exist_ok=True)
    is_tracked_array = name.startswith("tracked_")
    executable = fixture_out / (f"{name}.a" if is_tracked_array else name)
    output_options = ["--output-type=staticlib"] if is_tracked_array else []
    compiled = subprocess.run(
        [compiler, "-g", "--dump-ir", "--dump-to-screen", "--save-temps", str(temps),
         *output_options, "-o", str(executable),
         str(FIXTURES / f"{name}.cj")],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    (fixture_out / "compile.log").write_text(compiled.stdout)
    (fixture_out / "compile.rc").write_text(f"{compiled.returncode}\n")
    run_rc = None
    run_log = ("not run: static library fixture\n" if compiled.returncode == 0 and is_tracked_array
               else "not run: compile failed\n")
    if compiled.returncode == 0 and not is_tracked_array:
        executed = subprocess.run(
            [str(executable)], cwd=ROOT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, check=False,
        )
        run_rc = executed.returncode
        run_log = executed.stdout
    (fixture_out / "run.log").write_text(run_log)
    (fixture_out / "run.rc").write_text("NOT_RUN\n" if run_rc is None else f"{run_rc}\n")
    return FixtureRun(name, compiled.returncode, compiled.stdout, run_rc)


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
    parser.add_argument("--source-root", default=ROOT, type=pathlib.Path)
    parser.add_argument("--structure-ir", type=pathlib.Path)
    parser.add_argument(
        "--select",
        help="comma-separated checks; default runs every check (StructureString only with --structure-ir)",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    selected = set(ALL_CHECKS)
    if args.select:
        selected = set(args.select.split(","))
        unknown = selected - ALL_CHECKS
        if unknown:
            parser.error(f"unknown checks: {','.join(sorted(unknown))}")

    fixture_for_check = {
        "stackNestedRef": "ref_stack_heap",
        "heapGCRead": "ref_stack_heap",
        "globalGCRead": "ref_global",
        "fixedArrayNoRefControl": "noref_fixed",
        "nativeAggregateRead": "native_aggregate",
        "nativeAggregateWrite": "native_aggregate",
        "structureString": "structure_string",
        "trackedArrayScalar": "tracked_array_scalar",
        "trackedArrayStruct": "tracked_array_struct",
        "trackedNestedArrayStruct": "tracked_nested_array_struct",
        "trackedStructArray": "tracked_struct_array",
    }
    fixture_names = sorted({fixture_for_check[name] for name in selected if name in fixture_for_check})
    fixtures = {name: compile_fixture(args.compiler, args.out, name) for name in fixture_names}
    checks = []

    if "stackNestedRef" in selected:
        def stack_ref() -> None:
            fixture = fixtures["ref_stack_heap"]
            ir = require_compiled(fixture)
            function = require_function(ir, "stackRead")
            require_typed_fields(function, "RefOuterValue.stackRead", managed_leaf=True)
            if fixture.run_rc != 0:
                raise AssertionError(f"ref_stack_heap executable rc={fixture.run_rc}")

        checks.append(("stackNestedRef", stack_ref))

    if "heapGCRead" in selected:
        def heap_ref() -> None:
            ir = require_compiled(fixtures["ref_stack_heap"])
            function = require_function(ir, "heapRead")
            if "llvm.cj.gcread.struct" not in function:
                raise AssertionError("tracked heap aggregate bypassed gcread.struct")

        checks.append(("heapGCRead", heap_ref))

    if "globalGCRead" in selected:
        def global_ref() -> None:
            ir = require_fixture(fixtures["ref_global"])
            function = require_function(ir, "globalRefRead")
            if "llvm.cj.gcread.static.struct" not in function:
                raise AssertionError("global reference aggregate bypassed gcread.static.struct")

        checks.append(("globalGCRead", global_ref))

    if "fixedArrayNoRefControl" in selected:
        def fixed_array_control() -> None:
            ir = require_fixture(fixtures["noref_fixed"])
            function = require_function(ir, "main")
            if "llvm.memcpy" not in function:
                raise AssertionError("no-reference aggregate lost its independent legal raw-copy control")

        checks.append(("fixedArrayNoRefControl", fixed_array_control))

    tracked_array_checks = {
        "trackedArrayScalar": ("tracked_array_scalar", "NoRefArrayHolder4read"),
        "trackedArrayStruct": ("tracked_array_struct", "ArrayStructHolder4read"),
        "trackedNestedArrayStruct": ("tracked_nested_array_struct", "NestedArrayStructHolder4read"),
        "trackedStructArray": ("tracked_struct_array", "StructArrayHolder9readItems"),
    }
    for check_name, (fixture_name, function_name) in tracked_array_checks.items():
        if check_name not in selected:
            continue

        def tracked_array(check_name=check_name, fixture_name=fixture_name,
                          function_name=function_name) -> None:
            ir = require_compiled(fixtures[fixture_name])
            function = require_function(ir, function_name)
            if "llvm.cj.copy.no.ref.struct" not in function:
                raise AssertionError(f"{check_name} bypassed copy.no.ref.struct")
            if "llvm.memcpy.p0i8.p1i8" in function:
                raise AssertionError(f"{check_name} emitted a raw AS1-to-AS0 memcpy")
            if "llvm.cj.gcread" in function:
                raise AssertionError(f"{check_name} no-ref array was routed through gcread")
            if "cjcj.copy.no.ref.array." not in ir:
                raise AssertionError(f"{check_name} lost its named array metadata wrapper")

        checks.append((check_name, tracked_array))

    if "nativeAggregateRead" in selected:
        def native_read() -> None:
            ir = require_fixture(fixtures["native_aggregate"])
            function = require_function(ir, "NativePairE4readHl", "ptr.read.addr")
            require_typed_fields(function, "CPointer<NativePair>.read", managed_leaf=False)
            if "llvm.cj.gcread" in function:
                raise AssertionError("native CType read was routed through managed gcread")
            if "llvm.memcpy" in function:
                raise AssertionError("native CType read retained a whole-object memcpy")
            array_functions = [candidate for candidate in function_slices(ir, "4readHl")
                               if "ptr.read.addr" in candidate and "typed.copy.src.element" in candidate]
            if not array_functions:
                raise AssertionError("CPointer<VArray>.read did not recurse through typed elements")

        checks.append(("nativeAggregateRead", native_read))

    if "nativeAggregateWrite" in selected:
        def native_write() -> None:
            ir = require_fixture(fixtures["native_aggregate"])
            function = require_function(ir, "NativePairE5writeHl", "ptr.write.addr")
            require_typed_fields(function, "CPointer<NativePair>.write", managed_leaf=False)
            if "llvm.cj.gcwrite" in function:
                raise AssertionError("native CType write was routed through managed gcwrite")
            if "llvm.memcpy" in function:
                raise AssertionError("native CType write retained a whole-object memcpy")
            array_functions = [candidate for candidate in function_slices(ir, "5writeHl")
                               if "ptr.write.addr" in candidate and "typed.copy.src.element" in candidate]
            if not array_functions:
                raise AssertionError("CPointer<VArray>.write did not recurse through typed elements")

        checks.append(("nativeAggregateWrite", native_write))

    if "illegalCTypeRef" in selected:
        illegal_out = args.out / "illegal"
        illegal = subprocess.run(
            [args.compiler, "--output-type=staticlib", "-o", str(illegal_out),
             str(FIXTURES / "illegal_c_ref.cj")],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        (args.out / "illegal.log").write_text(illegal.stdout)
        (args.out / "illegal.rc").write_text(f"{illegal.returncode}\n")

        def illegal_c_ref() -> None:
            if illegal.returncode == 0:
                raise AssertionError("@C struct with managed String field was accepted")
            if "error" not in illegal.stdout.lower():
                raise AssertionError("illegal @C struct produced no error diagnostic")

        checks.append(("illegalCTypeRef", illegal_c_ref))

    if "baselessAS1FailClosed" in selected:
        def product_source() -> None:
            source = (args.source_root / "packages" / "codegen" / "src" / "IRBuilder.cj").read_text()
            create_load = source[source.index("public func CreateLoad(elementType:"):]
            create_load = create_load[:create_load.index("public func CreateLoad(elementType:", 20)]
            if "DeRef(resultType).SatisfyCType()" not in source:
                raise AssertionError("CType discriminator is not the CHIR semantic predicate")
            diagnostic = "non-CType reference aggregate load has addrspace(1) source without managed base"
            if diagnostic not in create_load:
                raise AssertionError("baseless AS1 aggregate guard is disconnected from CreateLoad")
            guard = "containsRef && !isCTypeAggregate && sourceAddressSpace == 1u32"
            if guard not in create_load:
                raise AssertionError("baseless AS1 guard no longer distinguishes reference aggregate from CType")

        checks.append(("baselessAS1FailClosed", product_source))

    if "structureString" in selected:
        structure_ir = (args.structure_ir.read_text() if args.structure_ir is not None
                        else require_fixture(fixtures["structure_string"]))

        def structure_string() -> None:
            function = require_function(structure_ir, "StructureStringE4readHl", "ptr.read.addr")
            require_typed_fields(function, "StructureString.read", managed_leaf=False)
            if "llvm.memcpy" in function or "llvm.cj.gcread" in function:
                raise AssertionError("StructureString representative is not a native typed-leaf read")

        checks.append(("structureString", structure_string))

    results = dict(run_check(name, check) for name, check in checks)
    (args.out / "results.json").write_text(json.dumps(results, sort_keys=True, indent=2) + "\n")
    return 0 if results and all(value == "PASS" for value in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
