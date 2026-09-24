#!/usr/bin/env python3
"""Trace actual std.core IR values into array-copy length and address operands."""
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
text = (out / 'core-compile.log').read_text(errors='replace')
bodies = dict(re.findall(r'^define[^\n]*?@([^\s(]+)\([^\n]*\).*?\{\n(.*?)^}', text, re.M | re.S))
ssa = r'%[-a-zA-Z$._0-9]+'
rows = []


def definitions(body):
    return dict(re.findall(r'^  (' + ssa + r') = (.*)$', body, re.M))


def depends(value, root, defs, seen=None):
    if value == root:
        return True
    seen = set() if seen is None else seen
    if value in seen:
        return False
    seen.add(value)
    return any(depends(v, root, defs, seen) for v in re.findall(ssa, defs.get(value, '')))


def dynamic_size(value, defs):
    ext = re.fullmatch(r'sext i32 (' + ssa + r') to i64(?:,.*)?', defs.get(value, ''))
    if not ext:
        return False
    phi = defs.get(ext[1], '')
    # Reference size is selected at the existing reference-kind branch;
    # the other incoming value must load field 4 from the element TypeInfo.
    incoming = re.findall(r'\[ ([^,]+), (' + ssa + r') \]', phi)
    if not phi.startswith('phi i32 ') or len(incoming) != 2:
        return False
    if not any(v == '8' for v, _ in incoming):
        return False
    for value, _ in incoming:
        load = re.match(r'load i32, i32\* (' + ssa + r')', defs.get(value, ''))
        if load and re.match(r'getelementptr inbounds %TypeInfo, %TypeInfo\* %ti\.arg\d*, i32 0, i32 4(?:,|$)', defs.get(load[1], '')):
            return True
    return False


# Include all real generic Array copy sites, with the four public overloads
# required explicitly so an accidentally empty or incomplete corpus fails.
selected = {n: b for n, b in bodies.items() if n.startswith('_CNat5ArrayIG_E') and '%arr.data.len' in b}
required = ['_CNat5ArrayIG_E5cloneHv', '_CNat5ArrayIG_E5cloneHRNat5RangeIlE',
            '_CNat5ArrayIG_E6copyToHRNatY1_IG_E', '_CNat5ArrayIG_E6copyToHRNatY1_IG_Elll']
details = []
for name, body in selected.items():
    defs = definitions(body)
    triples = re.findall(r'^  (%arr\.data\.len\d*) = mul i64 ([^,\n]+), ([^,\n]+).*\n'
                         r'  (%src\.index\d*) = mul i64 ([^,\n]+), ([^,\n]+).*\n'
                         r'  (%dst\.index\d*) = mul i64 ([^,\n]+), ([^,\n]+)', body, re.M)
    sites = []
    for length, count, size, src, src_count, src_size, dst, dst_count, dst_size in triples:
        calls = re.findall(r'call void @llvm\.cj\.array\.copy\.generic\.i64\(([^\n]+)\)', body)
        consumers = []
        for call in calls:
            # Five operands: destination base/address, source base/address, bytes.
            operands = re.findall(r'(?:i8 addrspace\(1\)\*|i64) (' + ssa + r'|\d+)', call)
            if len(operands) == 5 and depends(operands[4], length, defs):
                consumers.append(depends(operands[1], dst, defs) and depends(operands[3], src, defs))
        ok = (count.startswith('%') and size == src_size == dst_size and dynamic_size(size, defs)
              and bool(consumers) and all(consumers))
        sites.append(dict(length=length, count=count, element_size=size, src_index=src,
                          dst_index=dst, result_reaches_copy=bool(consumers), passed=ok))
    details.append(dict(symbol=name, sites=sites, passed=bool(sites) and all(x['passed'] for x in sites)))
missing = [n for n in required if n not in selected]
disasm = (out / 'clone.disasm').read_text(errors='replace')
lowered = ('CJ_MCC_ArrayCopyGeneric' in disasm and len(re.findall(r'\bimul\b', disasm)) >= 2
           and not re.search(r'\bshl\s+\$0x3,|\blea\s+[^\n]*,[ ]*8\)', disasm))
rows.append(dict(name='genericArrayCopyUsesElementLayout', passed=not missing and bool(details)
                 and all(x['passed'] for x in details) and lowered, missing=missing,
                 lowered_clone_dynamic_stride=lowered, functions=details))

# Independent control: byte-array sites retain their one-byte element stride.
byte_sites = []
for name, body in bodies.items():
    if name.startswith('_CNat6String'):
        for line in body.splitlines():
            if re.search(r'%arr\.data\.len\d* = mul i64 .*?, 1(?:,|$)', line):
                byte_sites.append(dict(symbol=name, instruction=line.strip()))
rows.append(dict(name='byteArrayStrideControl', passed=bool(byte_sites), sites=byte_sites))

# Walk the actual clone len==0 successor; it must return without copying.
clone = bodies.get(required[0], '')
blocks = {m[1]: m[2] for m in re.finditer(r'^([-a-zA-Z$._0-9]+):[^\n]*\n(.*?)(?=^[-a-zA-Z$._0-9]+:|\Z)', clone, re.M | re.S)}
zero = re.search(r'(' + ssa + r') = icmp eq i64 ' + ssa + r', 0[^\n]*\n  br i1 \1, label %([-a-zA-Z$._0-9]+)', clone)
visited = set()
pending = [zero[2]] if zero else []
while pending:
    label = pending.pop()
    if label in visited:
        continue
    visited.add(label)
    pending.extend(re.findall(r'label %([-a-zA-Z$._0-9]+)', blocks.get(label, '').split('; preds =')[0]))
zero_ok = bool(visited) and all('array.copy' not in blocks.get(b, '') for b in visited) and any('ret void' in blocks.get(b, '') for b in visited)
rows.append(dict(name='emptyCloneControl', passed=zero_ok, blocks=sorted(visited)))

(out / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
for row in rows:
    print(('PASS ' if row['passed'] else 'FAIL ') + row['name'])
    if row['name'] == 'genericArrayCopyUsesElementLayout':
        print('TARGET_ASSERTION_EXECUTED functions=' + str(len(details)) + ' missing=' + repr(missing))
        for detail in details:
            print(json.dumps(detail))
sys.exit(0 if all(r['passed'] for r in rows) else 1)
