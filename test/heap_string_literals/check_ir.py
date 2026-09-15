#!/usr/bin/env python3
"""Check real compiler IR and the matching backend assembly, including root slots."""
import argparse
import pathlib
import re

p = argparse.ArgumentParser()
p.add_argument('ir', type=pathlib.Path)
p.add_argument('assembly', type=pathlib.Path)
a = p.parse_args()
irs = sorted(a.ir.glob('*.ll'))
assemblies = sorted(a.assembly.glob('*.s'))
assert irs and assemblies, 'expected retained compiler IR and backend assembly'
failures = 0
checks = 0

def check(name, condition):
    global failures, checks
    checks += 1
    failures += not condition
    print(f'ASSERT {name}={"PASS" if condition else "FAIL"}')

all_ir = '\n'.join(x.read_text() for x in irs)
all_asm = '\n'.join(x.read_text() for x in assemblies)
roots = []
for asm in assemblies:
    active = False
    for line in asm.read_text().splitlines():
        if '.section' in line:
            active = '.cjmetadata.gcroots' in line
        elif active and '.quad' in line:
            roots.append(line)
cache_count = 0
for ir in irs:
    text = ir.read_text()
    for line in text.splitlines():
        if not line.startswith('@') or ' = ' not in line:
            continue
        name, definition = line.split(' = ', 1)
        if 'record.std.core:String' not in definition or 'external global' in definition:
            continue
        cache_count += 1
        symbol = name[1:].strip('"')
        check(f'{ir.name}.{symbol}.mutable', ' global ' in ' '+definition and 'zeroinitializer' in definition)
        check(f'{ir.name}.{symbol}.heap_source', any(
            '@llvm.cj.gcwrite.static.ref(' in x and name in x and '%rawarray' in x
            for x in text.splitlines()))
        check(f'{ir.name}.{symbol}.root', any(symbol in x for x in roots))
    for line in text.splitlines():
        if line.startswith('@"$const_cjstring_data.'):
            check(f'{ir.name}.native_bytes', re.search(r'private constant \[\d+ x i8\]', line) is not None)
            check(f'{ir.name}.native_not_root', line.split(' = ')[0][2:-1] not in '\n'.join(roots))
    if re.search(r'(?:call|invoke)[^\n]*@llvm.cj.malloc.array\([^\n]*, i64 [1-9][0-9]*, i64 1\)', text):
        check(f'{ir.name}.payload_copy', '@llvm.memcpy.p1i8.p0i8.i64(' in text)
check('cache_input_present', cache_count > 0)
check('native_typeinfo_control', '%TypeInfo* @"RawArray<UInt8>.ti"' in all_ir)
check('runtime_allocator', 'CJ_MCC_NewArray8' in all_asm)
check('runtime_static_store', 'CJ_MCC_WriteStaticRef' in all_asm)
helpers = set(re.findall(r'define[^\n]* @([^ (]*\.cjstring\.materialize\.\d+)\(', all_ir))
calls = set(re.findall(r'call void @([^ (]*\.cjstring\.materialize\.\d+)\(', all_ir))
check('all_split_modules_called', bool(helpers) and helpers == calls)
print(f'IR_RESULT checks={checks} failures={failures} caches={cache_count} modules={len(helpers)}')
raise SystemExit(bool(failures))
