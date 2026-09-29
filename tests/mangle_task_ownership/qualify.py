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
    parser.add_argument('--race', action='store_true',
                        help='enable only after observation-only input qualification')
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
    qualification = Path(__file__).with_name('Qualification.cj').read_text()
    if args.race:
        qualification = qualification.replace('import std.collection.*',
            'import std.collection.*\nimport cjcj::mangle.MangleOwnershipRace')
        # Configure only after inspecting the actual typed AST and task indices.
        observation = '            println("MANGLE_QUALIFICATION shared=${same} separate=${separate} fullTasks=${fullTasks} remainder=${decls.size % 30}")'
        qualification = qualification.replace(observation, observation + '''
            if (!same || !separate || !fullTasks || decls.size % 30 == 0) {
                throw IllegalStateException("MANGLE_FIXTURE_INELIGIBLE")
            }
            MangleOwnershipRace.Configure(a, workers)''')
        modified = modified.replace('import cjcj::mangle.BaseMangler as RealBaseMangler',
            'import cjcj::mangle.MangleOwnershipRace\nimport cjcj::mangle.BaseMangler as RealBaseMangler')
        old_routes = [
            '                            desugarDecl.mangledName = baseMangler.Mangle(desugarDecl)',
            '                            desugarDecl.mangledName = baseMangler.Mangle(adapter.ConvertDecl(desugarDecl))',
        ]
        routes = [route for route in old_routes if route in modified]
        if len(routes) != 1:
            raise SystemExit('expected one recognized product macro route')
        route = routes[0]
        modified = modified.replace(route, '''                            MangleOwnershipRace.BeforeMacro(curDecl.identifier.Val())
                            try {
    ''' + route + '''
                                MangleOwnershipRace.MacroResult(curDecl.identifier.Val(), desugarDecl.mangledName)
                            } finally {
                                MangleOwnershipRace.Release(curDecl.identifier.Val())
                            }''')
        modified = modified.replace('        DoMangling(baseMangler, parallelNum, topDecls)',
            '        DoMangling(baseMangler, parallelNum, topDecls)\n        MangleOwnershipRace.Finish()')
        mangle = args.tree / 'packages/mangle/src'
        shutil.copyfile(Path(__file__).with_name('Race.cj'), mangle / 'MangleOwnershipRace.cj')
        for name, before, after in [
            ('ASTAdapter.cj', '        StoreTy(source, target)',
             '        StoreTy(source, target)\n        MangleOwnershipRace.AfterStore(this, source, target)'),
            ('BaseMangler.cj', '                if (let Some(ty) <- param.semaTy()) {',
             '                if (let Some(ty) <- param.semaTy()) {\n                    MangleOwnershipRace.Consume(ty)'),
        ]:
            target = mangle / name
            content = target.read_text()
            if content.count(before) != 1:
                raise SystemExit(f'expected one bearing point: {name}')
            target.write_text(content.replace(before, after))
    fixture.write_text(qualification)
    path.write_text(modified)
    args.diff.write_text(''.join(difflib.unified_diff(
        original.splitlines(True), modified.splitlines(True),
        fromfile='a/packages/frontend/src/CompilerInstance.cj',
        tofile='b/packages/frontend/src/CompilerInstance.cj')))


if __name__ == '__main__':
    main()
