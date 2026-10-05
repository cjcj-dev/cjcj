#!/usr/bin/env python3
"""Assert real frontend diagnostic output from the compiler unittest ELF.

Run separately per case so an unrelated emitted message cannot satisfy a case.
The ELF and product archives must be built from the tested source revision.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--elf", type=Path, required=True)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
results = []
for case in ("DifferentProducerVersion", "SameProducerVersion", "UnavailableProducerVersion",
             "EmptyPackageNameUsesPath", "EmptyPackageNameAndPathUsesUnknown", "ValidDependencyHeader"):
    run = subprocess.run([str(args.elf.resolve()), "--no-color", "--show-all-output", "--no-progress", "--filter=CjoValidationDiagnosticTest." + case],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (args.evidence / (case + ".log")).write_text(run.stdout)
    text = re.sub(r"\x1b\[[0-9;]*m", "", run.stdout)
    expected = re.findall(r"^FRONTEND_EXPECTED=(.*)$", text, re.M)
    observed = re.findall(r"^\s*error: (validation of (?:ast|cached type) file .*?)\s*$", text, re.M)
    # DiagnosticEngine may render the same diagnostic immediately and again
    # during category emission. Only the real Cangjie assertions decide it.
    target_executed = bool(re.search(
        r"\[ (?:PASSED|FAILED) \] CASE: " + re.escape(case) + r"(?: \(|$)", text))
    summary = re.search(r"Summary: TOTAL: (\d+)\s+PASSED: (\d+), SKIPPED: (\d+), ERROR: (\d+)\s+FAILED: (\d+)", text)
    complete = summary is not None and tuple(map(int, summary.groups())) in (
        (9, 1, 8, 0, 0), (9, 0, 8, 0, 1))
    passed = run.returncode == 0 and target_executed and complete
    results.append({"case": case, "rc": run.returncode,
                    "target_assertion_executed": target_executed,
                    "observed_frontend_messages": observed,
                    "complete_case_summary": complete,
                    "pass": passed})
    print(json.dumps(results[-1]), flush=True)
# Existing version-query tests protect successful verification and the normal
# CJO compatibility gate while the new cases target failed verification.
regression = subprocess.run([str(args.elf.resolve()), "--no-color", "--show-all-output", "--no-progress",
                             "--filter=CjoVersionTest.*"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
(args.evidence / "CjoVersionTest.log").write_text(regression.stdout)
cases = ["CjoVersionQueryOnLoader", "MissingVersionQueryOnLoader", "HeaderVersionQueryAndGate"]
text = re.sub(r"\x1b\[[0-9;]*m", "", regression.stdout)
executed = all(re.search(r"\[ (?:PASSED|FAILED) \] CASE: " + case + r"(?: \(|$)", text) for case in cases)
summary = re.search(r"Summary: TOTAL: (\d+)\s+PASSED: (\d+), SKIPPED: (\d+), ERROR: (\d+)\s+FAILED: (\d+)", text)
complete = summary is not None and tuple(map(int, summary.groups())) == (9, 3, 6, 0, 0)
results.append({"case": "CjoVersionTest.*", "rc": regression.returncode,
                "target_assertion_executed": executed,
                "complete_case_summary": complete,
                "pass": regression.returncode == 0 and executed and complete})
print(json.dumps(results[-1]), flush=True)
record = {"elf_sha256": hashlib.sha256(args.elf.read_bytes()).hexdigest(), "results": results}
(args.evidence / "result.json").write_text(json.dumps(record, indent=2) + "\n")
raise SystemExit(0 if all(result["pass"] for result in results) else 1)
