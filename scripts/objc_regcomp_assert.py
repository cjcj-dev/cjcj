#!/usr/bin/env python3
"""Assert reg companion results from the real stage1 desugared AST."""
import argparse
import json
import re
from pathlib import Path
from objc_cpointer_assert import nodes, own_field, functions, params, names, ptr, calls_to, args


def run(work, pattern):
    results = []
    def check(name, ok, observed):
        if re.search(pattern, name):
            results.append(dict(name=name, passed=bool(ok), observed=observed))
            print(('PASS ' if ok else 'FAIL ') + name + ' observed=' + json.dumps(observed), flush=True)
    def read(fixture):
        files = list((work / fixture / 'result_AST').glob('*_desugar_ast.txt'))
        text = files[0].read_text() if len(files) == 1 else ''
        return text, {c[0].removeprefix('ClassDecl: '): c for c in nodes(text, 'ClassDecl: ')}
    def fns(cls): return functions(cls) if cls else []
    def fields(cls):
        return [f for f in nodes(cls[1], 'VarDecl: ') if f[2] == cls[2] + 4] if cls else []
    def attrs(node):
        a = own_field(node, 'attributes') if node else None
        return a[1] if a else ''
    text, classes = read('constructors')
    for cname in ('PointerImpl', 'PointerImplChild'):
        fs = fns(classes.get(cname))
        base = [f for f in fs if names(params(f)) == ['$obj', '$registryId', '$mrk']]
        data = [f for f in fs if names(params(f))[:1] == ['$regData']]
        check(cname + '.base_signature', len(base) == 1,
              [names(params(f)) for f in fs if f[0].startswith('FuncDecl: init')])
        check(cname + '.regdata_signature', len(data) == (2 if cname == 'PointerImpl' else 1),
              [names(params(f)) for f in data])
        check(cname + '.registry_consumer', len(base) == 1 and 'RefExpr: getFromRegistryById {' in base[0][1],
              dict(base_count=len(base), lookup=bool(base and 'RefExpr: getFromRegistryById {' in base[0][1])))
        companion = classes.get(cname + '$reg')
        cfs = fns(companion)
        cb = [f for f in cfs if names(params(f)) == ['$obj']]
        check(cname + '.companion_base', len(cb) == 1, [names(params(f)) for f in cfs])
        if cname == 'PointerImpl':
            check('Registry.root_registration', len(cb) == 1 and 'RefExpr: setRegistryId {' in cb[0][1] and
                  'RefExpr: putToRegistry {' in cb[0][1], dict(set=bool(cb and 'RefExpr: setRegistryId {' in cb[0][1]),
                  put=bool(cb and 'RefExpr: putToRegistry {' in cb[0][1])))
    text, classes = read('members')
    impl, companion = classes.get('RegistryImpl'), classes.get('RegistryImpl$reg')
    moved = [f[0] for f in fields(companion)]
    remaining = [f[0] for f in fields(impl)]
    check('Members.fields_moved', 'VarDecl: value' in moved and 'VarDecl: shared' in moved and
          'VarDecl: value' not in remaining and 'VarDecl: shared' not in remaining,
          dict(companion=moved, impl=remaining))
    moved_methods = [f[0] for f in fns(companion)]
    proxy_methods = [f[0] for f in fns(impl) if 'OBJ_C_IMPL_MOVED_MEMBER_PROXY' in attrs(f)]
    check('Members.static_proxy', any(n.startswith('FuncDecl: readShared ') for n in moved_methods) and
          any(n.startswith('FuncDecl: readShared ') for n in proxy_methods),
          dict(moved=moved_methods, proxies=proxy_methods))
    props = nodes(impl[1], 'PropDecl: ') if impl else []
    proxy_props = [p[0] for p in props if 'OBJ_C_IMPL_MOVED_MEMBER_PROXY' in attrs(p)]
    check('Members.field_proxies', 'PropDecl: value' in proxy_props and 'PropDecl: shared' in proxy_props, proxy_props)
    check('Members.finalizer_moved', any('FINALIZER' in attrs(f) for f in fns(companion)), moved_methods)
    check('Control.ordinary_field', 'VarDecl: value' in [f[0] for f in fields(classes.get('Ordinary'))] and
          'Ordinary$reg' not in classes, [f[0] for f in fields(classes.get('Ordinary'))])
    _, broken = read('broken')
    for name in ('BrokenMirror', 'BrokenImpl', 'BrokenChild'):
        check(name + '.broken_propagated', 'IS_BROKEN' in attrs(broken.get(name)), attrs(broken.get(name)))
    check('Broken.healthy_control', bool(broken.get('HealthyImpl')) and 'IS_BROKEN' not in attrs(broken.get('HealthyImpl')),
          attrs(broken.get('HealthyImpl')))
    check('Control.compiler_completed', (work / 'control' / 'compiler.rc').read_text().strip() == '0',
          (work / 'control' / 'compiler.rc').read_text().strip())
    (work / 'assertions.json').write_text(json.dumps(results, indent=2) + '\n')
    if not results: raise ValueError('no selected assertions')
    failed = [r['name'] for r in results if not r['passed']]
    print('RESULT total=' + str(len(results)) + ' failed=' + json.dumps(failed))
    return int(bool(failed))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('work', type=Path)
    p.add_argument('--filter', default='.*')
    a = p.parse_args()
    raise SystemExit(run(a.work, a.filter))
