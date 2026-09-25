#!/usr/bin/env python3
"""Assert mirror-ctor nil handling from the real compiler desugar AST dump."""
import argparse
import json
import re
import sys
from pathlib import Path

from objc_cpointer_assert import nodes, own_field, functions, params, names


MESSAGE = 'Initialization error: expected NilMirror, got nil.'


def ast_text(work):
    files = list((work / 'mirror' / 'result_AST').glob('*_desugar_ast.txt'))
    return files[0].read_text() if len(files) == 1 else ''


def compiler_rc(work):
    path = work / 'mirror' / 'compiler.rc'
    return path.read_text().strip() if path.exists() else 'missing'


def user_init(text):
    for cls in nodes(text, 'ClassDecl: PointerMirror'):
        for fn in functions(cls):
            if not fn[0].startswith('FuncDecl: init '):
                continue
            if names(params(fn)) == ['pointer']:
                return fn
    return None


def this_calls(fn):
    found = []
    for call in nodes(fn[1], 'CallExpr'):
        if 'RefExpr: this {' in call[1].split('arguments [', 1)[0]:
            found.append(call)
    return found


def lambda_of(call):
    lams = nodes(call[1], 'LambdaExpr')
    return lams[0] if lams else None


def temp_binding(lam):
    for var in nodes(lam[1], r'VarDecl: let \$tmp'):
        if 'CallExpr' not in var[1]:
            continue
        match = re.search(r'VarDecl: let (\$tmp\d+)', var[0])
        if match:
            return match[1], var
    return None, None


def returned_temp(lam, name):
    for ret in nodes(lam[1], 'ReturnExpr'):
        if 'RefExpr: %s {' % name in ret[1]:
            return True
    return False


def nil_throw(lam):
    hits = []
    for throw in nodes(lam[1], 'ThrowExpr'):
        literals = re.findall(r'LitConstExpr: String "([^"]*)"', throw[1])
        has_message = MESSAGE in literals
        has_type = 'ty: Class-ObjCInitException' in throw[1]
        if has_message or has_type or literals:
            hits.append(dict(message=has_message, type=has_type, literals=literals))
    return hits


def marker_kept(call):
    return 'RefExpr: __NATIVE_OBJC_ID_MARKER {' in call[1]


def run(work, pattern):
    text = ast_text(work)
    rc = compiler_rc(work)
    fn = user_init(text) if text else None
    calls = this_calls(fn) if fn else []
    call = calls[0] if calls else None
    lam = lambda_of(call) if call else None
    name, var = temp_binding(lam) if lam else (None, None)
    throws = nil_throw(lam) if lam else []
    results = []

    def check(name_, ok, observed):
        if not re.search(pattern, name_):
            return
        results.append(dict(name=name_, passed=bool(ok), observed=observed))
        print(('PASS ' if ok else 'FAIL ') + name_ + ' observed=' + json.dumps(observed), flush=True)

    check('NilMirror.nil_throws',
          rc == '0' and bool(throws) and all(hit['message'] and hit['type'] for hit in throws),
          dict(compiler_rc=rc, ast=bool(text), throws=throws))
    check('NilMirror.temp_passed_to_this',
          rc == '0' and call is not None and lam is not None and name is not None and
          returned_temp(lam, name) and marker_kept(call) and 'objCAlloc' in var[1],
          dict(compiler_rc=rc, this_calls=len(calls), temp=name,
               returned=bool(name and lam and returned_temp(lam, name)),
               marker=bool(call and marker_kept(call)),
               alloc=bool(var and 'objCAlloc' in var[1])))
    Path(work / 'assert.json').write_text(json.dumps(results, indent=2) + '\n')
    failed = [row['name'] for row in results if not row['passed']]
    return 1 if failed or not results else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('work')
    parser.add_argument('--filter', default='.*')
    args = parser.parse_args()
    sys.exit(run(Path(args.work), args.filter))


if __name__ == '__main__':
    main()
