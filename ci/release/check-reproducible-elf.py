#!/usr/bin/env python3
"""Compare actual ELF bytes/sections, including the Cangjie string dictionary.

Exit 1 on the release invariant violation, even for the expected cut arm.
No timestamps or sections are excluded from byte equality.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect(filename, marker):
    data = Path(filename).read_bytes()
    if data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('expected a little-endian ELF64')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    offset, entry_size, count, names_index = header[6], header[11], header[12], header[13]
    raw = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * entry_size) for i in range(count)]
    names = data[raw[names_index][4]:raw[names_index][4] + raw[names_index][5]]
    sections = {}
    metadata = None
    for section in raw[1:]:
        name = names[section[0]:].split(b'\0', 1)[0].decode()
        payload = b'' if section[1] == 8 else data[section[4]:section[4] + section[5]]
        sections[name] = dict(size=section[5], address=section[3], sha256=hashlib.sha256(payload).hexdigest())
        if name == '.cjmetadata':
            metadata = payload
    if metadata is None:
        raise ValueError('missing .cjmetadata')
    # Cjstart.S:48-61: StringPoolDict offset/size are header words 9 and 10.
    start, size = struct.unpack_from('<II', metadata, 9 * 4)
    if start + size > len(metadata):
        raise ValueError('StringPoolDict outside metadata')
    return dict(sha256=hashlib.sha256(data).hexdigest(), sections=sections,
                marker_count=data.count(marker.encode()), dictionary_offset=start,
                dictionary_size=size), data, metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('left')
    parser.add_argument('right')
    parser.add_argument('--marker', required=True)
    parser.add_argument('--json', required=True)
    args = parser.parse_args()
    left, a, am = inspect(args.left, args.marker)
    right, b, bm = inspect(args.right, args.marker)
    differences = [name for name in sorted(left['sections'].keys() | right['sections'].keys())
                   if left['sections'].get(name) != right['sections'].get(name)]
    md_diff = [i for i, (x, y) in enumerate(zip(am, bm)) if x != y]
    in_dict = (len(am) == len(bm) and left['dictionary_offset'] == right['dictionary_offset']
               and left['dictionary_size'] == right['dictionary_size']
               and all(left['dictionary_offset'] <= i < left['dictionary_offset'] + left['dictionary_size']
                       for i in md_diff))
    assertions = {'elf_bytes_equal': a == b, 'section_hashes_equal': not differences,
                  'source_prefix_absent': left['marker_count'] == right['marker_count'] == 0}
    result = dict(left=left, right=right, differing_sections=differences,
                  metadata_differing_bytes=len(md_diff), metadata_diff_all_in_dictionary=in_dict,
                  assertions=assertions)
    Path(args.json).write_text(json.dumps(result, indent=2) + '\n')
    for name, passed in assertions.items():
        print(f'ASSERT {name}={"PASS" if passed else "FAIL"}')
    print(f'SECTION_DIFF={differences} DICTIONARY_ONLY={in_dict} DIFF_BYTES={len(md_diff)}')
    return 0 if all(assertions.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
