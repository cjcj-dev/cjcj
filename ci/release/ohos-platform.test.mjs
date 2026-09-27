import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {releasePlatformReadiness} from '../../build/lib/targets.mjs';
import {crossStdArguments} from './cross-std-arguments.mjs';

const tuples = ['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative'];
const keys = ['linux-x64-ohos', 'darwin-arm64-ohos', 'win32-x64-ohos'];
for (const key of keys) {
  test(`OHOS producer removes precisely its frozen missing-tuple reasons for ${key}`, () => {
    const expected = key === 'darwin-arm64-ohos' ? tuples.slice(0, 1) : tuples;
    const baseline = expected.map(tuple => `tuple ${tuple}: no P01-P23 stage cross-builds a runtime and final std for it (P24 cross target)`);
    const result = releasePlatformReadiness(key);
    console.log(`ASSERT_OHOS_READINESS ${key} ${JSON.stringify(result)}`);
    assert.deepEqual(baseline.filter(reason => !result.reasons.includes(reason)), baseline);
    assert.deepEqual(result.reasons.filter(reason => !baseline.includes(reason)), []);
    assert.equal(result.status, 'buildable');
    for (const tuple of expected) assert.equal(result.crossStd[tuple], 'linux-x64');
  });

  test(`OHOS matrix CLI connects runtime and std artifacts for ${key}`, () => {
    const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', key], {encoding: 'utf8'});
    assert.equal(run.status, 0, run.stderr);
    const plan = JSON.parse(run.stdout);
    const actual = crossStdArguments(plan.package[0]?.cross_std_artifacts ?? '[]', '/artifact root');
    const arches = key === 'darwin-arm64-ohos' ? ['aarch64'] : ['aarch64', 'x86_64'];
    const expected = arches.flatMap(arch => {
      const location = `linux_ohos_${arch}_cjnative=/artifact root/final-std-ohos-${arch.replace('_', '-')}`;
      return ['--cross-std-dir', location, '--cross-runtime-dir', `${location}/cross-runtime`];
    });
    if (key === 'linux-x64-ohos') expected.push('--cross-std-dir', 'windows_x86_64_cjnative=/artifact root/final-std-windows-x64');
    console.log(`ASSERT_OHOS_CROSS_CONSUMER ${key} ${JSON.stringify(actual)}`);
    assert.deepEqual(actual, expected);
    assert.deepEqual(plan.source.find(row => row.target === 'linux-x64'), {target: 'linux-x64', build_ohos: true});
  });
}

test('OHOS real release workflow selects the shared SDK probe and both source artifacts', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  const source = fs.readFileSync(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  assert.match(source, /requirement: ohos-sdk/);
  assert.match(source, /run: npx --yes zx@8 ci\/srcbuild\/steps\/build-ohos-final-std\.mjs/);
  for (const arch of ['aarch64', 'x86-64']) assert.ok(source.includes(`name: final-std-ohos-${arch}\n`));
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
  assert.match(workflow, /build_ohos: true/);
  for (const key of keys) {
    assert.ok(workflow.includes(`release_key: ${key}\n`));
    assert.ok(workflow.includes(`needs.package-${key}.result == 'success'`));
  }
});
