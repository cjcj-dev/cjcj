#!/usr/bin/env python3
"""Add temporary result-membership assertions to a disposable stage1 source tree.

The shipped compiler has no added test hooks. --cut changes the product producer
or consumer, keeping the observation and assertion identical across all arms.
"""
import argparse
import difflib
from pathlib import Path


def membership(block, expr, expected, label, indent):
    lines = [
        'var memberCount: Int64 = 0',
        f'for (member in {block}.GetExpressions()) {{',
        f'    if (member.nodeId == {expr}.nodeId) {{ memberCount++ }}',
        '}',
        f'println("CONSTEVAL {label} members=${{memberCount}} expected={expected}")',
        f'if (memberCount != {expected}) {{',
        f'    throw IllegalStateException("CONSTEVAL {label}: block membership mismatch")',
        '}',
    ]
    return ('\n'.join(indent + line for line in lines) + '\n').replace(
        'memberCount', 'memberCount_' + label.replace('-', '_'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    parser.add_argument('--cut', choices=['producer', 'consumer', 'enum-selector'])
    parser.add_argument('--diff', type=Path, required=True)
    args = parser.parse_args()
    rel = 'packages/chir/src/ConstEval.cj'
    path = args.tree / rel
    original = path.read_text()
    text = original
    sites = [
        ('                    block.AppendExpression(constant)',
         membership('block', 'constant', 0, 'literal-created', '                    ')),
        ('                    if (!constant.IsConstantNull()) {',
         membership('block', 'constant', 1, 'literal-inserted', '                    ')),
        ('            insertExpr(constant)',
         membership('parent', 'constant', 0, 'created', '            ')),
        ('            return ExprResultAsValue(constant)',
         membership('parent', 'constant', 1, 'inserted', '            ')),
    ]
    # At cast creation neither expression has been consumed; both are then
    # inserted by the caller callback. These observe actual block membership.
    sites += [
        ('            let createdTypeCast340 = builder.CreateTypeCast(ty, selector, parent)',
         membership('parent', 'selectorExpr', 0, 'enum-before-cast', '            ')),
        ('            insertExpr(selectorExpr)',
         membership('parent', 'selectorExpr', 0, 'enum-selector-created', '            ') +
         membership('parent', 'createdTypeCast340', 0, 'enum-cast-created', '            ')),
        ('            insertExpr(createdTypeCast340)',
         membership('parent', 'selectorExpr', 1, 'enum-selector-inserted', '            ')),
        ('            return ExprResultAsValue(createdTypeCast340)',
         membership('parent', 'createdTypeCast340', 1, 'enum-cast-inserted', '            ')),
    ]
    for needle, assertion in sites:
        if text.count(needle) != 1:
            raise SystemExit(f'expected exactly one product site: {needle}')
        text = text.replace(needle, assertion + needle)
    if args.cut == 'consumer':
        text = text.replace('            insertExpr(constant)',
                            '            // Controlled cut: constant is not inserted.')
    if args.cut == 'enum-selector':
        text = text.replace('            insertExpr(selectorExpr)',
                            '            // Controlled cut: enum selector is not inserted.')
    if args.cut == 'producer':
        needle = '                    let constant = builder.CreateConstant(ty, IntLiteral(val.GetInt()), parent)'
        if text.count(needle) != 1:
            raise SystemExit('expected one integer producer')
        text = text.replace(needle, needle + '\n                    parent.AppendExpression(constant)')
    path.write_text(text)
    args.diff.write_text(''.join(difflib.unified_diff(
        original.splitlines(True), text.splitlines(True),
        fromfile='a/' + rel, tofile='b/' + rel)))


if __name__ == '__main__':
    main()
