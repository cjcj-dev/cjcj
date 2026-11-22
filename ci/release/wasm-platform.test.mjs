import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {CROSS_STD_BUILDS, getReleasePlatform, getTarget, releasePlatformReadiness, RELEASE_REQUIREMENTS} from '../../build/lib/targets.mjs';
import {crossStdArguments} from './cross-std-arguments.mjs';
import {assertWasmArchive, verifyCrossRuntime, writeCrossRuntimeManifest} from './cross-runtime.mjs';
import {probeRequirement} from './platform-matrix.mjs';
import {archiveName, importsOf, packageGraph, wasmImports} from '../wasm-std-full.mjs';

const tuple = 'wasi_wasm32_cjnative';
const keys = ['linux-x64-wasm', 'darwin-arm64-wasm', 'win32-x64-wasm'];
const root = path.resolve(import.meta.dirname, '..', '..');

test('the wasm cross row names the wasm32-unknown-wasi tuple and its final std artifact', () => {
  const rows = CROSS_STD_BUILDS.filter(row => row.family === 'wasm');
  assert.deepEqual(rows.map(row => [row.tuple, row.triple, row.target, row.artifact]),
    [[tuple, 'wasm32-unknown-wasi', 'linux-x64', 'final-std-wasm32-wasi']]);
});

for (const key of keys) test(`${key} mirrors its -android host package with only the wasm cross tuple`, () => {
  const platform = getReleasePlatform(key);
  const android = getReleasePlatform(key.replace(/-wasm$/, '-android'));
  assert.equal(platform.host, android.host);
  assert.equal(platform.runner, android.runner);
  assert.deepEqual(platform.crossTuples, [tuple]);
  assert.deepEqual(platform.requires, ['wasi-sysroot']);
  const result = releasePlatformReadiness(key);
  const androidResult = releasePlatformReadiness(android.key);
  console.log(`ASSERT_WASM_READINESS ${key} ${JSON.stringify(result)}`);
  assert.equal(result.crossStd[tuple], 'linux-x64');
  assert.equal(result.packageDeclared, true);
  assert.ok(!result.reasons.some(reason => reason.startsWith(`tuple ${tuple}:`)), 'the wasm producer removes the missing-tuple reason');
  assert.ok(!result.reasons.some(reason => reason.startsWith('requires wasi-sysroot:')), 'the DAG installs and probes wasi-sysroot');
  // Exactly the host-side gaps the Android package of the same host already has.
  assert.deepEqual(result.reasons, androidResult.reasons);
  assert.equal(result.status, androidResult.status);
  if (result.status === 'buildable') assert.equal(getTarget(result.host).spec.crossCompile, false);
});

test('wasi-sysroot probe reads CJCJ_WASI_SYSROOT and requires the wasi libc', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wasi-sysroot-'));
  try {
    assert.equal(probeRequirement('wasi-sysroot', {CJCJ_WASI_SYSROOT: dir}).present, false);
    fs.mkdirSync(path.join(dir, 'lib', 'wasm32-wasi'), {recursive: true});
    fs.writeFileSync(path.join(dir, 'lib', 'wasm32-wasi', 'libc.a'), '!<arch>\n');
    assert.deepEqual(probeRequirement('wasi-sysroot', {CJCJ_WASI_SYSROOT: dir}), {present: true, detail: `CJCJ_WASI_SYSROOT=${dir}`});
    assert.equal(RELEASE_REQUIREMENTS['wasi-sysroot'].marker, 'lib/wasm32-wasi/libc.a');
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('wasm matrix CLI turns on build_wasm and hands final-std-wasm32-wasi plus its cross runtime to packaging', () => {
  const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', 'linux-x64-wasm'], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  const plan = JSON.parse(run.stdout);
  assert.deepEqual(plan.source, [{target: 'linux-x64', build_wasm: true}]);
  const entries = JSON.parse(plan.package[0].cross_std_artifacts);
  assert.deepEqual(entries, [{tuple, artifact: 'final-std-wasm32-wasi'}]);
  assert.deepEqual(crossStdArguments(JSON.stringify(entries), '/artifacts'), ['--cross-std-dir', `${tuple}=/artifacts/final-std-wasm32-wasi`,
    '--cross-runtime-dir', `${tuple}=/artifacts/final-std-wasm32-wasi/cross-runtime`]);
});

function arMember(name, body) {
  const header = Buffer.alloc(60, ' ');
  header.write(`${name}/`, 0, 'latin1');
  header.write(String(body.length), 48, 'latin1');
  header.write('`\n', 58, 'latin1');
  return Buffer.concat([header, body, body.length & 1 ? Buffer.from('\n') : Buffer.alloc(0)]);
}
const wasmObject = Buffer.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
const elfObject = Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0]);

