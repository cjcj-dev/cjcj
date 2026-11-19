import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {LLVM_ENTRY_BIN, NATIVE_LLVM_BIN, overlayWasmSdk, wasmLdEntry} from './wasm-sdk-overlay.mjs';
import {parseWasiPin} from './wasi-toolchain.mjs';

const LLC_ENTRY = ['cjcj-sdk-entry-v1', '3', `${NATIVE_LLVM_BIN}/llc`, 'linux', 'native-target:x64', 'third_party/llvm/lib', ''].join('\n');

function write(file, text, mode = 0o644) { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text, {mode}); }

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-overlay-'));
  const base = path.join(dir, 'base');
  for (const tool of ['llc', 'opt', 'llvm-objcopy', 'lld']) write(path.join(base, NATIVE_LLVM_BIN, tool), `native ${tool}`, 0o755);
  write(path.join(base, LLVM_ENTRY_BIN, 'llc'), 'launcher', 0o755);
  write(path.join(base, LLVM_ENTRY_BIN, 'llc.entry'), LLC_ENTRY);
  for (const tool of ['llvm-ar', 'llvm-objcopy']) write(path.join(base, LLVM_ENTRY_BIN, tool), 'launcher', 0o755);
  write(path.join(base, 'libexec/compiler/cjcj-stage1'), 'native cjc', 0o755);
  write(path.join(base, '.target-tools/tools/bin/cjpm'), 'native cjpm', 0o755);
  write(path.join(base, 'tools/bin/node'), '#!/bin/sh\necho v22.23.3\n', 0o755);
  const inputs = path.join(dir, 'inputs');
  for (const tool of ['llc', 'opt', 'llvm-objcopy', 'lld']) write(path.join(inputs, 'llvm', tool), `wasm ${tool}`, 0o755);
  write(path.join(inputs, 'cjc'), 'wasm cjc', 0o755);
  write(path.join(inputs, 'cjpm'), 'lane3 cjpm', 0o755);
  write(path.join(inputs, 'libcangjie-runtime.a'), 'rt');
  write(path.join(inputs, 'libcangjie-std-core.a'), 'core');
  write(path.join(inputs, 'std.core.cjo'), 'cjo');
  const src = path.join(dir, 'sysroot-src');
  for (const name of ['libc.a', 'crt1-command.o']) write(path.join(src, 'wasi-sysroot/lib/wasm32-wasi', name), name);
  const tarball = path.join(inputs, 'wasi-sysroot.tar.gz');
  assert.equal(spawnSync('tar', ['-czf', tarball, '-C', src, 'wasi-sysroot']).status, 0);
  const pin = parseWasiPin(['WASI_SYSROOT_URL=https://example.invalid/s.tar.gz',
    `WASI_SYSROOT_SHA256=${createHash('sha256').update(fs.readFileSync(tarball)).digest('hex')}`,
    'WASI_SYSROOT_VERSION=17.0', 'WASI_SYSROOT_LLVM_MAJOR=15', 'WASI_NODE_MIN_MAJOR=20'].join('\n'));
  const args = {baseSdk: base, dest: path.join(dir, 'out/sdk'), llvmBin: path.join(inputs, 'llvm'), cjc: path.join(inputs, 'cjc'),
    runtimeArchive: path.join(inputs, 'libcangjie-runtime.a'), stdArchives: [path.join(inputs, 'libcangjie-std-core.a')],
    stdModules: [path.join(inputs, 'std.core.cjo')], sysrootTarball: tarball, cjpm: path.join(inputs, 'cjpm'), pin};
  return {dir, base, args};
}

test('the wasm-ld entry is the llc entry with only the target line changed', () => {
  const entry = wasmLdEntry(LLC_ENTRY);
  const diff = LLC_ENTRY.split('\n').map((line, i) => [line, entry.split('\n')[i]]).filter(([a, b]) => a !== b);
  assert.deepEqual(diff, [[`${NATIVE_LLVM_BIN}/llc`, `${NATIVE_LLVM_BIN}/wasm-ld`]]);
  assert.throws(() => wasmLdEntry('not an entry\n'), /unexpected llc SDK entry/);
});

test('overlay produces a layout that passes the wasm SDK check and records provenance', () => {
  const {base, args} = fixture();
  const result = overlayWasmSdk(args);
  assert.deepEqual([result.check.ok, result.check.missing, result.check.problems], [true, [], []]);
  const dest = args.dest;
  assert.equal(fs.readFileSync(path.join(dest, NATIVE_LLVM_BIN, 'wasm-ld'), 'utf8'), 'wasm lld');
  assert.equal(fs.readFileSync(path.join(dest, NATIVE_LLVM_BIN, 'lld'), 'utf8'), 'native lld');
  assert.equal(fs.readFileSync(path.join(dest, LLVM_ENTRY_BIN, 'wasm-ld'), 'utf8'), 'launcher');
  assert.equal(fs.readFileSync(path.join(dest, 'libexec/compiler/cjcj-stage1'), 'utf8'), 'wasm cjc');
  assert.equal(fs.readFileSync(path.join(dest, '.target-tools/tools/bin/cjpm'), 'utf8'), 'lane3 cjpm');
  assert.equal(fs.readFileSync(path.join(base, 'libexec/compiler/cjcj-stage1'), 'utf8'), 'native cjc', 'the base SDK is not modified');
  const provenance = JSON.parse(fs.readFileSync(path.join(dest, 'WASM-SDK-OVERLAY.json'), 'utf8'));
  assert.equal(provenance.target, 'wasm32-unknown-wasi');
  assert.match(provenance.outputs['libexec/compiler/cjcj-stage1'], /^[0-9a-f]{64}$/);
  assert.equal(provenance.inputs.sysrootTarball.sha256, args.pin.WASI_SYSROOT_SHA256);
});

test('a missing input fails before any output exists', () => {
  for (const drop of ['lld', 'cjc', 'runtimeArchive', 'sysrootTarball']) {
    const {args} = fixture();
    const target = drop === 'lld' ? path.join(args.llvmBin, 'lld') : args[drop];
    fs.rmSync(target);
    assert.throws(() => overlayWasmSdk(args), /is missing/, drop);
    assert.equal(fs.existsSync(args.dest), false, drop);
  }
  const {args} = fixture();
  fs.mkdirSync(args.dest, {recursive: true});
  assert.throws(() => overlayWasmSdk(args), /dest must be a new path/);
});

test('a sysroot tarball that does not match the pin fails before any output exists', () => {
  const {args} = fixture();
  const pin = parseWasiPin(Object.entries({...args.pin, WASI_SYSROOT_SHA256: 'b'.repeat(64)}).map(([k, v]) => `${k}=${v}`).join('\n'));
  assert.throws(() => overlayWasmSdk({...args, pin}), /sha256 mismatch/);
  assert.equal(fs.existsSync(args.dest), false);
});
