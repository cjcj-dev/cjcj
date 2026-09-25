#!/usr/bin/env python3
import pathlib
import re
import sys

FP_OPCODES = ("fadd", "fsub", "fmul", "fdiv", "frem", "fneg", "fcmp")
FLAG_TOKENS = (" fast", " nnan", " ninf", " reassoc", " nsz", " arcp", " contract", " afn")
INST_RE = re.compile(r"^\s*(fadd|fsub|fmul|fdiv|frem|fneg|fcmp|add)\b(.*)$")


def instruction_lines(root: pathlib.Path):
    found = []
    files = sorted(root.rglob("*.ll"))
    for path in files:
        for lineno, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            match = INST_RE.match(line)
            if match is None:
                continue
            found.append((match.group(1), line.rstrip(), f"{path}:{lineno}"))
    return files, found


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("on", "off"):
        print("usage: check.py <ll-root> <on|off>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1])
    mode = sys.argv[2]
    files, found = instruction_lines(root)
    print(f"LL_FILES={len(files)}")
    counts = {name: 0 for name in (*FP_OPCODES, "add")}
    failures = []
    target_ran = {name: 0 for name in FP_OPCODES}
    integer_ran = 0
    for opcode, line, where in found:
        if opcode == "add":
            integer_ran += 1
            counts["add"] += 1
            if " fast" in line:
                failures.append(f"INTEGER_ADD_HAS_FAST {where} {line}")
            continue
        counts[opcode] += 1
        has_fast = " fast" in line
        has_partial = any(token in line for token in FLAG_TOKENS if token != " fast")
        target_ran[opcode] += 1
        print(f"ASSERT_RAN target={opcode}_fast mode={mode} hit=1 where={where}")
        if mode == "on":
            if not has_fast:
                failures.append(f"MISSING_FAST {opcode} {where} {line}")
            if has_partial:
                failures.append(f"PARTIAL_FLAGS {opcode} {where} {line}")
        else:
            if has_fast or has_partial:
                failures.append(f"UNEXPECTED_FLAGS {opcode} {where} {line}")
    for opcode in FP_OPCODES:
        print(f"ASSERT_RAN_SUMMARY opcode={opcode} executed={target_ran[opcode]} mode={mode}")
        if counts[opcode] == 0:
            failures.append(f"MISSING_OPCODE {opcode}")
    print(f"ASSERT_RAN target=integer_add_without_fast executed={integer_ran} mode={mode}")
    if counts["add"] == 0:
        failures.append("MISSING_OPCODE add")
    for opcode in (*FP_OPCODES, "add"):
        print(f"COUNT {opcode}={counts[opcode]}")
    if failures:
        print(f"FAIL n={len(failures)}")
        for item in failures:
            print(item)
        return 1
    print(f"PASS mode={mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
