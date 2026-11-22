#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {LLVM_ENTRY_BIN, NATIVE_LLVM_BIN, manifestDrift, overlayWasmSdk, wasmLdEntry} from './wasm-sdk-overlay.mjs';
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
  const sha = text => createHash('sha256').update(text).digest('hex');
  // release manifest pins the native compiler; a TOOLS-INPUTS entry that is already stale in the base must not be blamed on the overlay
  write(path.join(base, 'RELEASE-MANIFEST.jsonl'), JSON.stringify({component: 'compiler', artifacts: [
    {path: 'libexec/compiler/cjcj-stage1', sha256: sha('native cjc')}, {path: `${LLVM_ENTRY_BIN}/llvm-ar`, sha256: sha('launcher')}]}) + '\n');
  write(path.join(base, 'TOOLS-INPUTS.json'), JSON.stringify({files: {'tools/bin/node': {sha256: sha('stale')}}}));
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
  assert.equal(provenance.releaseVerifiable, false);
  assert.equal(provenance.inputs.std.mode, 'prebuilt');
  assert.deepEqual(provenance.supersededManifestEntries, {'RELEASE-MANIFEST.jsonl': ['libexec/compiler/cjcj-stage1']});
  assert.deepEqual(manifestDrift(base), {'TOOLS-INPUTS.json': ['tools/bin/node']}, 'pre-existing base drift is reported, not attributed');
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

test('both CLI modes reject unsafe SDK copy paths before touching the base or destination', t => {
  const {dir, base, args} = fixture();
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const cli = fileURLToPath(new URL('./wasm-sdk-overlay.mjs', import.meta.url));
  const alias = path.join(dir, 'base-alias');
  fs.symlinkSync(base, alias, 'dir');
  const dangling = path.join(dir, 'dangling-dest');
  fs.symlinkSync(path.join(dir, 'absent'), dangling, 'dir');
  const compiler = path.join(base, 'libexec/compiler/cjcj-stage1');
  const oldArchive = path.join(base, 'lib/wasi_wasm32_cjnative/libcangjie-std-core.a');
  write(oldArchive, 'inherited archive');
  const oldModule = path.join(base, 'modules/wasi_wasm32_cjnative/std/std.core.cjo');
  write(oldModule, 'inherited module');
  const copied = path.join(dir, 'cp-called');
  const cp = path.join(dir, 'test-bin/cp');
  write(cp, `#!${process.execPath}
require('node:fs').writeFileSync(${JSON.stringify(copied)}, 'unexpected copy');
process.exit(1);
`, 0o755);

  const modes = [
    ['source', ['--stdlib-source', dir, '--boundscheck-source', dir, '--clang', args.cjc, '--llvm-ar', args.cjc]],
    ['prebuilt', ['--std-archive', args.stdArchives[0], '--std-module', args.stdModules[0]]],
  ];
  function rejects(input, dest, message) {
    for (const [mode, flags] of modes) {
      const result = spawnSync(process.execPath, [cli, '--base-sdk', input, '--dest', dest, '--llvm-bin', args.llvmBin,
        '--cjc', args.cjc, '--runtime-archive', args.runtimeArchive, '--sysroot-tarball', args.sysrootTarball, ...flags],
      {encoding: 'utf8', env: {...process.env, PATH: path.dirname(cp) + path.delimiter + process.env.PATH}});
      assert.ifError(result.error);
      assert.equal(result.status, 2, `${mode}: ${result.stderr}`);
      assert.match(result.stderr, message, mode);
      assert.equal(result.stdout, '', mode);
      assert.equal(fs.existsSync(copied), false, mode);
      assert.equal(fs.readFileSync(compiler, 'utf8'), 'native cjc', mode);
      assert.equal(fs.readFileSync(oldArchive, 'utf8'), 'inherited archive', mode);
      assert.equal(fs.readFileSync(oldModule, 'utf8'), 'inherited module', mode);
    }
  }

  rejects(alias, args.dest, /base SDK must be a directory, not a symbolic link/);
  rejects(alias + path.sep, args.dest, /base SDK must be a directory, not a symbolic link/);
  assert.equal(fs.readlinkSync(alias), base);
  rejects(base, path.join(alias, 'must-not-create/sdk'), /dest must be outside the base SDK/);
  assert.equal(fs.existsSync(path.join(base, 'must-not-create')), false);
  rejects(base, dangling, /dest must be a new path/);
  assert.equal(fs.readlinkSync(dangling), path.join(dir, 'absent'));

  const runtime = path.join(base, 'runtime');
  fs.symlinkSync(path.dirname(oldArchive), runtime, 'dir');
  rejects(base, args.dest, /base SDK write path must be a directory, not a symbolic link: .*runtime/);
  assert.equal(fs.readlinkSync(runtime), path.dirname(oldArchive));
  fs.unlinkSync(runtime);

  const inheritedEntry = path.join(base, LLVM_ENTRY_BIN, 'wasm-ld.entry');
  fs.symlinkSync(oldModule, inheritedEntry);
  rejects(base, args.dest, /base SDK write path must be a regular file, not a symbolic link: .*wasm-ld\.entry/);
  assert.equal(fs.readlinkSync(inheritedEntry), oldModule);
  assert.equal(fs.existsSync(path.dirname(args.dest)), false);
});

