#!/usr/bin/env python3
"""Check unoptimized output of the real compiler, never a model of attribute lowering."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
out = args.output
ast = (out / 'fixture_AST/8_mangle_ast.txt').read_text()
chir = (out / 'fixture_CHIR/0_AST_CHIR.chirtxt').read_text()
modules = [(p, p.read_text()) for p in sorted(out.glob('*-nothrow_fixture.ll'))]
results = []

def check(name, passed, observed):
    result = dict(name=name, passed=bool(passed), observed=observed)
    results.append(result)
    print('EXECUTED', name, 'PASS' if passed else 'FAIL', observed, flush=True)

def ast_attrs(symbol):
    for block in ast.split('FuncDecl: '):
        if f'mangledName: "{symbol}"' in block:
            match = re.search(r'attributes: \[([^\]]*)\]', block)
            if match:
                return match[1].split(', ')
    return []

def ir_function(symbol):
    for path, text in modules:
        match = re.search(r'^(?:define|declare) [^\n]*@"?' + re.escape(symbol) + r'"?\([^\n]*', text, re.M)
        if match:
            header = match.group()
            attr_id = re.search(r'#(\d+)', header)
            attrs = ''
            if attr_id:
                group = re.search(r'^attributes #' + attr_id[1] + r' = \{ (.*) \}', text, re.M)
                attrs = group[1] if group else ''
            end = text.index('\n}', match.end()) if header.startswith('define ') else match.end()
            return header, attrs.split(), text[match.start():end], str(path)
    return '', [], '', ''

# Presence has its own non-fatal assertion: all target assertions below still execute.
headers = [line for line in chir.splitlines() if ' Func @' in line and '5~initHv(' in line]
foreign = [line for line in headers if 'ForeignObject5~initHv' in line or ('ForeignProtocol' in line) or 'DerivedForeign5~initHv' in line]
ordinary = [line for line in headers if 'OrdinaryObject5~initHv' in line]
check('generatedFinalizersPresent', len(foreign) == 3, headers)
check('ordinaryFinalizerPresent', len(ordinary) == 1, ordinary)
for label, token in [('mirror', 'ForeignObject5~initHv'), ('protocolWrapper', 'ForeignProtocol'), ('derivedMirror', 'DerivedForeign5~initHv')]:
    line = next((h for h in foreign if token in h), '')
    symbol = line.split('Func @')[-1].split('(')[0] if line else '__missing__'
    attrs = ast_attrs(symbol)
    print('OBSERVED', label + '.astAttributes', attrs, flush=True)
    print('OBSERVED', label + '.chirHeader', line, flush=True)
    check(label + '.chirIndependent', bool(line) and '[noSideEffect]' not in line, line)
    header, attrs, body, path = ir_function(symbol)
    check(label + '.llvmNoUnwind', bool(header) and 'nounwind' in attrs, dict(header=header, attrs=attrs, file=path))
    check(label + '.llvmNoExtraPromises', bool(header) and not {'readonly', 'readnone', 'willreturn'}.intersection(attrs), attrs)
    check(label + '.releaseCallControl', 'objCRelease' in body, body)
line = ordinary[0] if ordinary else ''
symbol = line.split('Func @')[-1].split('(')[0] if line else '__missing__'
check('ordinary.astUnmarkedControl', bool(line) and 'DOES_NOT_THROW' not in ast_attrs(symbol), ast_attrs(symbol))
check('ordinary.chirUnmarkedControl', bool(line) and '[doesNotThrow]' not in line, line)
header, attrs, _, path = ir_function(symbol)
check('ordinary.llvmUnmarkedControl', bool(header) and 'nounwind' not in attrs, dict(header=header, attrs=attrs, file=path))
# A real, called whitelist function proves the old stronger attribute path still runs.
control = '_CNatXl8hashCodeHv'
header, attrs, _, path = ir_function(control)
check('noSideEffect.llvmPromisesControl', bool(header) and {'nounwind', 'readonly', 'willreturn'}.issubset(attrs), dict(header=header, attrs=attrs, file=path))
check('noSideEffect.chirControl', any('[noSideEffect]' in line and 'Func @'+control+'(' in line for line in chir.splitlines()), control)
check('noSideEffect.actualCallControl', any(re.search(r'call i64 @'+control+r'\(', text) for _, text in modules), control)
(out / 'checks.json').write_text(json.dumps(results, indent=2) + '\n')
passed = sum(r['passed'] for r in results)
print(f'RESULT pass={passed} fail={len(results)-passed} total={len(results)}')
raise SystemExit(0 if passed == len(results) else 1)
