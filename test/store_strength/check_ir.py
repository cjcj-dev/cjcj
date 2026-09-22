#!/usr/bin/env python3
"""Inspect retained product IR; never infer strength from a stored value's type.

--expect FUNCTION_REGEX=STRENGTH selects fixture functions, including mangled
names. All matching writes must carry that explicit i32 constant. Input and
strength assertions are independent so a missing fixture cannot hide a check.
"""
import argparse
import pathlib
import re


def split_arguments(text):
    depth = 0
    quoted = False
    escaped = False
    start = 0
    args = []
    for i, char in enumerate(text):
        if quoted:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char in '([{<':
            depth += 1
        elif char in ')]}>':
            depth -= 1
        elif char == ',' and depth == 0:
            args.append(text[start:i].strip())
            start = i + 1
    if text[start:].strip():
        args.append(text[start:].strip())
    return args


def writes(text):
    function = ''
    for line in text.splitlines():
        if line.startswith('define '):
            function = line
        if re.search(r'\b(?:call|invoke)\b', line):
            match = re.search(r'@"?llvm\.cj\.gcwrite\.ref"?\((.*)\)', line)
            if match:
                yield function, split_arguments(match[1]), line
        if line == '}':
            function = ''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ir', type=pathlib.Path)
    parser.add_argument('--expect', action='append', default=[])
    parser.add_argument('--allow-unknown', action='append', default=[],
                        help='function regex for an individually documented unresolved slot path')
    parser.add_argument('--filter', default='')
    args = parser.parse_args()
    files = sorted(args.ir.rglob('*.ll')) if args.ir.is_dir() else [args.ir]
    files = [p for p in files if p.is_file()]
    records = [record for p in files for record in writes(p.read_text())]
    failed = 0
    executed = 0

    def check(name, passed, detail):
        nonlocal failed, executed
        if args.filter and args.filter not in name:
            return
        executed += 1
        failed += not passed
        print(f'ASSERT {name}={"PASS" if passed else "FAIL"} {detail}')

    check('input.files', bool(files), f'files={len(files)}')
    check('input.writes', bool(records), f'writes={len(records)}')
    missing = sum(len(operands) == 3 for _, operands, _ in records)
    invalid = sum(len(operands) != 4 or
                  re.fullmatch(r'i32 [012]', operands[-1]) is None
                  for _, operands, _ in records)
    check('strength.explicit', bool(records) and invalid == 0,
          f'three_operand={missing} invalid={invalid} writes={len(records)}')
    unknown = [(function, line) for function, operands, line in records
               if len(operands) == 4 and operands[-1] == 'i32 0']
    unlisted = [(function, line) for function, line in unknown
                if not any(re.search(pattern, function) for pattern in args.allow_unknown)]
    check('strength.unknown', bool(records) and not unlisted,
          f'unknown={len(unknown)} unlisted={len(unlisted)}')
    for function, line in unlisted:
        print(f'UNLISTED_UNKNOWN {function}\n{line}')
    for expected in args.expect:
        pattern, strength = expected.rsplit('=', 1)
        if strength not in ('0', '1', '2'):
            parser.error('strength must be 0, 1 or 2')
        selected = [operands for function, operands, _ in records if re.search(pattern, function)]
        check(f'input.{pattern}', bool(selected), f'writes={len(selected)}')
        bad = sum(len(operands) != 4 or operands[-1] != f'i32 {strength}' for operands in selected)
        check(f'strength.{pattern}', bool(selected) and bad == 0,
              f'expected={strength} writes={len(selected)} mismatches={bad}')
    print(f'IR_RESULT checks={executed} failures={failed} writes={len(records)}')
    return int(failed != 0 or executed == 0)


if __name__ == '__main__':
    raise SystemExit(main())
