#!/usr/bin/env python3
"""Assert constructor invariants from the real compiler's desugared AST.

The dump is an input, never a reconstructed AST or a copy of compiler logic.
Every assertion prints its observed value, including successful assertions.
"""
import argparse
import json
import re
from pathlib import Path


def nodes(text, label):
    pattern = re.compile(r'^( *)(%s[^\n]*?) \{\n' % label, re.M)
    result = []
    for match in pattern.finditer(text):
        end = text.find('\n' + match[1] + '}', match.end())
        if end >= 0:
            result.append((match[2], text[match.start():end + len(match[1]) + 2], len(match[1])))
    return result


def own_field(node, key):
    return re.search(r'^' + ' ' * (node[2] + 2) + re.escape(key) + r': (.*)$', node[1], re.M)


def params(fn):
    lists = nodes(fn[1], 'FuncParamList')
    return nodes(lists[0][1], 'FuncParam: ') if lists else []


def names(ps):
    return [p[0].removeprefix('FuncParam: ') for p in ps]


def functions(cls):
    fs = nodes(cls[1], 'FuncDecl: ')
    depth = min((f[2] for f in fs), default=-1)
    return [f for f in fs if f[2] == depth]


def args(call):
    return [a for a in nodes(call[1], 'FuncArg') if a[2] == call[2] + 4]


def ptr(node):
    field = own_field(node, 'ptr')
    return field[1] if field else None


def calls_to(fn, target):
    result = []
    for call in nodes(fn[1], 'CallExpr'):
        field = own_field(call, 'resolvedFunction ptr')
        if field and field[1] == target:
            result.append(call)
    return result


def marker_argument(call):
    actuals = args(call)
    return len(actuals) >= 2 and 'RefExpr: __NATIVE_OBJC_ID_MARKER {' in actuals[1][1]


