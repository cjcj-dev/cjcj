// Minimal on-disk SDK fixture with the three runtime roles, for layout/relocation contracts.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export function elf(machine, payload) {
  const header = Buffer.alloc(64);
  header.writeUInt32BE(0x7f454c46, 0); header[4] = 2; header[5] = 1; header.writeUInt16LE(3, 16); header.writeUInt16LE(machine, 18);
  return Buffer.concat([header, Buffer.from(payload)]);
}

export function makeSdk({tuple = 'linux_x86_64_cjnative', machine = 62, host = 'official-host-runtime', product = 'coloured-runtime', exec} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-fixture-')), sdk = path.join(root, 'cangjie');
  const put = (rel, data) => { fs.mkdirSync(path.dirname(path.join(sdk, rel)), {recursive: true}); fs.writeFileSync(path.join(sdk, rel), data); };
  put('bin/cjc', '#!/bin/sh\n');
  put(`runtime/lib/${tuple}/libcangjie-runtime.so`, elf(machine, product));
  put(`.compiler-exec/runtime/lib/${tuple}/libcangjie-runtime.so`, elf(machine, exec ?? product));
  if (host !== null) put(`.host/runtime/lib/${tuple}/libcangjie-runtime.so`, elf(machine, host));
  put('lib/linux_x86_64_cjnative/std/core.cjo', 'cjo');
  return {root, sdk};
}
