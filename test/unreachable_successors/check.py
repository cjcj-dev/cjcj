#!/usr/bin/env python3
"""Exercise unreachable analysis through the real compiler, including CHIR branches.

The generic StringBuilder overload specializes its type-match into unreachable
CHIR regions containing Branch users. The non-generic overload is the control.
CANGJIE_HOME and the runtime/library paths must describe the supplied compiler.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--out", type=Path, required=True)
parser.add_argument("--jobs", type=int, default=1)
args = parser.parse_args()
compiler = args.compiler.resolve()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
results = []
for name in ("branch", "ordinary", "diagnostic"):
    target = out / name
    target.mkdir(exist_ok=True)
    archive = target / (name + ".a")
    archive.unlink(missing_ok=True)
    command = [str(compiler), str(Path(__file__).resolve().with_name(name + ".cj")),
               "--output-type=staticlib", "-O0" if name == "diagnostic" else "-O2", "-j" + str(args.jobs), "-o", str(archive)]
    start = time.monotonic()
    with (target / "compile.log").open("w") as log:
        run = subprocess.run(command, cwd=target, stdout=log, stderr=subprocess.STDOUT)
    (target / "compile.rc").write_text(str(run.returncode) + "\n")
    text = (target / "compile.log").read_text(errors="replace")
    archive_ok = archive.is_file() and archive.read_bytes()[:8] == b"!<arch>\n"
    ok = run.returncode == 0 and "NoneValueException" not in text and archive_ok
    if name == "diagnostic":
        clean_log = re.sub(r"\x1b\[[0-9;]*m", "", text)
        # The outer return's source expression is selected by this analysis;
        # binding the warning to line 2 distinguishes the DCE reporter's other
        # unreachable warnings from this phase's observable result.
        warning = re.search(r"warning: unreachable expression\n(?:.*\n){0,3}?.*?diagnostic\.cj:2:", clean_log)
        ok = ok and warning is not None
    # This assertion always executes, including when compilation throws. There
    # is no earlier fatal setup assertion that could hide the product result.
    print(f"{'PASS' if ok else 'FAIL'} {name}-typed-operands "
          f"compiler_rc={run.returncode} archive={archive_ok}", flush=True)
    results.append(dict(name=name, command=command, rc=run.returncode, passed=ok,
                        target_exception="NoneValueException" in text and "AllUsersIsExprKind" in text,
                        archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest() if archive.is_file() else None,
                        wall=time.monotonic() - start))
(out / "result.json").write_text(json.dumps(dict(
    compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
    cases=results), indent=2) + "\n")
raise SystemExit(0 if all(row["passed"] for row in results) else 1)
