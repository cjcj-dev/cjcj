import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {load as yaml} from '../../vendor/js-yaml/js-yaml.mjs';
import {allReleasePlatforms, getReleasePlatform, releasePlatformReadiness, sourceBuildCells} from '../../../build/lib/targets.mjs';
import {crossStdArguments} from '../../release/cross-std-arguments.mjs';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const workflow = async name => yaml(await fs.readFile(path.join(root, '.github/workflows', name), 'utf8'));
const invoke = (script, args, env = {}) => spawnSync(process.execPath, [path.join(root, script), ...args],
  {encoding: 'utf8', env: {...process.env, ...env}});
const releaseKeys = allReleasePlatforms().filter(key => {
  const p = getReleasePlatform(key);
  return !p.excluded && !p.crossCompiledHost && p.requires.some(req => ['ohos-sdk', 'xcode-ios'].includes(req));
});
const substitute = (text, row) => text.replace(/\$\{\{ matrix\.([a-z_]+) \}\}/g, (_, key) => row[key]);

for (const key of releaseKeys) {
  test(`${key}: declared segments and source admission agree with the release CLI`, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'cross-plan-'));
    t.after(() => fs.rm(dir, {recursive: true, force: true}));
    const run = invoke('ci/release/platform-matrix.mjs', ['plan', '--platforms', key]);
    assert.equal(run.status, 0, run.stderr);
    const plan = JSON.parse(run.stdout);
    const family = key.endsWith('-ios') ? 'ios' : 'ohos';
    const declared = getReleasePlatform(key).crossTuples.filter(tuple => family === 'ios' ? tuple.startsWith('ios_') : tuple.startsWith('linux_ohos_'));
    const readiness = releasePlatformReadiness(key);
    const entries = JSON.parse((plan.package[0] || plan.blocked[0])?.cross_std_artifacts || '[]');
    const sourceCells = sourceBuildCells();
    const eligible = Boolean(readiness.sdkSourceTarget) && [readiness.sourceTarget, ...Object.values(readiness.crossStd)].every(target => sourceCells.some(cell => cell.target === target && cell.status === 'runnable'));
    console.log(`CROSS_TARGET_ASSERT key=${key} declared=${JSON.stringify(declared)} actual=${JSON.stringify(entries)}`);
    assert.deepEqual(entries.filter(e => declared.includes(e.tuple)).map(e => e.tuple).sort(), [...declared].sort(), 'declared cross tuple must have a reachable producer');
    console.log(`CROSS_SOURCE_GUARD_ASSERT key=${key} eligible=${eligible} packages=${plan.package.length}`);
    assert.equal(plan.package.length, eligible ? 1 : 0, 'incomplete native producer must not enter runnable release packages');
    if (!eligible) assert.deepEqual(plan.source, []);
    if (readiness.status === 'blocked') {
      assert.equal(plan.blocked[0].reasons, readiness.reasons.join(' | '));
      if (!readiness.sdkSourceTarget) assert.match(plan.blocked[0].reasons, /native SDK .*no source cell runs package-install/);
      else assert.match(plan.blocked[0].reasons, /source darwin-arm64:.*#?473|issues\/473/);
    }
    const source = {target: readiness.crossStd[declared[0]]};
    assert.ok(source.target, `${key}: declared cross source`);
    const file = path.join(dir, 'output');
    const selected = invoke('ci/srcbuild/target-matrix.mjs', ['--targets', source.target, '--single'], {GITHUB_OUTPUT: file});
    assert.equal(selected.status, 0, selected.stderr);
    const outputs = Object.fromEntries((await fs.readFile(file, 'utf8')).trim().split('\n').map(line => {
      const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)];
    }));
    const cell = sourceBuildCells().find(cell => cell.target === source.target);
    const admission = invoke('ci/srcbuild/target-matrix.mjs', ['--targets', source.target, '--single', '--require-ready']);
    console.log(`CROSS_ADMISSION_ASSERT target=${source.target} status=${cell.status} rc=${admission.status}`);
    assert.equal(admission.status, cell.status === 'runnable' ? 0 : 1);
    if (cell.status === 'blocked') {
      assert.match(admission.stderr, /blocked:.*issues\/473/);
      assert.deepEqual(JSON.parse(outputs.matrix).include, []);
    }
    const rows = JSON.parse(outputs[`${family}_matrix`]).include;
    const [outer, inner, breadth] = await Promise.all(['srcbuild.yml', 'srcbuild-target.yml', 'release-matrix.yml'].map(workflow));
    assert.equal(breadth.jobs.source.with[`build_${family}`], `\${{ matrix.build_${family} || false }}`);
    assert.equal(outer.jobs.srcbuild.with[`build_${family}`], `\${{ inputs.build_${family} || false }}`);
    for (const w of [outer, inner]) assert.equal(w.on.workflow_call.inputs[`build_${family}`].default, false);
    const job = inner.jobs[`source-${family}`];
    assert.deepEqual(job.needs, ['plan', 'source-stage3']);
    assert.equal(job.strategy.matrix, `\${{ fromJson(needs.plan.outputs.${family}_matrix) }}`);
    assert.equal(inner.jobs.plan.outputs[`${family}_matrix`], `\${{ steps.select.outputs.${family}_matrix }}`);
    const restoreEntry = family === 'ios' ? 'ios-stage2-handoff.mjs restore' : 'job-handoff.mjs restore stage3';
    const restore = job.steps.findIndex(step => step.run?.includes(restoreEntry));
    const build = job.steps.findIndex(step => step.run?.includes(`build-${family}-final-std.mjs`));
    assert.ok(restore >= 0 && build > restore, 'cross consumer must follow verified SDK restore');
    const download = job.steps.find(step => step.uses?.startsWith('actions/download-artifact@'));
    const upload = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
    if (family === 'ios') {
      const producer = inner.jobs['source-stage3'].steps.find(s => s.with?.name === download.with.name);
      assert.equal(producer.if, "matrix.target == 'darwin-arm64' && inputs.build_ios");
      assert.equal(producer.with['if-no-files-found'], 'error');
      assert.ok(job.steps.some(s => s.uses?.startsWith('actions/checkout@') && s.with['persist-credentials'] === false));
      assert.ok(job.steps.every(s => !s.run?.includes('job-handoff.mjs')));
    }
    assert.equal(job.steps[build].env.CROSS_STD_TUPLE, '${{ matrix.tuple }}');
    for (const entry of entries.filter(e => declared.includes(e.tuple))) {
      const row = rows.find(row => row.tuple === entry.tuple);
      const published = row && substitute(upload.with.name, row);
      console.log(`CROSS_ARTIFACT_ASSERT tuple=${entry.tuple} producer=${published} consumer=${entry.artifact}`);
      assert.equal(published, entry.artifact, 'published artifact must be the package consumer artifact');
      assert.equal(substitute(download.with.name, row), family === 'ios'
        ? `source-ios-stage2-${source.target}` : `source-handoff-${source.target}-stage3`);
      assert.equal(substitute(upload.with.path, row), `\${{ env.CANGJIE_WORKSPACE }}/software/${entry.artifact}`);
      assert.equal(upload.with['if-no-files-found'], 'error');
    }
    const args = crossStdArguments(JSON.stringify(entries), '/downloaded artifacts');
    const actual = args.flatMap((value, i) => value === '--cross-runtime-dir' ? [args[i + 1]] : []);
    console.log(`CROSS_ARGUMENT_ASSERT key=${key} actual=${JSON.stringify(actual)}`);
    assert.deepEqual(actual, entries.filter(e => declared.includes(e.tuple)).map(e => `${e.tuple}=/downloaded artifacts/${e.artifact}/cross-runtime`));
  });
}

test('Android and Windows independent controls retain their producer and consumer branches', async () => {
  const run = invoke('ci/release/platform-matrix.mjs', ['plan', '--platforms', 'linux-x64-android,win32-x64']);
  assert.equal(run.status, 0, run.stderr);
  const plan = JSON.parse(run.stdout);
  assert.equal(plan.source.find(row => row.target === 'linux-x64').build_android, true);
  assert.ok(plan.source.every(row => !row.build_ios && !row.build_ohos));
  const jobs = (await workflow('srcbuild-target.yml')).jobs;
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
    const verify = () => invoke('ci/release/verify-ios-runtime.mjs', [], {
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
