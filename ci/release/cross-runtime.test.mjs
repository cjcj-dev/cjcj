import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {installCrossRuntime, writeCrossRuntimeManifest} from './cross-runtime.mjs';

const tuple = 'linux_android_aarch64_cjnative';
const runtimeRef = '1'.repeat(40);
// Small real cross-compiled ELF inputs exercise the artifact installer only.
// They are not runtime or final-std build acceptance evidence.
async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'android-artifact-'));
  t.after(() => fs.rm(directory, {recursive: true, force: true}));
  const root = path.join(directory, 'input');
  const stage = path.join(directory, 'sdk');
  const shared = path.join(root, 'runtime', 'lib', tuple);
  const lib = path.join(root, 'lib', tuple);
  await fs.mkdir(shared, {recursive: true});
  await fs.mkdir(lib, {recursive: true});
  const source = path.join(directory, 'fixture.c');
  await fs.writeFile(source, 'int artifact_fixture(void) { return 479; }\n');
  const output = path.join(shared, 'libcangjie-runtime.so');
  const built = spawnSync('clang', ['--target=aarch64-linux-android23', '-fuse-ld=lld', '-nostdlib', '-shared', source, '-o', output], {encoding: 'utf8'});
  assert.equal(built.status, 0, `fixture compile: ${built.stderr}`);
  await fs.copyFile(output, path.join(shared, 'libboundscheck.so'));
  const object = spawnSync('clang', ['--target=aarch64-linux-android23', '-c', source, '-o', path.join(lib, 'cjstart.o')], {encoding: 'utf8'});
  assert.equal(object.status, 0, `fixture object: ${object.stderr}`);
  return {root, stage, tuple, runtimeRef};
}

test('Android runtime consumer installs the producer inventory byte for byte', async t => {
  const args = await fixture(t);
  const produced = await writeCrossRuntimeManifest(args);
  await installCrossRuntime(args);
  const actual = [];
  for (const file of produced.files) {
    const destination = await fs.readFile(path.join(args.stage, file.path)).catch(() => null);
    actual.push({path: file.path, bytes: destination?.toString('hex') ?? 'MISSING'});
  }
  const expected = await Promise.all(produced.files.map(async file => ({path: file.path,
    bytes: (await fs.readFile(path.join(args.root, file.path))).toString('hex')})));
  console.log('ASSERT_ANDROID_RUNTIME_INSTALLED_BYTES');
  assert.deepEqual(actual, expected, 'Android runtime consumer must install every attested byte');
});

test('Android runtime producer records exact file hashes and source identity', async t => {
  const args = await fixture(t);
  await writeCrossRuntimeManifest(args);
  const record = JSON.parse(await fs.readFile(path.join(args.root, 'CROSS-RUNTIME.json'), 'utf8'));
  console.log('ASSERT_ANDROID_RUNTIME_PRODUCER_IDENTITY');
  assert.equal(record.runtimeRef, runtimeRef);
  assert.deepEqual(record.files.map(file => file.path), [`lib/${tuple}/cjstart.o`,
    `runtime/lib/${tuple}/libboundscheck.so`, `runtime/lib/${tuple}/libcangjie-runtime.so`]);
  assert.ok(record.files.every(file => /^[0-9a-f]{64}$/.test(file.sha256)));
});

test('Android runtime consumer rejects changed bytes and mismatched source identity', async t => {
  const args = await fixture(t);
  await writeCrossRuntimeManifest(args);
  await assert.rejects(installCrossRuntime({...args, runtimeRef: '2'.repeat(40)}), /identity mismatch/);
  await fs.appendFile(path.join(args.root, 'lib', tuple, 'cjstart.o'), 'changed');
  await assert.rejects(installCrossRuntime(args), /inventory\/hash mismatch/);
});
