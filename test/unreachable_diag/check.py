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
log = (out / "compile.log").read_text(errors="replace")
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

else_true = line_of("return 2")
else_false = line_of("return 3")
match_case = line_of("Left(0) | Right(0)")
after = line_of("return 9")
later = line_of("keepLater(die(), 7)")
reachable_line = line_of("return 1")

failures = []

def expect(name, ok, detail):
    print(("PASS " if ok else "FAIL ") + name + " " + detail)
    if not ok:
        failures.append(name)

else_hits = count(lambda msg, line: "unreachable" in msg and line in (else_true, else_false))
expect("else-if-both-arms", else_hits == 2, f"hits={else_hits} lines={else_true},{else_false}")
pattern_hits = count(lambda msg, line: "unreachable pattern" in msg and line == match_case)
expect("match-case-once", pattern_hits == 1, f"hits={pattern_hits} line={match_case}")
after_hits = count(lambda msg, line: "unreachable" in msg and line == after)
expect("return-continuation-warned", after_hits >= 1, f"hits={after_hits} line={after}")
later_hits = count(lambda msg, line: "unreachable" in msg and line == later)
expect("nothing-later-arg", later_hits >= 1, f"hits={later_hits} line={later}")
reachable_hits = count(lambda msg, line: "unreachable" in msg and line == reachable_line and "elseIf" not in lines[line - 1])
# reachable() and elseIf both contain 'return 1'. Bind the first occurrence only.
reachable_fn = line_of("func reachable")
reachable_return = next(i for i, line in enumerate(lines, 1) if i > reachable_fn and "return 1" in line)
reachable_hits = count(lambda msg, line: "unreachable" in msg and line == reachable_return)
expect("reachable-silent", reachable_hits == 0, f"hits={reachable_hits} line={reachable_return}")

raise SystemExit(1 if failures else 0)
