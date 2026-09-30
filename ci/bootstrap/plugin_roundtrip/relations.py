"""GDB read-only observer for x86_64 official-host compiler objects.

Offsets must be verified against this ELF's getter/AddExtend/ArrayList.add
instructions. No inferior calls or memory writes are performed.
"""
import gdb
import json
import os

observed = {}
active = False
completed = False
records = []
errors = []

def word(address):
    return int.from_bytes(gdb.selected_inferior().read_memory(address, 8), 'little')

def pointer(address):
    value = word(address)
    # Official HRT IdleBarrier uses the low 48 address bits. Refuse a
    # forwarded/invalid object header instead of interpreting it as live data.
    address_bits = value & ((1 << 48) - 1)
    if address_bits and word(address_bits) >> 48:
        errors.append(f'object header requires relocation resolution: {value:#x}')
        raise RuntimeError(errors[-1])
    return address_bits

def type_name(obj):
    return gdb.execute('info symbol ' + hex(word(obj)), to_string=True).strip()

def caller_is_restore():
    f = gdb.newest_frame().older()
    return f is not None and 'StringToCHIRPtr' in (f.name() or '')

class Begin(gdb.Breakpoint):
    def stop(self):
        global active
        active = True
        return False

pending = None

def check_pending():
    global pending
    if pending is None:
        return
    definition, ty, kind = pending
    pending = None
    if any(k in kind for k in ('StructType.ti', 'ClassType.ti', 'EnumType.ti')):
        category = 'custom'
        owner = pointer(ty + 0x20)
        collection = pointer(owner + 0xc0)
    elif any(k in kind for k in ('IntType.ti', 'BooleanType.ti', 'FloatType.ti', 'RuneType.ti', 'UnitType.ti', 'CStringType.ti')):
        category = 'builtin'
        owner = ty
        collection = pointer(owner + 0x20)
    else:
        records.append(dict(definition=hex(definition), type=kind, status='outside-observed-types'))
        return
    raw = pointer(collection + 8)
    offset = word(collection + 0x10)
    capacity = word(collection + 0x18)
    size = word(collection + 0x20)
    if size > capacity or size > 100000:
        errors.append('invalid ArrayList layout')
        raise RuntimeError(errors[-1])
    contents = [pointer(raw + 16 + 8 * (offset + i)) for i in range(size)]
    record = dict(category=category, definition=hex(definition), type=kind,
                  owner=hex(owner), size=size, members=[hex(x) for x in contents],
                  present=definition in contents)
    records.append(record)
    print('ASSERT restored-relation ' + json.dumps(record), flush=True)

class ReturnedType(gdb.FinishBreakpoint):
    def __init__(self, definition):
        super().__init__(gdb.newest_frame(), internal=True)
        self.definition = definition
    def stop(self):
        global pending
        ty = int(gdb.parse_and_eval('$rax'))
        kind = type_name(ty)
        observed[self.definition] = (ty, kind)
        pending = (self.definition, ty, kind)
        return False

class Target(gdb.Breakpoint):
    def stop(self):
        if active and caller_is_restore():
            definition = int(gdb.parse_and_eval('$rdi'))
            # Check the completed iteration before advancing, so the observer
            # never retains object addresses across unrelated compiler phases.
            if pending is not None and definition != pending[0]:
                check_pending()
            ReturnedType(definition)
        return False

class End(gdb.Breakpoint):
    def stop(self):
        global active, completed
        if not active or not caller_is_restore():
            return False
        check_pending()
        active = False
        completed = True
        return False

restore = '_CN13cjcj:frontend13ExecutePlugin15StringToCHIRPtrHCNac9ArrayListICN9cjcj:chir8FunctionEECNacY5_ICNY7_9GlobalVarEEY3_CNac7HashMapICNY7_5BlockECNY7_10ExpressionEE'
Begin('*' + "'" + restore + "'")
Target("*'_CN9cjcj:chir9ExtendDef15GetExtendedTypeHv'")
End("*'_CN9cjcj:chir11CHIRBuilder23UpdateTypeInCorePackageHv'")
gdb.execute('run')
checks = {c: [r for r in records if r.get('category') == c] for c in ('builtin', 'custom')}
summary = dict(completed=completed, errors=errors, complete_census=len(records) == len(observed), relations=records,
               assertions={c: bool(rs) and all(r['present'] for r in rs) for c, rs in checks.items()})
with open(os.environ['RELATION_JSON'], 'w') as f:
    json.dump(summary, f, indent=2)
print('RELATION_SUMMARY ' + json.dumps({k:v for k,v in summary.items() if k != 'relations'}))
gdb.execute('quit ' + ('0' if completed and not errors and summary['complete_census'] and all(summary['assertions'].values()) else '1'))
