import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {load as yaml} from '../../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {allReleasePlatforms, getReleasePlatform, releasePlatformReadiness, sourceBuildCells} from '../../../../lib/targets.mjs';
import {crossStdArguments} from '../../release/cross-std-arguments.mjs';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

const root = path.resolve(import.meta.dirname, '../../../../..');
const workflow = async name => yaml(await fs.readFile(path.join(root, '.github/workflows', name), 'utf8'));
const invoke = (script, args, env = {}) => spawnSync(process.execPath, [path.join(root, script), ...args],
  {encoding: 'utf8', env: {...process.env, ...env}});
const releaseKeys = allReleasePlatforms().filter(key => {
  const p = getReleasePlatform(key);
  return !p.excluded && !p.crossCompiledHost && p.requires.some(req => ['ohos-sdk', 'xcode-ios'].includes(req));
});
const substitute = (text, row) => text.replace(/\$\{\{ matrix\.([a-z_]+) \}\}/g, (_, key) => row[key]);

for (const key of releaseKeys) {
}

test('Android and Windows independent controls retain their producer and consumer branches', async () => {
  const run = invoke('build/sdk/producers/release/platform-matrix.mjs', ['plan', '--platforms', 'linux-x64-android,win32-x64']);
  assert.equal(run.status, 0, run.stderr);
  const plan = JSON.parse(run.stdout);
  assert.equal(plan.source.find(row => row.target === 'linux-x64').build_android, true);
  assert.ok(plan.source.every(row => !row.build_ios && !row.build_ohos));
  const jobs = (await workflow('sdk-build-target.yml')).jobs;
  assert.deepEqual(jobs['source-windows'].needs, ['plan', 'source-stage3', 'source-mingw']);
  assert.deepEqual(jobs['source-android'].needs, ['plan', 'source-stage3']);
  console.log('CROSS_INDEPENDENT_CONTROL Android/Windows retained');
});

// Binary-format fixtures qualify the shared manifest/installer only. They are
// deliberately not described as built iOS runtime or final std artifacts.
// mach_header_64 (MH_DYLIB), then LC_ID_DYLIB @rpath/<name> and LC_BUILD_VERSION
// naming the deployment platform (PLATFORM_IOS 2, PLATFORM_IOSSIMULATOR 7).
function machoDylibFixture(cpu, platform, name) {
  const install = Buffer.from(`@rpath/${name}\0`);
  const id = Buffer.alloc(Math.ceil((24 + install.length) / 8) * 8);
  id.writeUInt32LE(0xd, 0); id.writeUInt32LE(id.length, 4); id.writeUInt32LE(24, 8); install.copy(id, 24);
  const build = Buffer.alloc(24); build.writeUInt32LE(0x32, 0); build.writeUInt32LE(24, 4); build.writeUInt32LE(platform, 8);
  const header = Buffer.alloc(32); header.writeUInt32LE(0xfeedfacf, 0); header.writeUInt32LE(cpu, 4); header.writeUInt32LE(6, 12);
  header.writeUInt32LE(2, 16); header.writeUInt32LE(id.length + build.length, 20);
  return Buffer.concat([header, id, build]);
}
for (const [tuple, cpu, platform] of [['ios_aarch64_cjnative', 0x0100000c, 2],
  ['ios_simulator_aarch64_cjnative', 0x0100000c, 7], ['ios_simulator_x86_64_cjnative', 0x01000007, 7]]) {
  test(`${tuple}: installer preserves declared binary bytes and rejects changed transport`, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'ios-artifact-'));
    t.after(() => fs.rm(dir, {recursive: true, force: true}));
    const workspace = path.join(dir, 'workspace');
    const runtimeWorkspace = path.join(workspace, '.srcbuild/workspace');
    const source = path.join(runtimeWorkspace, 'cangjie_runtime');
    const input = path.join(source, 'runtime-install'), stage = path.join(source, 'installed-sdk');
    const files = new Map([[`lib/${tuple}/cjstart.o`, Buffer.from('fixture-start-object')]]);
    for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
      files.set(`runtime/lib/${tuple}/${name}`, machoDylibFixture(cpu, platform, name));
    }
    for (const [file, bytes] of files) {
      await fs.mkdir(path.dirname(path.join(input, file)), {recursive: true});
      await fs.writeFile(path.join(input, file), bytes);
    }
    const args = {root: input, stage, tuple, runtimeRef: '1'.repeat(40)};
    const record = await writeCrossRuntimeManifest(args);
    assert.deepEqual(record.files.map(file => file.path), [...files.keys()].sort());
    const runtimeArch = tuple.includes('x86_64') ? 'x86_64' : 'aarch64';
    const builtBounds = path.join(source, 'runtime/CMakebuild/runtime-staging/lib', `${runtimeArch}_Release`, 'libboundscheck.dylib');
    await fs.mkdir(path.dirname(builtBounds), {recursive: true});
    await fs.copyFile(path.join(input, `runtime/lib/${tuple}/libboundscheck.dylib`), builtBounds);
    const target = tuple.replace('_cjnative', '').replaceAll('_', '-').replace('x86-64', 'x86_64');
    const verify = () => invoke('build/sdk/producers/release/verify-ios-runtime.mjs', [], {
      CANGJIE_WORKSPACE: runtimeWorkspace, IOS_TARGET: target, CJCJ_NATIVE_RUNTIME_REF: args.runtimeRef,
    });
    const verified = verify();
    console.log(verified.stdout + verified.stderr);
    const observed = await Promise.all([...files.keys()].map(file => fs.readFile(path.join(stage, file)).then(bytes => bytes.toString('hex'), () => 'MISSING')));
    console.log(`CROSS_BYTES_ASSERT tuple=${tuple} actual=${JSON.stringify(observed)}`);
    assert.deepEqual(observed, [...files.values()].map(bytes => bytes.toString('hex')), 'installed runtime bytes must equal producer bytes');
    assert.equal(verified.status, 0, verified.stdout + verified.stderr);
    await fs.appendFile(path.join(input, `lib/${tuple}/cjstart.o`), 'transport-change');
    const changed = verify();
    assert.equal(changed.status, 1);
    assert.match(changed.stderr, /inventory\/hash mismatch/);
  });
}
