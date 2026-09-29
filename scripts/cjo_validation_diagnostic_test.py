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
for case in ("DifferentProducerVersion", "SameProducerVersion", "UnavailableProducerVersion"):
    run = subprocess.run([str(args.elf.resolve()), "--filter=CjoValidationDiagnosticTest." + case],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (args.evidence / (case + ".log")).write_text(run.stdout)
    text = re.sub(r"\x1b\[[0-9;]*m", "", run.stdout)
    expected = re.findall(r"^FRONTEND_EXPECTED=(.*)$", text, re.M)
    observed = re.sub(r"^FRONTEND_EXPECTED=.*$", "", text, flags=re.M)
    passed = (run.returncode == 0 and len(expected) == 1
              and "FRONTEND_TARGET_BEGIN" in observed and "FRONTEND_TARGET_END" in observed
              and expected[0] in observed)
    results.append({"case": case, "rc": run.returncode,
                    "target_assertion_executed": len(expected) == 1,
                    "frontend_message_matches": len(expected) == 1 and expected[0] in observed,
                    "pass": passed})
    print(json.dumps(results[-1]), flush=True)
record = {"elf_sha256": hashlib.sha256(args.elf.read_bytes()).hexdigest(), "results": results}
(args.evidence / "result.json").write_text(json.dumps(record, indent=2) + "\n")
raise SystemExit(0 if all(result["pass"] for result in results) else 1)
