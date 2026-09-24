#!/usr/bin/env python3
"""Check enum constructor metadata emitted by a real stage1 compiler.

Run under the compiler's SDK/loader environment. Each assertion consumes dumped
product IR; no compiler component or layout model is rebuilt by this test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def split_fields(text):
    fields, start, depth, quoted = [], 0, 0, False
    for i, char in enumerate(text):
        if char == '"':
            quoted = not quoted
        if quoted:
            continue
        if char in '([{<':
            depth += 1
        elif char in ')]}>':
            depth -= 1
        elif char == ',' and depth == 0:
            fields.append(text[start:i].strip())
            start = i + 1
    fields.append(text[start:].strip())
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixture = Path(__file__).resolve().parent / 'enum_zero_offsets_fixtures/layouts.cj'
    command = [str(compiler), str(fixture), '-O0', '--dump-ir', '--dump-to-screen',
               '--output-type=staticlib', '-o', str(out / 'layouts.a')]
    (out / 'compiler.sha256').write_text(hashlib.sha256(compiler.read_bytes()).hexdigest() + '\n')
    (out / 'fixture.sha256').write_text(hashlib.sha256(fixture.read_bytes()).hexdigest() + '\n')
    (out / 'compile.command.json').write_text(json.dumps(command) + '\n')
    result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=180)
    (out / 'compile.log').write_text(result.stdout)
    (out / 'compile.rc').write_text(str(result.returncode) + '\n')
    # Compilation failure is infrastructure/fixture failure, never a red invariant.
    if result.returncode:
        print(f'COMPILE_FAILED rc={result.returncode}; target assertions not executed')
        return 2
    ir = result.stdout

    def definition(name):
        rows = set(re.findall(r'^@"' + re.escape(name) + r'" = (?!external)[^\n]+', ir, re.M))
        assert len(rows) == 1, f'expected one definition of {name}, got {len(rows)}'
        return rows.pop()

    def metadata(name, kind='TypeInfo'):
        line = definition('enumzero:' + name)
        body = line.split('%' + kind + ' { ', 1)[1].split(' },', 1)[0]
        return split_fields(body)

    results = {}

    def check(name, action):
        # Printed before the predicate, so a failing target remains observable.
        print('EXECUTED ' + name)
        try:
            action()
            results[name] = 'PASS'
        except (AssertionError, IndexError, ValueError) as error:
            results[name] = 'FAIL'
            print(f'FAIL {name}: {error}')
        else:
            print('PASS ' + name)

    def fields(name, count):
        ti = metadata(name + ':0.ti')
        assert ti[3] == f'i16 {count}', f'field count: {ti[3]}'
        assert ti[4] == 'i32 0' and ti[7] == 'i8 1', f'zero layout: {ti[4]}, {ti[7]}'
        field_name = 'enumzero:' + name + ':0.ti.fields'
        assert '@"' + field_name + '"' in ti[13], f'field types not consumed: {ti[13]}'
        field_array = definition(field_name)
        assert f'[{count} x %TypeInfo*]' in field_array, field_array
        assert field_array.count('%TypeInfo* @"enumzero:Empty.ti"') == count, field_array

    def offsets(name, count, expected):
        ti = metadata(name + ':0.ti')
        offset_name = 'enumzero:' + name + ':0.ti.offsets'
        assert '@"' + offset_name + '"' in ti[10], f'offsets not consumed: {ti[10]}'
        array = definition(offset_name)
        assert f'constant [{count} x i32]' in array, array
        values = [int(x) for x in re.findall(r'i32 (-?\d+)', array)]
        if 'zeroinitializer' in array:
            values = [0] * count
        assert values == expected, f'offset array: {values}, expected {expected}'

    def no_args():
        ti = metadata('NoArgs:0.ti')
        assert (ti[3], ti[4], ti[7], ti[10], ti[13]) == ('i16 0', 'i32 0', 'i8 1', 'i32* null', 'i8* null'), ti

    def nonzero():
        assert metadata('Nonzero:0.ti')[3] == 'i16 2'
        offsets('Nonzero', 2, [0, 4])

    def generic():
        tt = metadata('Generic:0.tt', 'TypeTemplate')
        assert tt[3:5] == ['i16 2', 'i16 1'], tt
        assert '@"enumzero:Generic:0.tt.fieldTiFns"' in tt[5], tt[5]

    for name, count in [('OneEmpty', 1), ('TwoEmpty', 2)]:
        check(name + 'FieldTypes', lambda n=name, c=count: fields(n, c))
        check(name + 'OffsetsConsumed', lambda n=name, c=count: offsets(n, c, [0] * c))
    check('NoArgsNullOffsets', no_args)
    check('NonzeroOffsetsControl', nonzero)
    check('GenericTemplateControl', generic)
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'SUMMARY total={len(results)} pass={list(results.values()).count("PASS")} fail={list(results.values()).count("FAIL")}')
    return int('FAIL' in results.values())


if __name__ == '__main__':
    raise SystemExit(main())
