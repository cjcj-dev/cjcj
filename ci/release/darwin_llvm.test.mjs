import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';
const {verifyDarwinLlvm, verifyDarwinMachO} = await import(process.env.DARWIN_LLVM_PRODUCT
  ? pathToFileURL(process.env.DARWIN_LLVM_PRODUCT).href : './darwin_llvm.mjs');
const platform = process.env.PLATFORM || 'darwin_aarch64';
function fixture(body) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-llvm-'));
  const native = process.env.DARWIN_LLVM_NATIVE_SOURCE;
  const manifest = native ? JSON.parse(fs.readFileSync(path.join(native, 'manifest.json'), 'utf8'))
    : {platform, library:'libLLVM.dylib', llvm_sha:'a'.repeat(40), targets:['X86','ARM','AArch64']};
  const file = path.join(root, 'libLLVM.dylib'), json = path.join(root, 'manifest.json');
  if (native) fs.copyFileSync(path.join(native, 'libLLVM.dylib'), file);
  else {
    const bytes = Buffer.alloc(32);
    bytes.writeUInt32LE(0xfeedfacf, 0);
    bytes.writeUInt32LE(platform === 'darwin_aarch64' ? 0x0100000c : 0x01000007, 4);
    bytes.writeUInt32LE(6, 12);
    fs.writeFileSync(file, Buffer.concat([bytes, Buffer.from(`CJLLVM-COMMIT:${manifest.llvm_sha}\0`)]));
  }
  const save = () => fs.writeFileSync(json, JSON.stringify(manifest));
  save();
  const check = () => verifyDarwinLlvm(root, platform, native ? process.env.CJCJ_NATIVE_LLVM_REF : 'a'.repeat(40));
  try { body({root, file, manifest, save, check}); }
  finally { fs.rmSync(root, {recursive:true, force:true}); }
}
test('matching producer container and source are accepted', () => fixture(({check}) => {
  const value = check();
  assert.equal(value.platform, platform);
  assert.equal(value.tuple, `${platform}_cjnative`);
}));
for (const [field, value, rule] of [
  ['llvm_sha', 'b'.repeat(40), 'LLVM_DYLIB_SOURCE_MISMATCH'],
  ['platform', 'linux_x86_64', 'LLVM_DYLIB_PLATFORM_MISMATCH'],
  ['library', 'libLLVM-15.so', 'LLVM_DYLIB_LIBRARY_MISMATCH'],
  ['targets', ['X86'], 'LLVM_DYLIB_TARGETS_MISMATCH'],
]) test(`rejects producer ${field} mismatch`, () => fixture(({manifest, save, check}) => {
  check(); manifest[field] = value; save();
  assert.throws(check, new RegExp(rule), `DARWIN_REJECT_${field}`);
}));
for (const [offset, value, rule] of [[0, 0x464c457f, 'DARWIN_INPUT_MACH_O'],
  [4, 0, 'DARWIN_INPUT_CPU'], [12, 2, 'DARWIN_INPUT_DYLIB']]) {
  test(`rejects actual container mutation ${rule}`, () => fixture(({file, check}) => {
    check(); const fd = fs.openSync(file, 'r+'), bytes = Buffer.alloc(4); bytes.writeUInt32LE(value);
    try { fs.writeSync(fd, bytes, 0, 4, offset); } finally { fs.closeSync(fd); }
    assert.throws(check, new RegExp(rule), `DARWIN_REJECT_${rule}`);
  }));
}
test('rejects mismatching source embedded in producer bytes', () => fixture(({file, check}) => {
  check(); fs.appendFileSync(file, `CJLLVM-COMMIT:${'c'.repeat(40)}\0`);
  assert.throws(check, /LLVM_DYLIB_SOURCE_STAMP_MISMATCH/);
}));
test('rejects truncated Mach-O before CPU inspection', () => fixture(({file}) => {
  fs.truncateSync(file, 12);
  assert.throws(() => verifyDarwinMachO(file, platform), /DARWIN_INPUT_MACH_O/);
}));
