import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../../..');
const workflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');
const platforms = ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64'];

test('srcbuild exposes reusable inputs, outputs, and the runtime override chain', async () => {
  const sourceBuild = await workflow('srcbuild.yml');
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
  const release = await workflow('release.yml');
  assert.ok(release.includes('uses: ./.github/workflows/srcbuild.yml'));
  assert.ok(release.includes('runtime_ref: ${{ inputs.runtime_ref }}'));
  const rows = release.split('\n').filter(line => line.includes('std_artifact: final-std-'));
  assert.equal(rows.length, platforms.length);
  for (const platform of platforms) {
    const row = rows.find(line => line.includes(`platform: ${platform},`));
    assert.ok(row, platform);
    assert.ok(row.includes(`std_artifact: final-std-${platform}`), row);
  }
  assert.ok(release.includes('std_artifact: ${{ matrix.std_artifact }}'));
  assert.ok(release.includes('pattern: pkg-*'));
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
    '--cjpm-provenance',
    '--cjpm-source-repo',
    '--cjpm-source-sha',
  ]) assert.equal(consumer.match(new RegExp(argument, 'g'))?.length, 2, argument);
  assert.equal(consumer.match(/--python-bundle/g)?.length, 2);
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
  assert.ok(consumer.includes('node ci/release/install_cjpm_artifact.mjs'));
});

test('all five package cells consume cjpm artifacts with producer sidecars', async () => {
  const [sourceBuild, windowsCjpm, consumer] = await Promise.all([
    workflow('srcbuild.yml'),
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
  const [release, tuples] = await Promise.all([workflow('release.yml'), workflow('platform-tuples.yml')]);
  assert.ok(release.includes('platform_set: windows-only'));
  assert.ok(!release.includes('platform_set: darwin-windows'));
  assert.ok(!release.includes('uses: ./.github/workflows/build-fixed-llc.yml'));
  assert.ok(tuples.includes("inputs.platform_set == 'windows-only'"));

  const artifacts = [
    ...['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64']
      .map(platform => `fixed-llvm-tools-${platform}`),
    'fixed-llvm-tools-windows_x86_64',
    ...platforms.map(platform => `final-std-${platform}`),
    ...platforms.filter(platform => platform !== 'windows-x64').map(platform => `source-cjpm-${platform}`),
    ...platforms.map(platform => `pkg-${platform}`),
    'runtime-install-windows_x86_64',
    'patched-cjpm-windows_x86_64',
  ];
  assert.equal(new Set(artifacts).size, artifacts.length);
});
