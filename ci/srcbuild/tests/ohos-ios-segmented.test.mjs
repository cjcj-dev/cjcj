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
    const restore = job.steps.findIndex(step => step.run?.includes('job-handoff.mjs restore stage3'));
    const build = job.steps.findIndex(step => step.run?.includes(`build-${family}-final-std.mjs`));
    assert.ok(restore >= 0 && build > restore, 'cross consumer must follow verified stage3 restore');
    const download = job.steps.find(step => step.uses?.startsWith('actions/download-artifact@'));
    const upload = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
    assert.equal(job.steps[build].env.CROSS_STD_TUPLE, '${{ matrix.tuple }}');
    for (const entry of entries.filter(e => declared.includes(e.tuple))) {
      const row = rows.find(row => row.tuple === entry.tuple);
      const published = row && substitute(upload.with.name, row);
      console.log(`CROSS_ARTIFACT_ASSERT tuple=${entry.tuple} producer=${published} consumer=${entry.artifact}`);
      assert.equal(published, entry.artifact, 'published artifact must be the package consumer artifact');
      assert.equal(substitute(download.with.name, row), `source-handoff-${source.target}-stage3`);
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
for (const [tuple, cpu] of [['ios_aarch64_cjnative', 0x0100000c],
  ['ios_simulator_aarch64_cjnative', 0x0100000c], ['ios_simulator_x86_64_cjnative', 0x01000007]]) {
  test(`${tuple}: installer preserves declared binary bytes and rejects changed transport`, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'ios-artifact-'));
    t.after(() => fs.rm(dir, {recursive: true, force: true}));
    const workspace = path.join(dir, 'workspace');
    const runtimeWorkspace = path.join(workspace, '.srcbuild/workspace');
    const source = path.join(runtimeWorkspace, 'cangjie_runtime');
    const input = path.join(source, 'runtime-install'), stage = path.join(source, 'installed-sdk');
    const files = new Map([[`lib/${tuple}/cjstart.o`, Buffer.from('fixture-start-object')]]);
    for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
      const bytes = Buffer.alloc(64); bytes.writeUInt32LE(0xfeedfacf, 0); bytes.writeUInt32LE(cpu, 4); bytes.writeUInt32LE(6, 12);
      bytes.write(name, 32); files.set(`runtime/lib/${tuple}/${name}`, bytes);
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
    for (const entry of ['packages', 'runtime_shim']) await fs.mkdir(path.join(workspace, entry), {recursive: true});
    await fs.writeFile(path.join(workspace, 'cjpm.toml'), 'controlled source handoff');
    const handoff = path.join(dir, 'source-handoff');
    const env = {...process.env, GITHUB_WORKSPACE: workspace, RUNNER_TEMP: dir,
      GITHUB_SHA: '1'.repeat(40), GITHUB_RUN_ID: '478', CJCJ_SRCBUILD_TARGET: 'darwin-arm64',
      GITHUB_ENV: path.join(dir, 'env'), GITHUB_PATH: path.join(dir, 'path')};
    const jobs = (await workflow('srcbuild-target.yml')).jobs;
    const pack = jobs['source-stage3'].steps.find(step => step.run?.includes('job-handoff.mjs pack stage3')).run;
    const restore = jobs['source-ios'].steps.find(step => step.run?.includes('job-handoff.mjs restore stage3')).run;
    const execute = command => spawnSync('bash', ['-c', command], {cwd: root, env, encoding: 'utf8'});
    const packed = execute(pack);
    assert.equal(packed.status, 0, packed.stdout + packed.stderr);
    const upload = jobs['source-stage3'].steps.find(step => step.uses?.startsWith('actions/upload-artifact@') && step.with?.name?.startsWith('source-handoff-'));
    const download = jobs['source-ios'].steps.find(step => step.uses?.startsWith('actions/download-artifact@'));
    const location = value => value.replace('${{ runner.temp }}', dir);
    assert.equal(download.with.name, upload.with.name, 'same stage3 artifact crosses the job boundary');
    // Actions upload/download copies the packed directory to the consumer's
    // declared download path; the producer and consumer paths need not match.
    await fs.cp(location(upload.with.path), location(download.with.path), {recursive: true});
    await fs.rm(workspace, {recursive: true});
    await fs.mkdir(workspace);
    const restored = execute(restore);
    assert.equal(restored.status, 0, restored.stdout + restored.stderr);
    console.log(`CROSS_HANDOFF_ASSERT tuple=${tuple} ${restored.stdout.trim()}`);
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
    await fs.appendFile(path.join(handoff, 'payload.tar'), 'changed-handoff-transport');
    await fs.rm(env.GITHUB_ENV, {force: true});
    const corrupt = execute(restore);
    console.log(`CROSS_HANDOFF_REJECT_ASSERT tuple=${tuple} rc=${corrupt.status}`);
    assert.equal(corrupt.status, 1);
    assert.match(corrupt.stderr, /handoff payload SHA256 mismatch/);
    await assert.rejects(fs.stat(env.GITHUB_ENV), {code: 'ENOENT'});
  });
}
