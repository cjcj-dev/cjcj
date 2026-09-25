#!/usr/bin/env python3
"""Strict bytes plus the #203, #200-run-specific decoded FINAL-field exception.

Never rewrites either artifact. Every differing byte must belong to an identified
VirtualMethodInfo.attributes field in an imported std.core Iterator subclass,
and the decoded field must differ in exactly FINAL (bit 11). All other bytes,
including vector ordering and layout, remain subject to exact comparison.
Schema: CHIRFlatBufferSchema.cj:608-624, 789, 935, 941-960, 995, 1138-1143.
"""
import argparse
import json
from pathlib import Path
import struct


class Package:
    def __init__(self, data):
        self.data = data
        self.root = self.number('I', 0)
        self.types = self.vector(self.root, 12)
        self.defs = self.vector(self.root, 24)
        self.type_tags = self.pointer(self.root, 10)
        self.def_tags = self.pointer(self.root, 22)

    def number(self, format_, offset):
        return struct.unpack_from('<' + format_, self.data, offset)[0]

    def field(self, table, slot):
        vtable = table - self.number('i', table)
        if slot >= self.number('H', vtable):
            return 0
        relative = self.number('H', vtable + slot)
        return table + relative if relative else 0

    def scalar(self, table, slot, format_='I'):
        offset = self.field(table, slot)
        return self.number(format_, offset) if offset else 0

    def pointer(self, table, slot):
        offset = self.field(table, slot)
        return offset + self.number('I', offset) if offset else 0

    def vector(self, table, slot):
        offset = self.pointer(table, slot)
        if not offset:
            return []
        return [p + self.number('I', p)
                for p in range(offset + 4, offset + 4 + 4 * self.number('I', offset), 4)]

    def string(self, table, slot):
        offset = self.pointer(table, slot)
        if not offset:
            return ''
        return self.data[offset + 4:offset + 4 + self.number('I', offset)].decode()

    def iterator_subclass(self, index):
        visited = set()
        while index not in visited and 0 <= index < len(self.defs):
            visited.add(index)
            if self.data[self.def_tags + 4 + index] != 3:  # ClassDef
                return False
            superclass = self.scalar(self.defs[index], 12)
            if not superclass or self.data[self.type_tags + 4 + superclass - 1] != 5:
                return False
            index = self.scalar(self.types[superclass - 1], 6) - 1
            custom = self.pointer(self.defs[index], 4)
            if self.string(custom, 14) == 'std.core' and self.string(custom, 10) == 'Iterator':
                return True
        return False

    def permitted_fields(self):
        fields = {}
        for index, definition in enumerate(self.defs):
            if self.data[self.def_tags + 4 + index] != 3:
                continue
            custom = self.pointer(definition, 4)
            base = self.pointer(custom, 4)
            if (self.string(custom, 14) != 'std.core'
                    or not self.scalar(base, 10, 'Q') & (1 << 15)
                    or not self.iterator_subclass(index)):
                continue
            owner = self.string(custom, 12)
            for table_index, vtable in enumerate(self.vector(custom, 30)):
                for method_index, method in enumerate(self.vector(vtable, 6)):
                    offset = self.field(method, 12)
                    if offset:
                        fields[(owner, table_index, method_index, self.string(method, 4))] = (
                            offset, self.number('Q', offset))
        return fields


def compare(left, right):
    a, b = left.read_bytes(), right.read_bytes()
    if a == b:
        return {'strict_equal': True, 'decoded_equal': True, 'exceptions': []}
    result = {'strict_equal': False, 'decoded_equal': False, 'exceptions': []}
    if len(a) != len(b):
        result['reason'] = 'artifact lengths differ'
        return result
    differences = {i for i, (x, y) in enumerate(zip(a, b)) if x != y}
    result['different_bytes'] = len(differences)
    pa, pb = Package(a).permitted_fields(), Package(b).permitted_fields()
    covered = set()
    for key in sorted(pa.keys() & pb.keys()):
        offset, av = pa[key]
        other_offset, bv = pb[key]
        if offset == other_offset and av ^ bv == (1 << 11):
            covered.update(range(offset, offset + 8))
            result['exceptions'].append({'entry': key, 'offset': offset,
                                         'left': hex(av), 'right': hex(bv)})
    result['unexplained_offsets'] = sorted(differences - covered)
    result['decoded_equal'] = not result['unexplained_offsets']
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('left', type=Path)
    parser.add_argument('right', type=Path)
    args = parser.parse_args()
    result = compare(args.left, args.right)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['decoded_equal'] else 1)
