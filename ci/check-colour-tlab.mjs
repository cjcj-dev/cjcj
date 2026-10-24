#!/usr/bin/env zx
// Byte-layout check from the fixed #715 scanner (LLVM 67934046); this does not
// establish that a compiler or a generated program executed successfully.
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

function count(bytes, hex) {
  const pattern = Buffer.from(hex, 'hex');
  let found = 0, offset = 0;
  while ((offset = bytes.indexOf(pattern, offset)) !== -1) {
    found++; offset += pattern.length;
  }
  return found;
}
export function inspect(file) {
  const bytes = fs.readFileSync(file);
  const oldObject = count(bytes, '488b12488b02488b4a08');
  const oldArray = count(bytes, '4d8b09498b014d8b5108');
  const newObject = count(bytes, '498b17488b02488b4a08');
  const newArray = count(bytes, '498b014d8b5108') - oldArray;
  const symbols = spawnSync('nm', ['-u', file], {encoding: 'utf8'});
  if (symbols.status !== 0) throw new Error(`nm failed rc=${symbols.status} signal=${symbols.signal}: ${symbols.stderr || symbols.error}`);
  const refs = [...new Set(symbols.stdout.split(/\r?\n/).map(line => line.trim().split(/\s+/).at(-1))
    .filter(name => name.split('@')[0].startsWith('g_cjLoad')))].sort();
  return {file, sha256: createHash('sha256').update(bytes).digest('hex'),
    three_level: oldObject + oldArray, two_level: newObject + newArray, colour_refs: refs};
}
export function main(files) {
  if (!files.length) throw new Error('usage: check-colour-tlab.mjs FILE [FILE...]');
  let failed = false;
  for (const file of files) {
    const row = inspect(file);
    row.assertions = {three_level_zero: row.three_level === 0,
      two_level_present: row.two_level > 0, colour_refs_present: row.colour_refs.length > 0};
    console.log(JSON.stringify(row));
    failed ||= !Object.values(row.assertions).every(Boolean);
  }
  return failed ? 1 : 0;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