test('cross runtime accepts wasm32 archives and rejects host objects (red control)', async () => {
  const good = Buffer.concat([Buffer.from('!<arch>\n'), arMember('a.o', wasmObject)]);
  assert.equal(assertWasmArchive(good, 'good.a'), 1);
  assert.throws(() => assertWasmArchive(Buffer.concat([Buffer.from('!<arch>\n'), arMember('a.o', elfObject)]), 'elf.a'), /not a wasm32 object/);
  assert.throws(() => assertWasmArchive(Buffer.from('\x7fELF'), 'x'), /not an ar archive/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-cross-runtime-'));
  try {
    for (const sub of [`lib/${tuple}`, `runtime/lib/${tuple}`]) fs.mkdirSync(path.join(dir, sub), {recursive: true});
    fs.writeFileSync(path.join(dir, 'runtime', 'lib', tuple, 'libcangjie-runtime.a'), good);
    fs.writeFileSync(path.join(dir, 'lib', tuple, 'libcangjie-std-core.a'), good);
    const ref = 'a'.repeat(40);
    await writeCrossRuntimeManifest({root: dir, tuple, runtimeRef: ref});
    assert.equal((await verifyCrossRuntime({root: dir, tuple, runtimeRef: ref})).tuple, tuple);
    fs.writeFileSync(path.join(dir, 'runtime', 'lib', tuple, 'libcangjie-runtime.a'), Buffer.concat([Buffer.from('!<arch>\n'), arMember('a.o', elfObject)]));
    await assert.rejects(verifyCrossRuntime({root: dir, tuple, runtimeRef: ref}), /hash mismatch|not a wasm32 object/);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('full std graph: every std package is ordered after its std imports, macros stay host-only', () => {
  const stdRoot = process.env.CJCJ_TEST_STDLIB_STD;
  assert.deepEqual([...importsOf('import std.{collection.*, io.InputStream}\npublic import std.math.numeric.BigInt\n')].sort(),
    ['std.collection.*', 'std.io.InputStream', 'std.math.numeric.BigInt']);
  assert.equal(archiveName('std.math.numeric'), 'libcangjie-std-math.numeric.a');
  if (!stdRoot) return;
  const {pkgs, order} = packageGraph(stdRoot);
  assert.equal(order[0], 'std.core');
  for (const name of order) for (const dep of pkgs.get(name).deps) assert.ok(order.indexOf(dep) < order.indexOf(name), `${dep} before ${name}`);
});

test('wasm import reader lists module/field pairs of a linked module', () => {
  // (module (import "wasi_snapshot_preview1" "fd_write" (func (param i32 i32 i32 i32) (result i32))))
  const name = s => [s.length, ...Buffer.from(s)];
  const type = [0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 1, 0x7f];
  const imp = [1, ...name('wasi_snapshot_preview1'), ...name('fd_write'), 0, 0];
  const bytes = Uint8Array.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 1, type.length + 1, 1, ...type, 2, imp.length, ...imp]);
  assert.deepEqual(wasmImports(bytes), [{module: 'wasi_snapshot_preview1', field: 'fd_write', kind: 0}]);
});

test('source-wasm job runs the formal producer and uploads final-std-wasm32-wasi', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const job = workflow.slice(workflow.indexOf('\n  source-wasm:\n'), workflow.indexOf('\n  source-ohos:\n'));
  assert.match(job, /if: contains\(needs\.plan\.outputs\.llvm_platforms, 'linux_x86_64'\) && inputs\.build_wasm/);
  assert.match(job, /requirement: wasi-sysroot/);
  assert.match(job, /run: node ci\/srcbuild\/steps\/build-wasm-final-std\.mjs/);
  assert.match(job, /name: final-std-wasm32-wasi/);
  for (const file of ['srcbuild.yml', 'release-matrix.yml']) {
    assert.match(fs.readFileSync(path.join(root, '.github/workflows', file), 'utf8'), /build_wasm/);
  }
});
