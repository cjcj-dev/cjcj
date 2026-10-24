import path from 'node:path';
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {BuildError} from './errors.mjs';

// PE DLL exports and executable imports are separate tables. `nm -D` is an
// ELF interface and cannot establish either table for a stripped Windows SDK.
export function readPeSymbols(file, target, kind) {
  if (!['imports', 'exports'].includes(kind)) throw new BuildError('runtime.pe-symbols', 'invalid table');
  const fd = fs.openSync(file, 'r');
  try {
    const dos = Buffer.alloc(64), pe = Buffer.alloc(26), size = fs.fstatSync(fd).size;
    if (fs.readSync(fd, dos, 0, 64, 0) !== 64 || dos.toString('ascii', 0, 2) !== 'MZ')
      throw new BuildError('runtime.pe-symbols', 'expected x64 PE/COFF image');
    const offset = dos.readUInt32LE(60);
    if (offset < 64 || offset + pe.length > size || fs.readSync(fd, pe, 0, pe.length, offset) !== pe.length
      || pe.readUInt32LE(0) !== 0x4550 || pe.readUInt16LE(4) !== 0x8664 || pe.readUInt16LE(24) !== 0x20b)
      throw new BuildError('runtime.pe-symbols', 'expected x64 PE/COFF image');
  } finally { fs.closeSync(fd); }
  const program = target.spec.llvmBinDir
    ? path.join(target.spec.llvmBinDir, 'llvm-readobj' + (process.platform === 'win32' ? '.exe' : ''))
    : 'llvm-readobj';
  const result = spawnSync(program, [`--coff-${kind}`, file], {encoding: 'utf8'});
  if (result.status !== 0) throw new BuildError('runtime.pe-symbols',
    `llvm-readobj failed: rc=${result.status} ${result.error?.message || result.stderr || ''}`);
  if (!/^Format: COFF-x86-64\s*$/m.test(result.stdout)) throw new BuildError('runtime.pe-symbols', 'expected x64 PE/COFF image');
  const block = kind === 'exports' ? /Export \{([\s\S]*?)^\}/gm : /(?:Delay)?Import \{([\s\S]*?)^\}/gm;
  const names = [];
  for (const match of result.stdout.matchAll(block)) {
    const expression = kind === 'exports' ? /^\s*Name: (\S+)\s*$/gm : /^\s*Symbol: (\S+) \(\d+\)\s*$/gm;
    for (const row of match[1].matchAll(expression)) names.push(row[1]);
  }
  return names.join('\n');
}
