import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {load as loadYaml} from '../../vendor/js-yaml/js-yaml.mjs';
import {allTargets, getTarget, getReleasePlatform, releasePlatformReadiness} from '../../../build/lib/targets.mjs';
import {planMatrix} from '../../release/platform-matrix.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const workflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');
const plan = planMatrix('all');
const nativeRows = plan.package.filter(row => getReleasePlatform(row.release_key).archiveKey === row.platform);
const nativeKeys = nativeRows.map(row => row.release_key);
const releaseWorkflow = async () => loadYaml(await workflow('release.yml'));
const jobsOf = release => Object.entries(release.jobs).map(([id, job]) => ({...job, id}));
const packageJobsOf = release => jobsOf(release)
  .filter(job => job.uses === './.github/workflows/build-release-package.yml');

const platforms = allTargets();

test('srcbuild exposes reusable inputs, outputs, and the runtime override chain', async () => {
  const sourceBuild = await workflow('srcbuild-target.yml');
  for (const contract of [
    'workflow_call:',
    'runtime_ref:',
    'CJCJ_RUNTIME_REF_OVERRIDE: ${{ inputs.runtime_ref }}',
    'run: npx --yes zx@8 ci/load_runtime_pin.mjs',
  ]) assert.ok(sourceBuild.includes(contract), contract);
  for (const platform of platforms) {
    const output = `final_std_${platform.replaceAll('-', '_')}:`;
    assert.ok(sourceBuild.includes(output), output);
    assert.ok(sourceBuild.includes(`final-std-${platform}`), platform);
  }
});

test('release connects each platform row to its same-platform final std', async () => {
  const release = await releaseWorkflow();
  assert.ok(jobsOf(release).some(job => job.uses === './.github/workflows/srcbuild.yml'));
  assert.ok(jobsOf(release).some(job => job.with?.runtime_ref === '${{ inputs.runtime_ref }}'));
  // The pairing, not the row that used to carry it. Phase control replaced the
  // matrix with one job per phase, so platform and std_artifact now sit on
  // separate lines of the same with: block; a line-shaped check reads a correct
  // wiring as missing.
  const packageJobs = packageJobsOf(release)
    .filter(job => nativeKeys.includes(job.with?.release_key));
  assert.equal(packageJobs.length, platforms.length,
    `expected one package job per platform, found ${packageJobs.length}`);
  for (const platform of platforms) {
    const job = packageJobs.find(entry => entry.with?.platform === platform);
    assert.ok(job, `no package job declares platform: ${platform}`);
    assert.equal(job.with?.std_artifact, `final-std-${platform}`,
      `the ${platform} package job does not ask for final-std-${platform}`);
  }
  assert.ok(jobsOf(release).some(job => job.steps?.some(step => step.with?.pattern === 'pkg-*')));
});

test('release cross packages depend on their native phase and Android producer with same-host std', async () => {
  const release = await releaseWorkflow();
  const packages = packageJobsOf(release);
  const cross = packages.filter(job => !nativeKeys.includes(job.with?.release_key));
  const rows = plan.package.filter(row => !nativeKeys.includes(row.release_key));
  assert.deepEqual(cross.map(job => job.with?.release_key).sort(), rows.map(row => row.release_key).sort(),
    'every non-native package must have an explicit cross contract');
  const sources = jobsOf(release).filter(job => job.uses === './.github/workflows/srcbuild.yml');
  const jobId = job => job.id;
  for (const row of rows) {
    const {release_key: key, platform: host} = row;
    const job = cross.find(entry => entry.with?.release_key === key);
    assert.equal(job.with?.platform, host, `${key}: package host`);
    assert.equal(job.with?.std_artifact, row.std_artifact, `${key}: same-host final std`);
    const native = packages.find(entry => nativeKeys.includes(entry.with?.release_key) && entry.with?.platform === host);
    assert.ok(native, `${key}: native package dependency`);
    const producerJobs = Object.values(releasePlatformReadiness(key).crossStd).map(target => {
      const producer = sources.find(entry => entry.with?.targets === target);
      assert.ok(producer, `${key}: cross std source ${target}`);
      return jobId(producer);
    });
    assert.deepEqual([...job.needs].sort(),
      [...new Set([jobId(native), ...producerJobs])].sort(), `${key}: native phase and cross producer dependencies`);
    const tuples = JSON.parse(job.with?.cross_std_artifacts);
    assert.deepEqual(tuples, JSON.parse(row.cross_std_artifacts), `${key}: cross std tuples`);
    const publish = release.jobs.publish;
    assert.ok(publish.needs.includes(jobId(job)),
      `${key}: publish waits for the cross package`);
    assert.ok(publish.if.includes(`needs.${jobId(job)}.result == 'success'`), `${key}: publish requires cross success`);
  }
  for (const row of plan.source.filter(row => row.build_android)) {
    const producer = sources.find(job => job.with?.targets === row.target);
    assert.ok(producer, `${row.target}: Android producer exists`);
    assert.equal(producer.with?.build_android, true, `${row.target}: Android producer is enabled`);
  }
});

