#!/usr/bin/env python3
"""Generate ABI probes from the actual product declarations, without a model copy.

Run both generated programs on the same 64-bit target. compare.py checks the
candidate compiler's observed byte placement against C++ offsetof/sizeof.
This proves layout only; macro execution is a separate integration test.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--runtime-header', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
a = parser.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
source = a.repo / 'packages/macro/src/InvokeUtil.cj'
text = source.read_text()
names = {'RuntimeHeapParamC': 'HeapParam', 'RuntimeGCParamC': 'GCParam',
         'RuntimeLogParamC': 'LogParam', 'RuntimeConcurrencyParamC': 'ConcurrencyParam',
         'RuntimeConfigParamC': 'RuntimeParam'}
blocks, fields = {}, {}
for name in names:
    start = text.index('@C\nstruct ' + name + ' {')
    end = text.index('\n}\n', start) + 3
    blocks[name] = text[start:end]
    fields[name] = re.findall(r'^    let (\w+): (\w+)$', blocks[name], re.M)

zero = {'UIntNative': '0', 'Float64': '0.0', 'UInt64': '0', 'UInt32': '0', 'Int32': '0', 'Bool': 'false'}
marker = {'UIntNative': '6510615555426900570', 'Float64': '1.0',
          'UInt64': '6510615555426900570', 'UInt32': '1515870810', 'Int32': '1515870810', 'Bool': 'true'}
patterns = {'UIntNative': [90]*8, 'Float64': [0,0,0,0,0,0,240,63],
            'UInt64': [90]*8, 'UInt32': [90]*4, 'Int32': [90]*4, 'Bool': [1]}

def construct(name, active=None):
    args = []
    for field, ty in fields[name]:
        if ty in names:
            args.append(construct(ty, fields[ty][0][0] if field == active else None))
        else:
            args.append(marker[ty] if field == active else zero[ty])
    return name + '(' + ', '.join(args) + ')'

cj = ['import std.core.*',
      'foreign { func calloc(count: UIntNative, size: UIntNative): CPointer<Unit> }',
      *blocks.values(), 'main(): Int64 {']
cpp = ['#include <cstddef>', '#include <cstdio>', '#include <type_traits>',
       '#include "' + str(a.runtime_header.resolve()) + '"',
       'static_assert(sizeof(void*) == 8);', 'static_assert(sizeof(bool) == 1);', 'int main() {']
manifest = {}
for name, cname in names.items():
    cj += [f'    println("SIZE {cname} ${{sizeOf<{name}>()}} ${{alignOf<{name}>()}}")']
    cpp += [f'    static_assert(std::is_standard_layout_v<{cname}>);',
            f'    std::printf("SIZE {cname} %zu %zu\\n", sizeof({cname}), alignof({cname}));']
    for field, ty in fields[name]:
        key = cname + '.' + field
        cj += ['    unsafe {', f'        let p = CPointer<{name}>(calloc(1, sizeOf<{name}>()))',
               '        let bytes = CPointer<UInt8>(p)',
               f'        unsafe {{ p.write({construct(name, field)}) }}',
               f'        println("FIELD_SIZE {key} ${{sizeOf<{ty}>()}}")',
               f'        print("BYTES {key} ")',
               f'        for (i in 0..sizeOf<{name}>()) {{ print("${{unsafe {{ bytes.read(Int64(i)) }} }},") }}',
               '        println("")', '        unsafe { LibC.free(p) }', '    }']
        scalar = fields[ty][0][1] if ty in names else ty
        manifest[key] = {'pattern': patterns[scalar], 'type': ty}
# Enumerate the consumer independently: an omitted producer field must still
# appear in the expected table, and a stale producer field must not break C++.
header = a.runtime_header.read_text()
for cname in names.values():
    body = re.search(r'struct ' + cname + r' \{(.*?)\n\};', header, re.S).group(1)
    body = re.sub(r'/\*.*?\*/|//[^\n]*', '', body, flags=re.S)
    for field in re.findall(r'\b(\w+)\s*;', body):
        key = cname + '.' + field
        cpp += [f'    std::printf("FIELD {key} %zu %zu\\n", offsetof({cname}, {field}), sizeof((({cname}*)0)->{field}));']
cpp += ['}']
cj += ['    return 0', '}']
(a.out/'layout.cj').write_text('\n'.join(cj)+'\n')
(a.out/'layout.cpp').write_text('\n'.join(cpp)+'\n')
(a.out/'manifest.json').write_text(json.dumps({'fields': manifest, 'source': str(source),
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'header_sha256': hashlib.sha256(a.runtime_header.read_bytes()).hexdigest()}, indent=2)+'\n')
