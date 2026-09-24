#!/usr/bin/env python3
"""Observe BeforeTypeCheck generated declarations in a real compiler AST dump.

This intentionally ends at an unresolved-type diagnostic. It must not be used as
proof that the AfterTypeCheck registry/member relocation pipeline has executed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def run(argv, directory, output):
    started = time.monotonic()
    with output.open("wb") as stream:
        result = subprocess.run(argv, cwd=directory, stdout=stream, stderr=subprocess.STDOUT)
    return {"argv": argv, "rc": result.returncode, "wall": time.monotonic() - started}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent / "objc_registry_fixtures"
    imports = work / "imports" / "objc"
    imports.mkdir(parents=True, exist_ok=True)
    records = {"compiler": str(compiler), "sha256": hashlib.sha256(compiler.read_bytes()).hexdigest()}
    records["internal"] = run([str(compiler), str(fixtures / "objc_internal.cj"),
        "--module-name", "objc.internal", "--output-type=staticlib",
        "--output-dir", str(imports), "-o", "internal.a"], work, work / "internal.log")
    if records["internal"]["rc"]:
        (work / "result.json").write_text(json.dumps(records, indent=2))
        print("NOT_RUN declaration assertions: fixture module compilation failed", flush=True)
        return 2
    records["declarations"] = run([str(compiler), str(fixtures / "before_typecheck.cj"),
        "--import-path", str(work / "imports"), "--dump-ast", "--dump-to-screen",
        "--diagnostic-format=noColor", "--output-type=staticlib", "-o", "declarations.a"],
        work, work / "declarations.log")
    dump = (work / "declarations.log").read_text(errors="replace")
    # Every assertion records actual observations, including the semantic frontier.
    sections = re.split(r"(?=ClassDecl: )", dump)
    def section(name):
        return next((s for s in sections if s.startswith("ClassDecl: " + name + " {")), "")
    companion = section("Exported$reg")
    wrapper = section("Protocol$wrap")
    checks = {
        "expected_semantic_frontier": records["declarations"]["rc"] == 1 and "MissingRegistryFixtureType" in dump.split("Package:", 1)[0],
        "registry_companion_decl": bool(companion) and "OBJ_C_IMPL_REGISTRY_COMPANION" in companion,
        "registry_companion_visibility": bool(companion) and "PUBLIC" in companion and "OPEN" in companion,
        "interface_handle_wrapper_decl": bool(wrapper) and "OBJ_C_MIRROR_INTERFACE_HANDLE_WRAPPER" in wrapper,
        "ordinary_class_observed": bool(section("Ordinary")),
        "ordinary_has_no_companion": not bool(section("Ordinary$reg")),
    }
    records["checks"] = checks
    (work / "result.json").write_text(json.dumps(records, indent=2))
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {name} actual={passed}", flush=True)
    print("SCOPE=BeforeTypeCheck declarations only; AfterTypeCheck relocation not verified")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
