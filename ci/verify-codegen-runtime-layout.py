#!/usr/bin/env python3
"""Read real frontend bitcode using LLVM's C API and the paired layout header."""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import re
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--llvm-library', type=Path, required=True)
    p.add_argument('--header', type=Path, required=True)
    p.add_argument('--bitcode', type=Path, required=True)
    p.add_argument('--result', type=Path, required=True)
    p.add_argument('--surface', choices=('objects', 'arrays'), required=True)
    a = p.parse_args()
    llvm = C.CDLL(str(a.llvm_library.resolve()))
    ptr, uint, ull = C.c_void_p, C.c_uint, C.c_ulonglong
    def api(name, result, *args):
        fn = getattr(llvm, name); fn.restype = result; fn.argtypes = args
        return fn
    context = api('LLVMContextCreate', ptr)()
    api('LLVMContextSetOpaquePointers', None, ptr, C.c_int)(context, 0)
    buffer, message, module = ptr(), C.c_char_p(), ptr()
    if api('LLVMCreateMemoryBufferWithContentsOfFile', C.c_int, C.c_char_p, C.POINTER(ptr), C.POINTER(C.c_char_p))(
            str(a.bitcode).encode(), C.byref(buffer), C.byref(message)):
        raise RuntimeError(message.value.decode())
    if api('LLVMParseBitcodeInContext2', C.c_int, ptr, ptr, C.POINTER(ptr))(context, buffer, C.byref(module)):
        raise RuntimeError('LLVM rejected product bitcode')
    a.result.with_suffix('.ll').write_bytes(api('LLVMPrintModuleToString', C.c_char_p, ptr)(module))
    td = api('LLVMCreateTargetData', ptr, C.c_char_p)(api('LLVMGetDataLayoutStr', C.c_char_p, ptr)(module))
    kind = api('LLVMGetTypeKind', C.c_int, ptr)
    type_of = api('LLVMTypeOf', ptr, ptr)
    size = api('LLVMABISizeOfType', ull, ptr, ptr)
    offset = api('LLVMOffsetOfElement', ull, ptr, ptr, uint)
    count = api('LLVMCountStructElementTypes', uint, ptr)
    field = api('LLVMStructGetTypeAtIndex', ptr, ptr, uint)
    address_space = api('LLVMGetPointerAddressSpace', uint, ptr)
    name = api('LLVMGetValueName', C.c_char_p, ptr)
    operand = api('LLVMGetOperand', ptr, ptr, uint)
    operands = api('LLVMGetNumOperands', C.c_int, ptr)
    is_int = api('LLVMIsAConstantInt', ptr, ptr)
    integer = api('LLVMConstIntGetZExtValue', ull, ptr)
    opcode = api('LLVMGetInstructionOpcode', C.c_int, ptr)
    gep_type = api('LLVMGetGEPSourceElementType', ptr, ptr)
    is_gep = api('LLVMIsAGetElementPtrInst', ptr, ptr)
    is_cast = api('LLVMIsABitCastInst', ptr, ptr)
    is_instruction = api('LLVMIsAInstruction', ptr, ptr)
    print_value = api('LLVMPrintValueToString', C.c_char_p, ptr)
    ti = api('LLVMGetTypeByName2', ptr, ptr, C.c_char_p)(context, b'TypeInfo')
    values = {n: int(v) for n, v in re.findall(r'constexpr unsigned (\w+) = (\d+);', a.header.read_text())}
    fields = 'typeInfoName type flag fieldNum instanceSize gctib uuid align typeArgsNum validInheritNum fieldOffsets sourceGeneric typeArgs fields superTypeInfo vExtensionDataStart mTableDesc reflectInfo'.split()
    # Type specification is the upstream CGType.cpp:480-502 table, independent
    # of the frontend being tested. Numeric layout expectations come from runtime.
    widths = [0, 8, 8, 16, 32, 0, 32, 8, 8, 16, 0, 0, 0, 0, 0, 0, 0, 0]
    pointees = {f: 'i8' for f, w in zip(fields, widths) if not w}
    pointees.update(gctib='BitMap', fieldOffsets='i32', superTypeInfo='TypeInfo', vExtensionDataStart='ExtensionDef*')
    def describe(t):
        if kind(t) == 8:
            return 'i' + str(api('LLVMGetIntTypeWidth', uint, ptr)(t))
        if kind(t) == 10:
            return (api('LLVMGetStructName', C.c_char_p, ptr)(t) or b'<anonymous>').decode()
        if kind(t) == 12:
            return describe(api('LLVMGetElementType', ptr, ptr)(t)) + '*' + ('' if address_space(t) == 0 else 'AS' + str(address_space(t)))
        return 'kind=' + str(kind(t))
    checks = {}
    def check(label, ok, observed):
        checks[label] = {'pass': bool(ok), 'observed': observed}
        print(f'ASSERT {label}={"PASS" if ok else "FAIL"} {json.dumps(observed)}')
    check('typeinfo.present', bool(ti), bool(ti))
    if ti:
        n = count(ti)
        check('typeinfo.field_count', n == len(fields), n)
        check('typeinfo.size', size(td, ti) == values['TypeInfoSize'], size(td, ti))
        check('typeinfo.unpacked', not api('LLVMIsPackedStruct', C.c_int, ptr)(ti), bool(api('LLVMIsPackedStruct', C.c_int, ptr)(ti)))
        alignment = api('LLVMABIAlignmentOfType', uint, ptr, ptr)(td, ti)
        check('typeinfo.alignment', alignment == api('LLVMPointerSize', uint, ptr)(td), alignment)
        for f, w in zip(fields, widths):
            i = values[f + 'Index']
            if i >= n:
                check('typeinfo.' + f, False, 'index outside emitted struct'); continue
            t = field(ti, i)
            type_ok = (kind(t) == 8 and api('LLVMGetIntTypeWidth', uint, ptr)(t) == w) if w else (kind(t) == 12 and address_space(t) == 0 and describe(api('LLVMGetElementType', ptr, ptr)(t)) == pointees[f])
            check('typeinfo.' + f, type_ok and offset(td, ti, i) == values[f + 'Offset'],
                  {'type': describe(t), 'kind': kind(t), 'width': api('LLVMGetIntTypeWidth', uint, ptr)(t) if kind(t) == 8 else None, 'offset': offset(td, ti, i)})
    surfaces = ('size', 'payload', 'boxed') if a.surface == 'objects' else ('array_static', 'array_dynamic_get', 'array_dynamic_set', 'array_dynamic_ref')
    witnesses = {k: [] for k in ('size', 'payload', 'array_static', 'array_dynamic_get', 'array_dynamic_set', 'array_dynamic_ref', 'boxed')}
    get_first = api('LLVMGetFirstFunction', ptr, ptr); get_next = api('LLVMGetNextFunction', ptr, ptr)
    first_block = api('LLVMGetFirstBasicBlock', ptr, ptr); next_block = api('LLVMGetNextBasicBlock', ptr, ptr)
    first_inst = api('LLVMGetFirstInstruction', ptr, ptr); next_inst = api('LLVMGetNextInstruction', ptr, ptr)
    ref_loads = []
    function = get_first(module)
    while function:
        fn = name(function).decode()
        block = first_block(function)
        while block:
            inst = first_inst(block)
            while inst:
                label = name(inst).decode()
                if 'layoutRawRef' in fn and label.startswith('arr.idx.get') and not is_gep(inst):
                    ref_loads.append(print_value(inst).decode())
                if is_gep(inst):
                    text = print_value(inst).decode()
                    if label.startswith('ti.size'):
                        idx = operand(inst, 2)
                        good = is_int(idx) and integer(idx) == values['instanceSizeIndex']
                        witnesses['size'].append({'function': fn, 'ir': text, 'pass': bool(good)})
                    if label.startswith('obj.payload') and not label.startswith('obj.payload.slot'):
                        idx = operand(inst, 1)
                        observed = integer(idx) * size(td, gep_type(inst)) if is_int(idx) else None
                        witnesses['payload'].append({'function': fn, 'ir': text, 'offset': observed,
                                                    'pass': observed == values['ObjectHeaderSize'] and address_space(type_of(inst)) == 1})
                    if label.startswith('arr.idx.get.gep') and 'layoutRawStatic' in fn:
                        src = gep_type(inst)
                        observed = offset(td, src, 1) if kind(src) == 10 and count(src) == 2 else None
                        witnesses['array_static'].append({'function': fn, 'ir': text, 'offset': observed,
                            'pass': observed == values['ArrayHeaderSize'] - values['ArrayLengthOffset'] and address_space(type_of(inst)) == 1})
                    # Dynamic raw-array addressing is i8 GEP(array, mul(size,index)+header).
                    if any(n in fn for n in ('layoutRawGet', 'layoutRawSet', 'layoutRawRef')) and name(operand(inst, 0)) == b'array' and kind(gep_type(inst)) == 8 and api('LLVMGetIntTypeWidth', uint, ptr)(gep_type(inst)) == 8 and operands(inst) == 2:
                        idx = operand(inst, 1)
                        if is_instruction(idx) and opcode(idx) == 8:
                            constants = [integer(operand(idx, i)) for i in range(2) if is_int(operand(idx, i))]
                            if constants:
                                branch = 'array_dynamic_set' if 'Set' in fn or 'set' in fn else 'array_dynamic_ref' if 'Ref' in fn or 'ref' in fn else 'array_dynamic_get'
                                witnesses[branch].append({'function': fn, 'ir': text, 'offset': constants,
                                    'pass': constants == [values['ArrayHeaderSize']] and address_space(type_of(inst)) == 1})
                    if kind(gep_type(inst)) == 8 and operands(inst) == 2 and is_int(operand(inst, 1)) and ('boxed' in fn or 'Cell' in fn):
                        observed = integer(operand(inst, 1))
                        witnesses['boxed'].append({'function': fn, 'ir': text, 'offset': observed,
                                                  'pass': observed == values['ObjectHeaderSize']})
                inst = next_inst(inst)
            block = next_block(block)
        function = get_next(function)
    for label in surfaces:
        rows = witnesses[label]
        # Presence and the value assertion are separate; one missing witness
        # never masks the assertions on the other product results.
        check(label + '.witness', bool(rows), len(rows))
        check(label + '.value', bool(rows) and all(r['pass'] for r in rows), rows)
    if a.surface == 'arrays':
        check('array_dynamic_ref.direct_address', bool(witnesses['array_dynamic_ref']) and not ref_loads, ref_loads)
    globals_ = []
    semantic = {}
    glob = api('LLVMGetFirstGlobal', ptr, ptr)(module)
    next_global = api('LLVMGetNextGlobal', ptr, ptr)
    initializer = api('LLVMGetInitializer', ptr, ptr)
    while glob:
        init = initializer(glob)
        if init and type_of(init) == ti:
            global_name = name(glob).decode()
            globals_.append({'name': global_name, 'ir': print_value(init).decode()})
            if a.surface == 'objects' and global_name in ('layout_contract:Parent.ti', 'layout_contract:Child.ti', 'layout_contract:Cell<Int64>.ti'):
                observed = {}
                for f in ('fieldNum', 'instanceSize', 'align', 'typeArgsNum'):
                    v = operand(init, values[f + 'Index'])
                    observed[f] = integer(v) if is_int(v) else None
                observed['super'] = print_value(operand(init, values['superTypeInfoIndex'])).decode()
                observed['fields'] = print_value(operand(init, values['fieldsIndex'])).decode()
                observed['offsets'] = print_value(operand(init, values['fieldOffsetsIndex'])).decode()
                semantic[global_name] = observed
        glob = next_global(glob)
    check('initializers.present', bool(globals_), globals_)
    if a.surface == 'objects':
        specs = {'layout_contract:Parent.ti': (1, 4, 4, 0),
                 'layout_contract:Child.ti': (2, 16, 8, 0),
                 'layout_contract:Cell<Int64>.ti': (1, 8, 8, 1)}
        for global_name, expected in specs.items():
            observed = semantic.get(global_name, {})
            actual = tuple(observed.get(f) for f in ('fieldNum', 'instanceSize', 'align', 'typeArgsNum'))
            check('initializer.' + global_name, actual == expected and '.fields' in observed.get('fields', '') and '.offsets' in observed.get('offsets', ''), observed)
        check('initializer.inheritance', 'layout_contract:Parent.ti' in semantic.get('layout_contract:Child.ti', {}).get('super', ''), semantic.get('layout_contract:Child.ti', {}).get('super'))
    result = {'checks': checks, 'hashes': {str(f): hashlib.sha256(f.read_bytes()).hexdigest()
              for f in (a.llvm_library, a.header, a.bitcode)}, 'datalayout': api('LLVMGetDataLayoutStr', C.c_char_p, ptr)(module).decode()}
    a.result.write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(c['pass'] for c in checks.values()) else 1

if __name__ == '__main__':
    sys.exit(main())