test('a sysroot tarball that does not match the pin fails before any output exists', () => {
  const {args} = fixture();
  const pin = parseWasiPin(Object.entries({...args.pin, WASI_SYSROOT_SHA256: 'b'.repeat(64)}).map(([k, v]) => `${k}=${v}`).join('\n'));
  assert.throws(() => overlayWasmSdk({...args, pin}), /sha256 mismatch/);
  assert.equal(fs.existsSync(args.dest), false);
});

test('source mode installs the std pair produced by the staged SDK', t => {
  const {dir, base, args} = fixture();
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const stdLib = 'lib/wasi_wasm32_cjnative/libcangjie-std-core.a';
  const stdMod = 'modules/wasi_wasm32_cjnative/std/std.core.cjo';
  write(path.join(base, stdLib), 'old archive');
  write(path.join(base, stdMod), 'old module');
  write(path.join(base, path.dirname(stdMod), 'std.stale.cjo'), 'stale module');

  const executable = (file, body) => write(file, `#!${process.execPath}
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
${body}
`, 0o755);
  executable(path.join(base, 'bin/cjc'), `
const sdk = process.env.CANGJIE_HOME;
assert(args.includes('--no-prelude'));
assert.equal(fs.readFileSync(path.join(sdk, 'libexec/compiler/cjcj-stage1'), 'utf8'), 'wasm cjc');
assert.equal(fs.readFileSync(path.join(sdk, '${NATIVE_LLVM_BIN}/opt'), 'utf8'), 'wasm opt');
assert.equal(fs.readFileSync(path.join(sdk, 'runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a'), 'utf8'), 'rt');
assert(fs.statSync(path.dirname(path.join(sdk, '${stdMod}'))).isDirectory());
assert(!fs.existsSync(path.join(sdk, '${stdMod}')));
assert(!fs.existsSync(path.join(sdk, '${stdLib}')));
const out = args.find(arg => arg.startsWith('--output=')).slice('--output='.length);
fs.writeFileSync(out, 'fresh core');
fs.writeFileSync(out + '.cjo', 'fresh module');
`);
  const stdlibSource = path.join(dir, 'stdlib with spaces');
  const native = path.join(stdlibSource, 'libs/std/core/native');
  write(path.join(native, 'CMakeLists.txt'), '--redefine-sym \${SYM_PREFIX}Int64_ti=\${SYM_PREFIX}Int64.ti');
  write(path.join(native, 'typetemplate.c'), 'template source');
  write(path.join(native, 'ffi.c'), 'ffi source');
  write(path.join(native, 'SIMD_support.c'), 'SIMD source');
  const boundscheckSource = path.join(dir, 'bounds');
  write(path.join(boundscheckSource, 'src/memcpy_s.c'), 'bounds source');
  fs.mkdirSync(path.join(boundscheckSource, 'include'));
  const clang = path.join(dir, 'clang');
  executable(clang, `
const src = args.at(-3);
const out = args.at(-1);
if (src.endsWith('typetemplate.c')) fs.writeFileSync(out, '@Int64_ti = global i32 0');
else fs.copyFileSync(src, out);
`);
  const llvmAr = path.join(dir, 'llvm-ar');
  executable(llvmAr, `
const [op, archive, ...objects] = args;
assert.equal(op, 'rs');
for (const object of objects) fs.appendFileSync(archive, '|'+fs.readFileSync(object, 'utf8'));
`);
  const source = {stdlibSource, boundscheckSource, clang, llvmAr};
  assert.throws(() => overlayWasmSdk({...args, ...source}), /either source std production or prebuilt/);
  assert.throws(() => overlayWasmSdk({...args, stdModules: []}), /requires both/);
  assert.equal(fs.existsSync(args.dest), false);

  const result = overlayWasmSdk({...args, ...source, stdArchives: [], stdModules: []});
  assert.equal(result.check.ok, true);
  assert.equal(fs.readFileSync(path.join(args.dest, stdLib), 'utf8'),
    'fresh core|bounds source|ffi source|SIMD source|@"Int64.ti" = global i32 0', 'SDK must install the archive produced in this run');
  assert.equal(fs.readFileSync(path.join(args.dest, stdMod), 'utf8'), 'fresh module');
  assert.equal(result.provenance.inputs.std.mode, 'source');
  assert.equal(fs.existsSync(path.join(args.dest, path.dirname(stdMod), 'std.stale.cjo')), false);
  assert.equal(fs.readFileSync(path.join(base, stdLib), 'utf8'), 'old archive');

  const cli = fileURLToPath(new URL('./wasm-sdk-overlay.mjs', import.meta.url));
  const rejected = spawnSync(process.execPath, [cli, '--std-archive', '--std-module', args.stdModules[0]], {encoding: 'utf8'});
  assert.equal(rejected.status, 2);
  assert.match(rejected.stderr, /missing value for --std-archive/);
});