test('component provenance, final std, and Python inputs are fail-closed in both package commands', async () => {
  const consumer = await workflow('build-release-package.yml');
  const downloadStart = consumer.indexOf('- name: Download same-platform source-built final std');
  const downloadEnd = consumer.indexOf('\n      - name:', downloadStart + 1);
  assert.ok(downloadStart >= 0);
  const download = consumer.slice(downloadStart, downloadEnd);
  assert.ok(download.includes('name: ${{ inputs.std_artifact }}'));
  assert.ok(download.includes('path: ${{ env.FINAL_STD_DIR }}'));
  assert.ok(!download.includes('continue-on-error'));
  assert.equal(consumer.match(/--std-dir/g)?.length, 2);
  for (const argument of [
    '--base-sdk-archive',
    '--base-sdk-provenance',
    '--gate-host-runtime',
    '--gate-apparatus-provenance',
    '--cjpm-provenance',
    '--cjpm-source-repo',
    '--cjpm-source-sha',
    '--tools-source-repo',
    '--tools-source-sha',
  ]) assert.equal(consumer.match(new RegExp(argument, 'g'))?.length, 2, argument);
  assert.ok(consumer.includes('cat ci/source_pin.env >> "$GITHUB_ENV"'));
  assert.equal(consumer.match(/--python-bundle/g)?.length, 2);
  assert.equal(consumer.match(/prepare_gate_apparatus\.mjs/g)?.length, 2);
  assert.equal(consumer.match(/prepare_python_bundle\.mjs/g)?.length, 2);
  assert.equal(consumer.match(/verify_packaged_cjdb\.mjs/g)?.length, 2);
  for (const name of ['Prepare Python 3.11 bundle (Unix)', 'Prepare Python 3.11 bundle (Windows)']) {
    const start = consumer.indexOf(`- name: ${name}`);
    const end = consumer.indexOf('\n      - name:', start + 1);
    assert.ok(start >= 0, name);
    assert.ok(!consumer.slice(start, end).includes('continue-on-error'), name);
  }
  assert.ok(consumer.includes('EXPECTED_STD_ARTIFACT: final-std-${{ inputs.platform }}'));
  assert.ok(consumer.includes('name: source-cjpm-${{ inputs.platform }}'));
  assert.ok(consumer.includes('node ci/release/prepare_base_sdk.mjs'));
  assert.ok(consumer.includes('--actual-host-toolchain "$CJCJ_ACTUAL_HOST_TOOLCHAIN"'));
  assert.ok(consumer.includes('--actual-host-toolchain "$env:CJCJ_ACTUAL_HOST_TOOLCHAIN"'));
  assert.ok(consumer.includes('--base-sdk-id "$RELEASE_HOST_TOOLCHAIN"'));
  assert.ok(consumer.includes('--base-sdk-id "$env:RELEASE_HOST_TOOLCHAIN"'));
  assert.ok(consumer.includes('node ci/release/install_cjpm_artifact.mjs'));
});

test('private toolchain setup retains base SDK provenance and content-addressed bytes', async () => {
  const [setup, platformSetup, provenance] = await Promise.all([
    fs.readFile(path.join(root, 'ci/setup_sdk.mjs'), 'utf8'),
    fs.readFile(path.join(root, 'ci/platform_matrix/build_cjcj.mjs'), 'utf8'),
    fs.readFile(path.join(root, 'build/lib/release-component-provenance.mjs'), 'utf8'),
  ]);
  for (const source of [setup, platformSetup]) {
    assert.ok(source.includes('persistBaseSdkProvenance({'));
    assert.ok(source.includes('toolchainDir: cangjieHome'));
  }
  assert.ok(provenance.includes("path.join(root, '.cjv')"));
  assert.ok(provenance.includes("path.join('archives', 'sha256', value.artifact.sha256, expected.archive)"));
  assert.ok(provenance.includes('await fs.rename(temporary, destination)'));
});

