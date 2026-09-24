#!/usr/bin/env python3
"""Temporary compiler assertion arm for #200; never modifies the shipped tree.

Run against a disposable copy of the candidate. --cut restores one rejected
append before the same assertion. The input must have the migrated contract.
"""
import argparse
import difflib
import hashlib
from pathlib import Path

SITES = {
    'const-literal': ('ConstEval.cj',
        '                    if (!constant.IsConstantNull()) {', 'block', 'constant'),
    'lambda-debug': ('ClosureConversion.cj',
        '            globalFunc.GetEntryBlock().getOrThrow().InsertExprIntoHead(debugExpr)',
        'globalFunc.GetEntryBlock().getOrThrow()', 'debugExpr'),
    'env-allocate': ('ClosureConversion.cj',
        '        parent.InsertExprIntoHead(allocate)', 'parent', 'allocate'),
    'wrapper-allocate': ('ClosureConversion.cj',
        '        parentBlock.InsertExprIntoHead(allocate)', 'parentBlock', 'allocate'),
    'constructor-store': ('MarkClassHasInited.cj',
        '        entry.InsertExprIntoHead(storeRef)', 'entry', 'storeRef'),
    'constructor-false': ('MarkClassHasInited.cj',
        '        entry.InsertExprIntoHead(falseVal)', 'entry', 'falseVal'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    parser.add_argument('--cut', choices=SITES)
    parser.add_argument('--diff', type=Path, required=True)
    args = parser.parse_args()
    patches = []
    files = sorted({value[0] for value in SITES.values()})
    for filename in files:
        relative = Path('packages/chir/src') / filename
        path = args.tree / relative
        original = path.read_text()
        modified = original
        for site, (file, needle, block, expr) in SITES.items():
            if file != filename:
                continue
            if modified.count(needle) != 1:
                raise SystemExit(f'expected exactly one consumer: {site}')
            indent = needle[:len(needle) - len(needle.lstrip())]
            var = 'headMember_' + site.replace('-', '_')
            check = [f'var {var} = false',
                     f'for (member in {block}.GetExpressions()) {{',
                     f'    if (member.nodeId == {expr}.nodeId) {{ {var} = true }}',
                     '}',
                     f'println("HEAD_INSERT {site} member=${{{var}}}")',
                     f'if ({var}) {{ throw IllegalStateException("HEAD_INSERT {site}: already a block member") }}']
            if args.cut == site and site != 'const-literal':
                check.insert(0, f'{block}.AppendExpression({expr})')
            replacement = '\n'.join(indent + line for line in check) + '\n' + needle
            modified = modified.replace(needle, replacement)
        if filename == 'ConstEval.cj' and args.cut == 'const-literal':
            needle = '                    let constant = builder.CreateConstant(ty, IntLiteral(val.GetInt()), parent)'
            if modified.count(needle) != 1:
                raise SystemExit('expected one integer constant producer')
            modified = modified.replace(needle, needle + '\n                    parent.AppendExpression(constant)')
        path.write_text(modified)
        patches.extend(difflib.unified_diff(original.splitlines(True), modified.splitlines(True),
                                           fromfile='a/' + str(relative), tofile='b/' + str(relative)))
    args.diff.write_text(''.join(patches))
    print(hashlib.sha256(args.diff.read_bytes()).hexdigest(), args.diff)


if __name__ == '__main__':
    main()
