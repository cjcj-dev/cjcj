#!/usr/bin/env python3
"""Assert real frontend diagnostic output from the compiler unittest ELF.

Run separately per case so an unrelated emitted message cannot satisfy a case.
The ELF and product archives must be built from the tested source revision.
"""
from collections import Counter
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
    expected_count = 0 if case == "ValidDependencyHeader" else (5 if case == "DifferentProducerVersion" else 4)
    target_executed = ("IMPORT_TARGET loaded=true expected=true" in text if expected_count == 0
                       else len(expected) == expected_count and "FRONTEND_TARGET_BEGIN" in text
                       and "FRONTEND_TARGET_END" in text)
    matches = Counter(observed) == Counter(expected)
    passed = run.returncode == 0 and target_executed and matches
    results.append({"case": case, "rc": run.returncode,
                    "target_assertion_executed": target_executed,
                    "observed_frontend_messages": observed,
                    "frontend_message_matches": matches,
                    "pass": passed})
    print(json.dumps(results[-1]), flush=True)
record = {"elf_sha256": hashlib.sha256(args.elf.read_bytes()).hexdigest(), "results": results}
(args.evidence / "result.json").write_text(json.dumps(record, indent=2) + "\n")
raise SystemExit(0 if all(result["pass"] for result in results) else 1)
