#!/usr/bin/env python3
"""Stage1 diagnostics for VArray type-alias calls.

The compiler under test is the product executable. This script does not rebuild
a type checker. Each named assertion prints before its predicate so a failing
target stays visible.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*m")
MISMATCH = "mismatched types"
ARGS_MSG = "'VArray' constructor accepts only one argument"
ICE = "begin of range is zero"


def plain_text(text):
    return ANSI.sub("", text)


def summary(log):
    rows = [
        line
        for line in log.splitlines()
        if line.startswith("error:") or ICE in line or "Internal Compiler Error" in line
    ]
    return " | ".join(rows[:6]) or log[-400:]


def caret_detail(plain, needle):
    lines = plain.splitlines()
    for index, line in enumerate(lines):
        if needle not in line or "|" not in line:
            continue
        if not re.match(r"^\s*\d+\s*\|", line):
            continue
        if index + 1 >= len(lines) or "^" not in lines[index + 1]:
            return False, f"no caret after {line!r}"
        source_at = line.index(needle)
        caret_at = lines[index + 1].index("^")
        if source_at != caret_at:
            return False, f"caret {caret_at} != {needle!r} at {source_at} in {line!r}"
        return True, f"column {caret_at}"
    return False, f"source line containing {needle!r} not found"


def trailing_span(plain):
    lines = plain.splitlines()
    for index, line in enumerate(lines):
        if "Alias(1)" not in line or not re.match(r"^\s*\d+\s*\|", line):
            continue
        if index + 1 >= len(lines) or "^" not in lines[index + 1]:
            return False, f"no caret after {line!r}"
        caret = lines[index + 1]
        source_at = line.index("(")
        caret_at = caret.index("^")
        if source_at != caret_at:
            return False, f"caret {caret_at} != '(' at {source_at} in {line!r}"
        run = len(caret[caret_at:]) - len(caret[caret_at:].lstrip("^"))
        paren_only = line.index(")") - source_at + 1
        if run <= paren_only:
            return False, f"caret run {run} does not pass ')' in {line!r}"
        return True, f"column {caret_at} run {run}"
    return False, "source line containing 'Alias(1)' not found"


def compile_one(compiler, fixture, dest):
    dest.mkdir(parents=True, exist_ok=True)
    command = [
        str(compiler),
        str(fixture),
        "--output-type=staticlib",
        "-o",
        str(dest / "out.a"),
    ]
    start = time.monotonic()
    process = subprocess.run(
        command,
        cwd=dest,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    log = plain_text(process.stdout)
    (dest / "compile.log").write_text(process.stdout)
    (dest / "compile.plain").write_text(log)
    (dest / "compile.rc").write_text(str(process.returncode) + "\n")
    return {
        "command": command,
        "rc": process.returncode,
        "log": log,
        "wall": time.monotonic() - start,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent / "varray_source_diag_fixtures"
    names = [
        "alias_mismatch",
        "alias_zero",
        "alias_two",
        "direct_mismatch",
        "direct_zero",
        "alias_trail",
        "well_typed",
    ]
    before = subprocess.check_output(["uptime"], text=True).strip()
    compiled = {}
    for name in names:
        compiled[name] = compile_one(compiler, fixtures / (name + ".cj"), out / name)

    results = []

    def check(name, passed, detail):
        print("EXECUTED " + name, flush=True)
        status = "PASS" if passed else "FAIL"
        print(f"ASSERT {name} {status} {detail}", flush=True)
        results.append({"name": name, "pass": passed, "detail": detail, "executed": True})

    mismatch = compiled["alias_mismatch"]["log"]
    mismatch_ok = (
        MISMATCH in mismatch
        and "VArray<Int32, $2>" in mismatch
        and "VArray<Int64, $2>" in mismatch
        and "alias_mismatch.cj:4:" in mismatch
        and ICE not in mismatch
    )
    check("alias_mismatch_reported", mismatch_ok, "on source call" if mismatch_ok else summary(mismatch))

    zero = compiled["alias_zero"]["log"]
    zero_msg = ARGS_MSG in zero and ICE not in zero
    check("alias_zero_message", zero_msg, "arg-count diagnostic" if zero_msg else summary(zero))
    zero_paren, zero_detail = caret_detail(zero, "(")
    check("alias_zero_paren", zero_paren, zero_detail)

    two = compiled["alias_two"]["log"]
    two_msg = ARGS_MSG in two and ICE not in two
    check("alias_two_message", two_msg, "arg-count diagnostic" if two_msg else summary(two))
    two_paren, two_detail = caret_detail(two, "(")
    check("alias_two_paren", two_paren, two_detail)

    trail = compiled["alias_trail"]["log"]
    trail_msg = ARGS_MSG in trail and ICE not in trail
    check("alias_trail_message", trail_msg, "arg-count diagnostic" if trail_msg else summary(trail))
    trail_span, trail_detail = trailing_span(trail)
    check("alias_trail_span", trail_span, trail_detail)

    direct = compiled["direct_mismatch"]["log"]
    direct_ok = (
        MISMATCH in direct
        and "VArray<Int32, $2>" in direct
        and "VArray<Int64, $2>" in direct
        and ICE not in direct
    )
    check("direct_mismatch_reported", direct_ok, "direct VArray" if direct_ok else summary(direct))

    direct_zero = compiled["direct_zero"]["log"]
    direct_caret, direct_caret_detail = caret_detail(direct_zero, "(")
    direct_zero_ok = ARGS_MSG in direct_zero and ICE not in direct_zero and direct_caret
    check(
        "direct_zero_paren",
        direct_zero_ok,
        direct_caret_detail if direct_zero_ok else summary(direct_zero) + " " + direct_caret_detail,
    )

    well = compiled["well_typed"]
    well_ok = well["rc"] == 0 and "error:" not in well["log"]
    check("well_typed_compiles", well_ok, "rc=0" if well_ok else f"rc={well['rc']} {summary(well['log'])}")

    manifest = {
        "compiler": str(compiler),
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "affinity": sorted(os.sched_getaffinity(0)),
        "uptime_before": before,
        "uptime_after": subprocess.check_output(["uptime"], text=True).strip(),
        "cases": {
            name: {"rc": item["rc"], "wall": item["wall"], "command": item["command"]}
            for name, item in compiled.items()
        },
        "assertions": results,
    }
    (out / "result.json").write_text(json.dumps(manifest, indent=2) + "\n")
    failed = [item["name"] for item in results if not item["pass"]]
    print(f"SUMMARY pass={len(results) - len(failed)} fail={len(failed)} failed={failed}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
