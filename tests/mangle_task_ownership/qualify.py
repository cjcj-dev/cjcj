#!/usr/bin/env python3
"""Install observation-only P0 fixture into a disposable compiler source copy.

No qualification predicate rejects an input. Inspect the observations before
enabling the deterministic synchronization fixture or claiming input eligibility.
"""
import argparse
import difflib
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    parser.add_argument('--diff', type=Path, required=True)
    args = parser.parse_args()
    path = args.tree / 'packages/frontend/src/CompilerInstance.cj'
    original = path.read_text()
    needle = '        DoMangling(baseMangler, parallelNum, topDecls)'
    if original.count(needle) != 1:
        raise SystemExit('expected one real mangling dispatcher')
    modified = original.replace(needle,
        '        MangleOwnershipQualification(topDecls, parallelNum)\n' + needle)
    fixture = path.with_name('MangleOwnershipQualification.cj')
    if fixture.exists():
        raise SystemExit('qualification fixture already installed')
    shutil.copyfile(Path(__file__).with_name('Qualification.cj'), fixture)
    path.write_text(modified)
    args.diff.write_text(''.join(difflib.unified_diff(
        original.splitlines(True), modified.splitlines(True),
        fromfile='a/packages/frontend/src/CompilerInstance.cj',
        tofile='b/packages/frontend/src/CompilerInstance.cj')))


if __name__ == '__main__':
    main()
