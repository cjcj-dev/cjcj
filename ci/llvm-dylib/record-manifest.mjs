#!/usr/bin/env zx
// Record the sources actually checked out by the native producer beside its SO.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const [directory, llvmSource, runtimeSource] = process.argv.slice(2);
const {CJCJ_NATIVE_LLVM_REF: LLVM_SHA, CJCJ_NATIVE_RUNTIME_REF, LLVM_DYLIB_PLATFORM, LLVM_DYLIB_LIBRARY,
  GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_ENV} = process.env;
if (!directory || !llvmSource || !runtimeSource) throw new Error('LLVM_DYLIB_SOURCE_LOCATIONS_REQUIRED');
for (const [source, sha] of [[llvmSource, LLVM_SHA], [runtimeSource, CJCJ_NATIVE_RUNTIME_REF]]) {
  if (!/^[a-f0-9]{40}$/.test(sha || '')
      || execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim() !== sha)
    throw new Error('LLVM_DYLIB_CHECKOUT_MISMATCH');
}
const library = /^(linux)_(x86_64|aarch64)$/.test(LLVM_DYLIB_PLATFORM || '') ? 'libLLVM-15.so'
  : /^darwin_(x86_64|aarch64)$/.test(LLVM_DYLIB_PLATFORM || '') ? 'libLLVM.dylib' : undefined;
if (!library || LLVM_DYLIB_LIBRARY !== library) throw new Error('LLVM_DYLIB_PLATFORM_MISMATCH');
if (![GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT].every(value => /^[1-9][0-9]*$/.test(value || '')))
  throw new Error('LLVM_DYLIB_RUN_REQUIRED');
const sha256 = crypto.createHash('sha256').update(fs.readFileSync(path.join(directory, library))).digest('hex');
const manifest = {llvm_sha:LLVM_SHA, runtime_sha:CJCJ_NATIVE_RUNTIME_REF, sha256,
  platform:LLVM_DYLIB_PLATFORM, library, targets:['X86', 'ARM', 'AArch64'],
  run_id:GITHUB_RUN_ID, run_attempt:GITHUB_RUN_ATTEMPT};
fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify(manifest) + '\n');
if (GITHUB_ENV) fs.appendFileSync(GITHUB_ENV, `BUILT_DYLIB_SHA256=${sha256}\n`);
console.log(JSON.stringify(manifest));
