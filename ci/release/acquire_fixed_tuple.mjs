#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {acquire, verify} from './bootstrap_store.mjs';

const [pinFile, destination, sumsSha] = process.argv.slice(2);
if (!pinFile || !destination || !/^[a-f0-9]{64}$/.test(sumsSha || '')) {
  throw new Error('usage: acquire_fixed_tuple.mjs PIN DESTINATION LLVM_TUPLE_SUMS_SHA');
}
const pin = JSON.parse(fs.readFileSync(pinFile, 'utf8'));
// Share the release consumer's source selection and per-asset verification.
const tuple = await acquire(pin, path.dirname(destination));
try {
  verify(fs.readFileSync(path.join(tuple, 'SHA256SUMS')), sumsSha, 'LLVM_TUPLE_SUMS_SHA');
  const checked = spawnSync('sha256sum', ['--strict', '-c', 'SHA256SUMS'], {
    cwd: tuple, stdio: 'inherit',
  });
  if (checked.status !== 0) throw new Error('fixed LLVM tuple checksum verification failed');
  // Publish only after all pinned assets and the independently pinned sums pass.
  fs.rmSync(destination, {recursive: true, force: true});
  fs.renameSync(tuple, destination);
  console.log(`FIXED_LLVM_RELEASE_VERIFIED ${destination} ${sumsSha}`);
} finally {
  fs.rmSync(path.dirname(tuple), {recursive: true, force: true});
}
