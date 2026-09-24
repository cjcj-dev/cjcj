#!/usr/bin/env python3
"""Check real emitted function bodies for known-strength runtime entries."""
import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('disassembly', type=Path)
    args = parser.parse_args()
    functions = {}
    current = None
    for line in args.disassembly.read_text().splitlines():
        header = re.match(r'^[0-9a-fA-F]+ <([^>]+)>:$', line)
        if header:
            current = header[1]
            functions[current] = []
        elif current:
            functions[current].append(line)
    failures = 0
    for target in ('aggregateStringStore', 'aggregateReferenceStore', 'ordinaryReferenceStore'):
        bodies = ['\n'.join(body) for name, body in functions.items() if target in name]
        strong = sum('CJ_MCC_WriteRefField_Strong@' in body for body in bodies)
        unknown = sum('CJ_MCC_WriteRefField@' in body for body in bodies)
        passed = bool(bodies) and strong == len(bodies) and unknown == 0
        failures += not passed
        print(f'ASSERT elf.{target}={"PASS" if passed else "FAIL"} '
              f'functions={len(bodies)} strong={strong} unknown={unknown}')
    print(f'ELF_RESULT checks=3 failures={failures}')
    return int(failures != 0)


if __name__ == '__main__':
    raise SystemExit(main())
