import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {existsSync, readdirSync} from 'node:fs';
import test from 'node:test';
import {installCrossRuntime, writeCrossRuntimeManifest} from './cross-runtime.mjs';

const runtimeRef = '1'.repeat(40);
// Small real cross-compiled ELF inputs exercise the artifact installer only.
// They are not runtime or final-std build acceptance evidence.
async function fixture(t, tuple, triple) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'cross-artifact-'));
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
  const built = spawnSync('clang', [`--target=${triple}`, '-fuse-ld=lld', '-nostdlib', '-shared', source, '-o', output], {encoding: 'utf8'});
  assert.equal(built.status, 0, `fixture compile: ${built.stderr}`);
  await fs.copyFile(output, path.join(shared, 'libboundscheck.so'));
  const object = spawnSync('clang', [`--target=${triple}`, '-c', source, '-o', path.join(lib, 'cjstart.o')], {encoding: 'utf8'});
  assert.equal(object.status, 0, `fixture object: ${object.stderr}`);
  const identity = crypto.createHash('sha256').update(await fs.readFile(output)).digest('hex');
  const format = spawnSync('file', ['-b', output], {encoding: 'utf8'});
  assert.equal(format.status, 0, format.stderr);
  console.log(`FIXTURE_ELF tuple=${tuple} triple=${triple} sha256=${identity} file=${format.stdout.trim()}`);
  return {root, stage, tuple, runtimeRef};
}

for (const [label, tuple, triple] of [
  ['Android', 'linux_android_aarch64_cjnative', 'aarch64-linux-android23'],
  ['OHOS aarch64', 'linux_ohos_aarch64_cjnative', 'aarch64-linux-ohos'],
  ['OHOS x86_64', 'linux_ohos_x86_64_cjnative', 'x86_64-linux-ohos'],
]) {
test(`${label} runtime consumer installs the producer inventory byte for byte`, async t => {
  const args = await fixture(t, tuple, triple);
  const produced = await writeCrossRuntimeManifest(args);
  await installCrossRuntime(args);
  const actual = [];
  for (const file of produced.files) {
    const destination = await fs.readFile(path.join(args.stage, file.path)).catch(() => null);
    actual.push({path: file.path, bytes: destination?.toString('hex') ?? 'MISSING'});
  }
  const expected = await Promise.all(produced.files.map(async file => ({path: file.path,
    bytes: (await fs.readFile(path.join(args.root, file.path))).toString('hex')})));
  console.log(`ASSERT_RUNTIME_INSTALLED_BYTES ${tuple}`);
  assert.deepEqual(actual, expected, `${label} runtime consumer must install every attested byte`);
});

test(`${label} runtime producer records exact file hashes and source identity`, async t => {
  const args = await fixture(t, tuple, triple);
  await writeCrossRuntimeManifest(args);
  const record = JSON.parse(await fs.readFile(path.join(args.root, 'CROSS-RUNTIME.json'), 'utf8'));
  console.log(`ASSERT_RUNTIME_PRODUCER_IDENTITY ${tuple}`);
  assert.equal(record.runtimeRef, runtimeRef);
  assert.deepEqual(record.files.map(file => file.path), [`lib/${tuple}/cjstart.o`,
    `runtime/lib/${tuple}/libboundscheck.so`, `runtime/lib/${tuple}/libcangjie-runtime.so`]);
  const actualHashes = await Promise.all(record.files.map(async file => crypto.createHash('sha256')
    .update(await fs.readFile(path.join(args.root, file.path))).digest('hex')));
  assert.deepEqual(record.files.map(file => file.sha256), actualHashes);
});

test(`${label} runtime consumer rejects changed bytes and mismatched source identity`, async t => {
  const args = await fixture(t, tuple, triple);
  await writeCrossRuntimeManifest(args);
  await assert.rejects(installCrossRuntime({...args, runtimeRef: '2'.repeat(40)}), /identity mismatch/);
  await fs.appendFile(path.join(args.root, 'lib', tuple, 'cjstart.o'), 'changed');
  await assert.rejects(installCrossRuntime(args), /inventory\/hash mismatch/);
});

test(`${label} producer rejects the opposite ELF machine`, async t => {
  const args = await fixture(t, tuple, triple.startsWith('aarch64') ? 'x86_64-linux-ohos' : 'aarch64-linux-ohos');
  console.log(`ASSERT_CROSS_MACHINE_REJECT ${tuple}`);
  await assert.rejects(writeCrossRuntimeManifest(args), /not an ELF64 for/);
});
}