test('release package runs the packaged std checker as a bounded fail-closed step', async () => {
  const consumer = await workflow('build-release-package.yml');
  const start = consumer.indexOf('- name: Verify packaged standard library');
  const end = consumer.indexOf('\n      - name:', start + 1);
  assert.ok(start >= 0, 'packaged std verification step is missing');
  const check = consumer.slice(start, end);
  assert.match(check, /if: inputs\.verify/);
  assert.match(check, /timeout-minutes: 2/);
  assert.ok(!check.includes('continue-on-error'));
  assert.ok(check.includes('node scripts/check_packaged_std.mjs'));
  for (const argument of ['--sdk', '--std', '--platform']) assert.ok(check.includes(argument), argument);
  assert.equal(consumer.match(/node scripts\/check_packaged_std\.mjs/g)?.length, 1);
  assert.ok(start > consumer.indexOf('- name: Compose SDK package (Windows)'));
  assert.ok(start < consumer.indexOf('- name: Verify packaged SDK'));
});

test('all package cells consume cjpm artifacts with producer sidecars', async () => {
  const [sourceBuild, windowsCjpm, consumer] = await Promise.all([
    workflow('srcbuild-target.yml'),
    workflow('build-cjpm.yml'),
    workflow('build-release-package.yml'),
  ]);
  assert.ok(sourceBuild.includes('name: source-cjpm-${{ matrix.target }}'));
  assert.ok(sourceBuild.includes('node ci/release/prepare_cjpm_artifact.mjs'));
  assert.ok(windowsCjpm.includes('patched-cjpm/windows_x86_64/CJPM-PROVENANCE.json'));
  assert.ok(windowsCjpm.includes('node ci/release/prepare_cjpm_artifact.mjs'));
  assert.ok(consumer.includes("if: runner.os != 'Windows'"));
  assert.ok(consumer.includes('run: npx --yes zx@8 ci/platform_matrix/fetch_cjpm.mjs'));
});

test('release has one LLVM producer per tuple', async () => {
  const [release, tuples] = await Promise.all([releaseWorkflow(), workflow('platform-tuples.yml')]);
  assert.ok(jobsOf(release).some(job => job.with?.platform_set === 'windows-only'));
  assert.ok(!jobsOf(release).some(job => job.with?.platform_set === 'darwin-windows'));
  assert.ok(!jobsOf(release).some(job => job.uses === './.github/workflows/build-fixed-llc.yml'));
  assert.ok(tuples.includes("inputs.platform_set == 'windows-only'"));

  const artifacts = [
    ...platforms.map(platform => `fixed-llvm-tools-${getTarget(platform).spec.llvmPlatform}`),
    ...platforms.map(platform => `final-std-${platform}`),
    ...platforms.filter(platform => !getTarget(platform).spec.crossCompile).map(platform => `source-cjpm-${platform}`),
    ...platforms.map(platform => `pkg-${platform}`),
    ...platforms.filter(platform => getTarget(platform).spec.crossCompile).flatMap(platform =>
      [`runtime-install-${getTarget(platform).spec.llvmPlatform}`, `patched-cjpm-${getTarget(platform).spec.llvmPlatform}`]),
  ];
  assert.equal(new Set(artifacts).size, artifacts.length);
});

test('release packages select the named final compiler in each native phase', async () => {
  const release = await releaseWorkflow();
  const source = await workflow('srcbuild-target.yml');
  const consumer = await workflow('build-release-package.yml');
  const jobs = packageJobsOf(release);
  for (const platform of platforms.filter(name => !getTarget(name).spec.crossCompile)) {
    const job = jobs.find(entry => entry.with?.platform === platform);
    assert.equal(job.with?.compiler_artifact, `final-compiler-${platform}`, platform);
    assert.ok(source.includes(`final_compiler_${platform.replaceAll('-', '_')}:`), platform);
  }
  assert.match(source, /name: final-compiler-\$\{\{ matrix.target \}\}/);
  assert.ok(consumer.includes('node ci/release/select_final_compiler.mjs'));
  assert.ok(consumer.includes('--binary "$FINAL_COMPILER_BINARY"'));
  assert.ok(consumer.includes('$binary = "$env:FINAL_COMPILER_BINARY"'));
  assert.equal(consumer.match(/--compiler-artifact/g)?.length, 2);
});