def run(work, test_filter):
    results = []

    def check(name, ok, observed):
        if not re.search(test_filter, name):
            return
        results.append(dict(name=name, passed=bool(ok), observed=observed))
        print(('PASS ' if ok else 'FAIL ') + name + ' observed=' + json.dumps(observed))

    def ast(fixture, phase='desugar'):
        files = list((work / fixture / 'result_AST').glob('*_' + phase + '_ast.txt'))
        return files[0].read_text() if len(files) == 1 else ''

    def rc(fixture):
        p = work / fixture / 'compiler.rc'
        return int(p.read_text()) if p.exists() else None

    def classes(text):
        return {c[0].removeprefix('ClassDecl: '): c for c in nodes(text, 'ClassDecl: ')}

    cp_log = (work / 'cpointer' / 'compiler.log').read_text()
    cp_sema = ast('cpointer', 'sema')
    cp_class = classes(cp_sema).get('PointerMirror')
    cp_attrs = own_field(cp_class, 'attributes')[1] if cp_class else 'missing'
    check('CPointer.compatible', bool(cp_class) and 'IS_BROKEN' not in cp_attrs and
          'must be Objective-C compatible' not in cp_log,
          dict(rc=rc('cpointer'), attributes=cp_attrs,
               diagnostics=[s for s in cp_log.splitlines() if 'error:' in s]))
    neg = (work / 'negative' / 'compiler.log').read_text()
    check('NonCompatible.rejected', rc('negative') == 1 and
          'param type of Objective-C mirror constructor must be Objective-C compatible' in neg,
          dict(rc=rc('negative'), target_diagnostic='must be Objective-C compatible' in neg))
    check('Integer.control', rc('control') == 0 and bool(ast('control')),
          dict(rc=rc('control'), desugar=bool(ast('control'))))

    mirror_classes = classes(ast('mirror'))
    generated = {}
    for cname in ('PointerMirror', 'PointerChild'):
        cls = mirror_classes.get(cname)
        fs = functions(cls) if cls else []
        internal = [f for f in fs if names(params(f))[:1] == ['$obj']]
        observed = [names(params(f)) for f in internal]
        check(cname + '.base_formals', len(internal) == 1 and observed[0] == ['$obj', '$mrk'] and
              own_field(params(internal[0])[1], 'ty')[1] == 'Struct-NativeObjCIdMarker', observed)
        if internal:
            generated[cname] = internal[0]
        user = [f for f in fs if f[0].startswith('FuncDecl: init ') and names(params(f)) == ['pointer']]
        target_calls = calls_to(user[0], ptr(internal[0])) if len(user) == 1 and internal else []
        check(cname + '.this_actuals', len(target_calls) == 1 and marker_argument(target_calls[0]),
              [dict(arity=len(args(c)), marker=marker_argument(c)) for c in target_calls])
    base = generated.get('PointerMirror')
    child = generated.get('PointerChild')
    super_calls = calls_to(child, ptr(base)) if child and base else []
    check('Mirror.super_actuals', len(super_calls) == 1 and marker_argument(super_calls[0]),
          [dict(arity=len(args(c)), marker=marker_argument(c)) for c in super_calls])
    mirror_cls = mirror_classes.get('PointerMirror')
    wrap = [f for f in functions(mirror_cls) if f[0].startswith('FuncDecl: mirrorResult ')] if mirror_cls else []
    wrap_calls = calls_to(wrap[0], ptr(base)) if len(wrap) == 1 and base else []
    check('Mirror.wrap_actuals', len(wrap_calls) == 1 and marker_argument(wrap_calls[0]),
          [dict(arity=len(args(c)), marker=marker_argument(c)) for c in wrap_calls])

    impl_text = ast('impl')
    impl_classes = classes(impl_text)
    impl_targets = {}
    for cname in ('PointerImpl', 'PointerImplChild'):
        cls = impl_classes.get(cname)
        fs = functions(cls) if cls else []
        internal = [f for f in fs if names(params(f))[:1] == ['$obj']]
        expected = [['$obj', '$mrk', 'pointer'], ['$obj', '$mrk']] if cname == 'PointerImpl' else [['$obj', '$mrk', 'pointer']]
        actual = [names(params(f)) for f in internal]
        marker_types = [own_field(params(f)[1], 'ty')[1] if len(params(f)) > 1 else 'missing' for f in internal]
        check(cname + '.impl_formals', sorted(actual) == sorted(expected) and
              all(t == 'Struct-NativeObjCIdMarker' for t in marker_types),
              dict(params=actual, marker_types=marker_types))
        for fn in internal:
            impl_targets[ptr(fn)] = fn
    impl_calls = []
    for cls in impl_classes.values():
        for fn in functions(cls):
            for target in impl_targets:
                impl_calls.extend(calls_to(fn, target))
    check('Impl.this_super_actuals', bool(impl_calls) and all(marker_argument(c) for c in impl_calls),
          [dict(arity=len(args(c)), marker=marker_argument(c)) for c in impl_calls])
    wrappers = [f for f in nodes(impl_text, 'FuncDecl: CJImpl_ObjC_') if '_init_' in f[0]]
    check('Impl.wrapper_formals', len(wrappers) == len(impl_targets) and bool(wrappers) and
          all('$mrk' not in names(params(f)) for f in wrappers), [names(params(f)) for f in wrappers])
    wrapper_calls = [c for f in wrappers for t in impl_targets for c in calls_to(f, t)]
    check('Impl.wrapper_actuals', len(wrapper_calls) == len(wrappers) and bool(wrappers) and
          all(marker_argument(c) for c in wrapper_calls),
          [dict(arity=len(args(c)), marker=marker_argument(c)) for c in wrapper_calls])

    string_cls = classes(ast('strings')).get('StringMirror')
    string_fs = functions(string_cls) if string_cls else []
    string_base = [f for f in string_fs if names(params(f)) == ['$obj', '$mrk']]
    string_ctor = [f for f in string_fs if names(params(f)) == ['str']]
    string_calls = calls_to(string_ctor[0], ptr(string_base[0])) if len(string_ctor) == len(string_base) == 1 else []
    check('NSString.this_actuals', len(string_calls) == 1 and marker_argument(string_calls[0]),
          dict(rc=rc('strings'), calls=[dict(arity=len(args(c)), marker=marker_argument(c)) for c in string_calls]))
    (work / 'assertions.json').write_text(json.dumps(results, indent=2) + '\n')
    if not results:
        raise ValueError('filter did not select any assertions')
    failed = [r['name'] for r in results if not r['passed']]
    print('RESULT total=' + str(len(results)) + ' failed=' + json.dumps(failed))
    return int(bool(failed))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('work', type=Path)
    parser.add_argument('--filter', default='.*', help='regular expression selecting test names')
    opts = parser.parse_args()
    raise SystemExit(run(opts.work, opts.filter))