// Mach-O fixtures come from clang and lld's ld64 flavour, which distributions
// ship as ld64.lld beside a versioned LLVM rather than on PATH.
function ld64Directory() {
  const versioned = existsSync('/usr/lib') ? readdirSync('/usr/lib').filter(name => /^llvm-\d+$/.test(name))
    .sort((a, b) => Number(b.slice(5)) - Number(a.slice(5))).map(name => path.join('/usr/lib', name, 'bin')) : [];
  const directory = [...(process.env.PATH || '').split(path.delimiter), ...versioned]
    .find(entry => entry && existsSync(path.join(entry, 'ld64.lld')));
  assert.ok(directory, 'ld64.lld is required to link the Mach-O fixtures');
  return directory;
}
function clangMachO(triple, args) {
  const env = {...process.env, PATH: [ld64Directory(), process.env.PATH || ''].join(path.delimiter)};
  const built = spawnSync('clang', [`--target=${triple}`, ...args], {encoding: 'utf8', env});
  assert.equal(built.status, 0, `Mach-O fixture ${triple}: ${built.stderr}`);
}
async function iosFixture(t, tuple, triple, {installDirectory = '@rpath'} = {}) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'cross-macho-'));
  t.after(() => fs.rm(directory, {recursive: true, force: true}));
  const root = path.join(directory, 'input');
  const stage = path.join(directory, 'sdk');
  const shared = path.join(root, 'runtime', 'lib', tuple);
  const lib = path.join(root, 'lib', tuple);
  await fs.mkdir(shared, {recursive: true});
  await fs.mkdir(lib, {recursive: true});
  const source = path.join(directory, 'fixture.c');
  await fs.writeFile(source, 'int artifact_fixture(void) { return 479; }\n');
  for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
    clangMachO(triple, ['-fuse-ld=lld', '-nostdlib', '-shared', `-Wl,-install_name,${installDirectory}/${name}`,
      source, '-o', path.join(shared, name)]);
  }
  clangMachO(triple, ['-c', source, '-o', path.join(lib, 'cjstart.o')]);
  const format = spawnSync('file', ['-b', path.join(shared, 'libcangjie-runtime.dylib')], {encoding: 'utf8'});
  console.log(`FIXTURE_MACHO tuple=${tuple} triple=${triple} file=${format.stdout.trim()}`);
  return {root, stage, tuple, runtimeRef};
}

for (const [label, tuple, triples, macos, otherPlatform] of [
  // ios11 links LC_VERSION_MIN_IPHONEOS, the encoding the runtime's device and
  // x86_64 simulator builds carry; ios14 links LC_BUILD_VERSION.
  ['iOS device', 'ios_aarch64_cjnative', ['arm64-apple-ios11', 'arm64-apple-ios14'],
    'arm64-apple-macos12', ['arm64-apple-ios14-simulator', /targets iossimulator, not ios for/]],
  ['iOS simulator aarch64', 'ios_simulator_aarch64_cjnative', ['arm64-apple-ios14-simulator'],
    'arm64-apple-macos12', ['arm64-apple-ios11', /targets ios, not iossimulator for/]],
  ['iOS simulator x86_64', 'ios_simulator_x86_64_cjnative', ['x86_64-apple-ios11-simulator', 'x86_64-apple-ios14-simulator'],
    'x86_64-apple-macos12', ['arm64-apple-ios14-simulator', /is not a ios_simulator_x86_64_cjnative Mach-O dylib/]],
]) {
for (const triple of triples) {
test(`${label} runtime consumer installs ${triple} dylibs byte for byte`, async t => {
  const args = await iosFixture(t, tuple, triple);
  const produced = await writeCrossRuntimeManifest(args);
  await installCrossRuntime(args);
  const actual = await Promise.all(produced.files.map(async file => ({path: file.path,
    bytes: (await fs.readFile(path.join(args.stage, file.path)).catch(() => null))?.toString('hex') ?? 'MISSING'})));
  const expected = await Promise.all(produced.files.map(async file => ({path: file.path,
    bytes: (await fs.readFile(path.join(args.root, file.path))).toString('hex')})));
  console.log(`ASSERT_IOS_RUNTIME_INSTALLED_BYTES ${tuple} ${triple}`);
  assert.deepEqual(actual, expected);
});
}

test(`${label} producer rejects a macOS dylib with the same CPU`, async t => {
  const args = await iosFixture(t, tuple, macos);
  console.log(`ASSERT_IOS_REJECTS_MACOS ${tuple} ${macos}`);
  await assert.rejects(writeCrossRuntimeManifest(args), /targets macos, not ios(simulator)? for/);
});

test(`${label} producer rejects the other iOS deployment target`, async t => {
  const [triple, expected] = otherPlatform;
  const args = await iosFixture(t, tuple, triple);
  console.log(`ASSERT_IOS_REJECTS_OTHER_PLATFORM ${tuple} ${triple}`);
  await assert.rejects(writeCrossRuntimeManifest(args), expected);
});

test(`${label} producer rejects a build-host install name`, async t => {
  const args = await iosFixture(t, tuple, triples.at(-1), {installDirectory: '/Users/runner/work/runtime/lib'});
  console.log(`ASSERT_IOS_REJECTS_ABSOLUTE_INSTALL_NAME ${tuple}`);
  await assert.rejects(writeCrossRuntimeManifest(args), /install name \/Users\/runner\/work\/runtime\/lib\/lib\S+\.dylib is not @rpath\//);
});
}
