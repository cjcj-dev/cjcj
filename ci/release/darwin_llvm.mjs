// Native container/source checks; manifests record producer facts, not SDK authority.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {sdkPlatform} from '../bootstrap/sdk-platform.mjs';

export function darwinPlatform(platform) {
  const native = sdkPlatform(platform);
  assert.equal(native.os, 'darwin', 'DARWIN_INPUT_PLATFORM');
  return {...native, platform, cpu: native.arch === 'arm64' ? 0x0100000c : 0x01000007};
}
export function verifyDarwinMachO(file, platform) {
  const {cpu} = darwinPlatform(platform);
  assert.ok(fs.statSync(file).isFile(), `DARWIN_INPUT_REGULAR_FILE: ${file}`);
  const header = Buffer.alloc(32), fd = fs.openSync(file, 'r');
  let size;
  try { size = fs.readSync(fd, header, 0, header.length, 0); }
  finally { fs.closeSync(fd); }
  assert.ok(size === 32 && header.readUInt32LE(0) === 0xfeedfacf, `DARWIN_INPUT_MACH_O: ${file}`);
  assert.equal(header.readUInt32LE(4), cpu, `DARWIN_INPUT_CPU: ${file}`);
  assert.equal(header.readUInt32LE(12), 6, `DARWIN_INPUT_DYLIB: ${file}`);
  return {file: fs.realpathSync(file), platform, cpu};
}
export function verifyDarwinLlvm(root, platform, llvmSha) {
  const native = darwinPlatform(platform);
  assert.match(llvmSha || '', /^[a-f0-9]{40}$/, 'LLVM_DYLIB_SOURCE_PIN');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  assert.equal(manifest.platform, platform, 'LLVM_DYLIB_PLATFORM_MISMATCH');
  assert.equal(manifest.library, native.llvmLibrary, 'LLVM_DYLIB_LIBRARY_MISMATCH');
  assert.equal(manifest.llvm_sha, llvmSha, 'LLVM_DYLIB_SOURCE_MISMATCH');
  assert.deepEqual(manifest.targets, ['X86', 'ARM', 'AArch64'], 'LLVM_DYLIB_TARGETS_MISMATCH');
  const input = verifyDarwinMachO(path.join(root, native.llvmLibrary), platform);
  const stamps = [...new Set([...fs.readFileSync(input.file).toString('latin1')
    .matchAll(/CJLLVM-COMMIT:([0-9a-z-]+)/g)].map(match => match[1]))];
  assert.deepEqual(stamps, [llvmSha], 'LLVM_DYLIB_SOURCE_STAMP_MISMATCH');
  return {...input, llvm_sha: llvmSha, tuple: native.tuple};
}
