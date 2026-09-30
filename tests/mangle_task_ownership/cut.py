#!/usr/bin/env python3
"""Cut either task-adapter production or its macro consumer in an isolated tree.

Apply before fixture installation so cut.diff describes product code alone.
The narrow macro cut modifies a candidate-changed line; it does not replace
the constructor cut on a baseline-existing real entry line.
"""
import argparse
import difflib
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('tree', type=Path)
    p.add_argument('--kind', choices=['adapter', 'macro'], required=True)
    p.add_argument('--diff', type=Path, required=True)
    args = p.parse_args()
    relative = 'packages/frontend/src/CompilerInstance.cj'
    path = args.tree / relative
    original = path.read_text()
    candidate_route = """                            let convertedDesugarDecl = adapter.ConvertDecl(desugarDecl)
                            let desugarMangledName = baseMangler.Mangle(convertedDesugarDecl)
                            desugarDecl.mangledName = desugarMangledName
                            convertedDesugarDecl.mangledName = desugarMangledName
"""
    if original.count(candidate_route) != 1:
        raise SystemExit('candidate task-owned macro route is required')
    if args.kind == 'adapter':
        before = '        let adapter = RealMangleAstAdapter()'
        after = '        let adapter = baseMangler.adapter'
    else:
        before = candidate_route
        after = '                            desugarDecl.mangledName = baseMangler.Mangle(desugarDecl)\n'
    if original.count(before) != 1:
        raise SystemExit('expected one real product bearing point')
    modified = original.replace(before, after)
    path.write_text(modified)
    args.diff.write_text(''.join(difflib.unified_diff(
        original.splitlines(True), modified.splitlines(True),
        fromfile='a/' + relative, tofile='b/' + relative)))


if __name__ == '__main__':
    main()
