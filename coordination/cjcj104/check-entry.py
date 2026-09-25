#!/usr/bin/env python3
"""Check actual installed entries; invoke on kkk2 with PREFIX and contract root."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys

prefix, root = map(Path, sys.argv[1:])
env = dict(os.environ, PATH=f"{prefix}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
expected_sha = "34bc6627675906f8431892630b5e91fc4cc9f1e03ce15e9716025aa551e5c823"
failures = 0
for trial in range(1, 4):
    checks = [
        ("absolute-node", [str(prefix / "bin/node"), "--version"], "v20.19.0"),
        ("path-node", ["node", "--version"], "v20.19.0"),
        ("env-node", ["/usr/bin/env", "node", "--version"], "v20.19.0"),
        ("npm", ["npm", "--version"], "10.8.2"),
        ("npx", ["npx", "--version"], "10.8.2"),
        ("mjs-contract", ["node", "--test", str(root / "ci/sccache/report.test.mjs")], "# pass 6"),
        ("shebang-consumer", [str(root / "ci/sccache/report.mjs"), "--stats",
                              str(root / "ci/sccache/fixtures-stats-v0.18.0.json"),
                              "--component", "runtime", "--platform", "linux-x64",
                              "--require-compiles"], "requests=2 hits=1 misses=1"),
    ]
    for name, args, expected in checks:
        result = subprocess.run(args, env=env, text=True, capture_output=True)
        valid = (result.stdout.strip() == expected if name in
                 {"absolute-node", "path-node", "env-node", "npm", "npx"}
                 else expected in result.stdout)
        passed = result.returncode == 0 and valid
        failures += not passed
        print(f"ASSERT trial={trial} name={name} process_rc={result.returncode} verdict={'PASS' if passed else 'FAIL'}", flush=True)
        print(result.stdout, end="")
        print(result.stderr, end="")
actual_sha = hashlib.sha256((prefix / "bin/node").read_bytes()).hexdigest()
passed = actual_sha == expected_sha and not (prefix / "bin/node").is_symlink()
failures += not passed
print(f"ASSERT node-physical-sha256={actual_sha} verdict={'PASS' if passed else 'FAIL'}")
print(f"RESULT assertions=22 failures={failures}")
sys.exit(bool(failures))
