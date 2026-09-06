#!/usr/bin/env python3
"""Exercise zero/nonzero aggregate copy lowering with a built cjcj compiler."""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "cjcjcg_zero_layout_copy_fixtures"
REJECTION = "llvm.cj.copy.no.ref.struct size must be a nonzero constant"


def compile_fixture(compiler: pathlib.Path, out: pathlib.Path, name: str) -> tuple[int, str, int | None, str]:
    case = out / name
    case.mkdir(parents=True, exist_ok=True)
    executable = case / name
    command = [
        str(compiler), "-O2", "--dump-ir", "--dump-to-screen", "--save-temps", str(case / "temps"),
        "-o", str(executable), str(FIXTURES / f"{name}.cj"),
    ]
    compiled = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, check=False)
    (case / "compile.command").write_text("\0".join(command) + "\0")
    (case / "compile.log").write_text(compiled.stdout)
    (case / "compile.rc").write_text(f"{compiled.returncode}\n")
    run_rc = None
    run_log = "not run: compile failed\n"
    if compiled.returncode == 0:
        executed = subprocess.run([str(executable)], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, check=False)
        run_rc = executed.returncode
        run_log = executed.stdout
    (case / "run.log").write_text(run_log)
    (case / "run.rc").write_text("NOT_RUN\n" if run_rc is None else f"{run_rc}\n")
    return compiled.returncode, compiled.stdout, run_rc, run_log


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--source-root", default=ROOT, type=pathlib.Path)
    parser.add_argument("--invalid-rc", type=pathlib.Path)
    parser.add_argument("--invalid-log", type=pathlib.Path)
    args = parser.parse_args()
    if (args.invalid_rc is None) != (args.invalid_log is None):
        parser.error("--invalid-rc and --invalid-log must be supplied together")
    args.out.mkdir(parents=True, exist_ok=True)

    runs = {
        name: compile_fixture(args.compiler, args.out, name)
        for name in ("zero_side_effect", "nonzero_noref", "reference_aggregate")
    }
    results: dict[str, str] = {}

    def run_check(name: str, predicate) -> None:
        try:
            predicate()
        except AssertionError as error:
            results[name] = "FAIL"
            print(f"FAIL {name}: {error}")
        else:
            results[name] = "PASS"
            print(f"PASS {name}")

    def zero_noop() -> None:
        compile_rc, ir, run_rc, run_log = runs["zero_side_effect"]
        check(compile_rc == 0, f"compile rc={compile_rc}")
        check(run_rc == 0, f"run rc={run_rc}")
        check("ZERO_LAYOUT_SIDE_EFFECT_OK count=1" in run_log, "operand side-effect marker missing")
        check("llvm.cj.copy.no.ref.struct" not in ir, "zero-layout copy was still emitted")

    def nonzero_copy() -> None:
        compile_rc, ir, run_rc, run_log = runs["nonzero_noref"]
        check(compile_rc == 0, f"compile rc={compile_rc}")
        check(run_rc == 0, f"run rc={run_rc}")
        check("NONZERO_NOREF_COPY_OK" in run_log, "runtime marker missing")
        check("llvm.cj.copy.no.ref.struct" in ir, "nonzero no-ref typed copy was not emitted")

    def reference_copy() -> None:
        compile_rc, ir, run_rc, run_log = runs["reference_aggregate"]
        check(compile_rc == 0, f"compile rc={compile_rc}")
        check(run_rc == 0, f"run rc={run_rc}")
        check("REFERENCE_AGGREGATE_COPY_OK" in run_log, "runtime marker missing")
        check("llvm.cj.gcread.struct" in ir, "reference aggregate left its GC-read path")

    def shim_guard_source() -> None:
        source = (args.source_root / "runtime_shim" / "cjselfhost_llvmshim.cpp").read_text()
        check(REJECTION in source, "zero-size shim contract guard changed or disappeared")

    run_check("zeroLayoutNoopPreservesOperandSideEffect", zero_noop)
    run_check("nonzeroNoRefCopyUnchanged", nonzero_copy)
    run_check("referenceAggregateCopyUnchanged", reference_copy)
    run_check("shimZeroSizeGuardSourcePresent", shim_guard_source)

    if args.invalid_rc is not None and args.invalid_log is not None:
        def invalid_rejected() -> None:
            rc = int(args.invalid_rc.read_text().strip())
            log = args.invalid_log.read_text()
            check(rc != 0, "known-invalid zero-size emission unexpectedly succeeded")
            check(REJECTION in log, "known-invalid arm missed the exact shim rejection")

        run_check("shimRejectsKnownInvalidZeroSizeEmission", invalid_rejected)

    (args.out / "results.json").write_text(json.dumps(results, indent=2, sort_keys=True) + "\n")
    return 0 if results and all(value == "PASS" for value in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
