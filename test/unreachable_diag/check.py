#!/usr/bin/env python3
"""Bind stage1 diagnostics to the unreachable-region invariants.

The compiler log is the product result. Each assertion names the source line
it requires, so an earlier crash or a missing warning fails that assertion
instead of a setup check.
"""
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
profile = sys.argv[2] if len(sys.argv) > 2 else "o0"
if profile not in ("o0", "o2"):
    raise SystemExit("unknown profile " + profile)
log = re.sub(r"\x1b\[[0-9;]*m", "", (out / "compile.log").read_text(errors="replace"))
source = (Path(__file__).resolve().parent / "fixture.cj").read_text()
lines = source.splitlines()

def line_of(text):
    for index, line in enumerate(lines, 1):
        if text in line:
            return index
    raise SystemExit("marker missing: " + text)

warnings = []
for match in re.finditer(r"warning: ([^\n]+)\n(?:.*\n){0,3}?.*?fixture\.cj:(\d+):\d+", log):
    warnings.append((match.group(1).strip(), int(match.group(2))))
if not warnings:
    for match in re.finditer(r"fixture\.cj:(\d+):\d+: warning: ([^\n]+)", log):
        warnings.append((match.group(2).strip(), int(match.group(1))))

(out / "warnings.txt").write_text("".join(f"{line}: {msg}\n" for msg, line in warnings))
print("PARSED", len(warnings))
for msg, line in warnings:
    print(f"  {line}: {msg}")

def count(predicate):
    return sum(1 for msg, line in warnings if predicate(msg, line))

else_if = line_of("else if (false)")
else_arm = line_of("else-if false arm")
after = line_of("return 9")
later = line_of("keepLater(die(), 7)")
split_case = line_of("Left(1) | Left(2)")

failures = []

def expect(name, ok, detail):
    print(("PASS " if ok else "FAIL ") + name + " " + detail)
    if not ok:
        failures.append(name)

expect("compiler-completed", (out / "compile.rc").read_text().strip() == "0", "compile.rc=" + (out / "compile.rc").read_text().strip())
outer_return = line_of("return match (x)")
outer_hits = count(lambda msg, line: "unreachable expression" in msg and line == outer_return)
if profile == "o0":
    expect("outer-return-not-skipped", outer_hits == 1, f"hits={outer_hits} line={outer_return}")

else_if_hits = count(lambda msg, line: "unreachable block in 'if'" in msg and line == else_if)
else_arm_hits = count(lambda msg, line: "unreachable block in 'if'" in msg and line == else_arm)
expect("else-if-true-arm", else_if_hits == 1, f"hits={else_if_hits} line={else_if}")
expect("else-if-false-arm", else_arm_hits == 1, f"hits={else_arm_hits} line={else_arm}")
after_hits = count(lambda msg, line: "unreachable expression" in msg and line == after)
expect("return-continuation-warned", after_hits == 1, f"hits={after_hits} line={after}")
later_hits = count(lambda msg, line: "unreachable expression" in msg and line == later)
expect("nothing-later-arg", later_hits == 1, f"hits={later_hits} line={later}")
call_hits = count(lambda msg, line: "unreachable 'call'" in msg and line == later)
expect("nothing-call-warning", call_hits == 1, f"hits={call_hits} line={later}")
split_hits = count(lambda msg, line: "unreachable" in msg and line == split_case)
constructor_case = line_of("Left(1) | Right(2)")
constructor_hits = count(lambda msg, line: "unreachable" in msg and line == constructor_case)
if profile == "o0":
    expect("match-split-once", split_hits == 1, f"hits={split_hits} line={split_case}")
else:
    expect("match-constructors-once", constructor_hits == 1, f"hits={constructor_hits} line={constructor_case}")
reachable_fn = line_of("func reachable")
reachable_return = next(i for i, line in enumerate(lines, 1) if i > reachable_fn and "return 1" in line)
reachable_hits = count(lambda msg, line: "unreachable" in msg and line == reachable_return)
expect("reachable-silent", reachable_hits == 0, f"hits={reachable_hits} line={reachable_return}")

raise SystemExit(1 if failures else 0)
