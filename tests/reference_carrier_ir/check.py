#!/usr/bin/env python3
"""Check actual std.core IR emitted by the candidate compiler, not a model."""
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
functions = re.findall(r'^define .*?^}', text, re.M | re.S)
failures = []


def check(name, predicate):
    print(f'REFERENCE1356_IR_TARGET {name} pass={bool(predicate)}')
    if not predicate:
        failures.append(name)


def function(name):
    found = [body for body in functions if name in body.splitlines()[0]]
    check('present_' + name, len(found) == 1)
    return found[0] if len(found) == 1 else ''


for klass, count, size in [('Reference', 4, 32), ('FinalReference', 4, 32), ('Finalizer', 6, 48)]:
    prefix = f'@"std.core:{klass}.ti" = '
    lines = [line for line in text.splitlines() if line.startswith(prefix)]
    kind = -128 if klass == 'Reference' else -120
    check('layout_' + klass, len(lines) == 1 and f'i8 {kind}, i8 0, i16 {count}, i32 {size},' in lines[0])
    offsets = [line for line in text.splitlines() if line.startswith(f'@"std.core:{klass}.ti.offsets" = ')]
    check('offsets_' + klass, len(offsets) == 1 and
          f'[{count} x i32] [' + ', '.join(f'i32 {i * 8}' for i in range(count)) + ']' in offsets[0])

get = function('FinalReference11getInactive')
clear = function('FinalReference13clearInactive')
enqueue = function('ReferenceQueue8enqueue0')
check('final_referent_strong_load', '@llvm.cj.gcread.ref(' in get and '@llvm.cj.gcread.weak' not in get)
check('final_referent_strong_clear', any('@llvm.cj.gcwrite.ref(i8 addrspace(1)* null, i8 addrspace(1)* %this,' in line and 'i32 1)' in line for line in clear.splitlines()))
check('inactive_next_volatile', '@llvm.cj.atomic.load(' in get and 'i32 5)' in get)
check('queue_links_volatile', sum('@llvm.cj.atomic.store(' in line and 'i32 5)' in line for line in enqueue.splitlines()) == 3)
check('queue_lock_strong', '@llvm.cj.gcread.ref(' in enqueue and '@llvm.cj.gcread.weak' not in enqueue)
check('callbacks_published', any('call void @CJ_MCC_SetReferenceMethods(' in line for line in text.splitlines()))
print(f'REFERENCE1356_IR_RESULT failures={len(failures)}')
sys.exit(bool(failures))
