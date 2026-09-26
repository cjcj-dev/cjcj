#!/usr/bin/env python3
"""Byte-compare JavaImpl javagen output with nightly goldens."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


CASES = (
    ("impl_user", "Child.java"),
    ("prop_user", "Counter.java"),
    ("static_user", "Calc.java"),
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--compiler", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    here = Path(__file__).resolve().parent
    stubs = here.parent / "java_aftertypecheck"
    a.out.mkdir(parents=True, exist_ok=True)
    result = {
        "compiler": str(a.compiler),
        "compiler_sha256": sha(a.compiler),
        "affinity": sorted(os.sched_getaffinity(0)),
        "uptime_before": subprocess.check_output(["uptime"], text=True).strip(),
        "cases": {},
    }
    failed = False
    for name, java_name in CASES:
        dest = a.out / name
        imports = dest / "imports"
        (imports / "java").mkdir(parents=True, exist_ok=True)
        javagen = dest / "javagen"
        javagen.mkdir(parents=True, exist_ok=True)
        logs = dest / "logs"
        logs.mkdir(exist_ok=True)

        def compile_one(src, extra):
            command = [str(a.compiler), str(src), "--import-path", str(imports),
                       "--output-type=staticlib", "--diagnostic-format=noColor", *extra]
            with (logs / (src.stem + ".log")).open("w") as log:
                run = subprocess.run(command, cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=180)
            return run.returncode

        internal_rc = compile_one(stubs / "internal.cj",
                                  ["--output-dir", str(imports / "java"), "-o", "internal.a"])
        lang_rc = compile_one(stubs / "lang.cj",
                              ["--output-dir", str(imports / "java"), "-o", "lang.a"])
        user_rc = compile_one(here / (name + ".cj"),
                              ["--output-javagen-dir", str(javagen), "-o", "out.a"])
        produced = javagen / java_name
        golden = here / "golden" / java_name
        print("ASSERT java bytes " + java_name, flush=True)
        same = produced.is_file() and produced.read_bytes() == golden.read_bytes()
        print(("PASS " if same else "FAIL ") + java_name, flush=True)
        if not same:
            failed = True
        result["cases"][name] = {
            "java": java_name,
            "internal_rc": internal_rc,
            "lang_rc": lang_rc,
            "user_rc": user_rc,
            "produced": produced.is_file(),
            "bytes_equal": same,
        }
    result["uptime_after"] = subprocess.check_output(["uptime"], text=True).strip()
    result["passed"] = not failed
    (a.out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
