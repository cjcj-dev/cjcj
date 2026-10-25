import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {releasePlatformReadiness, getTarget} from '../../build/lib/targets.mjs';
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
    const sourceReasons = [];
    if (!result.sdkSourceTarget) sourceReasons.push(
      `native SDK ${result.host}: no source cell runs package-install and uploads cjcj-srcbuild-${result.host}-VERSION; cross std/components are not a whole SDK`);
    if (getTarget(result.host).nativeSourceBuild) sourceReasons.push(
      `native SDK ${result.host}: explicit native pair and provider inputs required`);
    sourceReasons.push(...getTarget(result.sourceTarget).sourceBuild.reasons.map(reason => `source ${result.sourceTarget}: ${reason}`));
    assert.equal(result.packageDeclared, true);
    assert.deepEqual(result.reasons.filter(reason => !baseline.includes(reason)), sourceReasons);
    assert.equal(result.status, sourceReasons.length ? 'blocked' : 'buildable');
    for (const tuple of expected) assert.equal(result.crossStd[tuple], 'linux-x64');
  });

  test(`OHOS matrix CLI connects runtime and std artifacts for ${key}`, () => {
    const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', key], {encoding: 'utf8'});
    assert.equal(run.status, 0, run.stderr);
    const plan = JSON.parse(run.stdout);
    const actual = crossStdArguments((plan.package[0] || plan.blocked[0])?.cross_std_artifacts ?? '[]', '/artifact root');
    const arches = key === 'darwin-arm64-ohos' ? ['aarch64'] : ['aarch64', 'x86_64'];
    const expected = arches.flatMap(arch => {
      const location = `linux_ohos_${arch}_cjnative=/artifact root/final-std-ohos-${arch.replace('_', '-')}`;
      return ['--cross-std-dir', location, '--cross-runtime-dir', `${location}/cross-runtime`];
    });
    if (key === 'linux-x64-ohos') expected.push('--cross-std-dir', 'windows_x86_64_cjnative=/artifact root/final-std-windows-x64');
    console.log(`ASSERT_OHOS_CROSS_CONSUMER ${key} ${JSON.stringify(actual)}`);
    assert.deepEqual(actual, expected);
    if (plan.package.length) assert.deepEqual(plan.source.find(row => row.target === 'linux-x64'), {target: 'linux-x64', build_ohos: true});
    else {
      assert.deepEqual(plan.source, []);
      const readiness = releasePlatformReadiness(key);
      for (const reason of readiness.reasons) assert.ok(plan.blocked[0].reasons.includes(reason), reason);
      assert.ok(readiness.reasons.length, 'blocked CLI result must retain a concrete producer gap');
    }
  });
}

test('OHOS real release workflow selects the shared SDK probe and both source artifacts', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  const source = fs.readFileSync(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  assert.match(source, /requirement: ohos-sdk/);
  assert.match(source, /run: npx --yes zx@8 ci\/srcbuild\/steps\/build-ohos-final-std\.mjs/);
  assert.match(source, /matrix: \$\{\{ fromJson\(needs.plan.outputs.ohos_matrix\) \}\}/);
  const job = source.slice(source.indexOf('  source-ohos:'), source.indexOf('  source-ios:'));
  assert.ok(job.includes('name: ${{ matrix.artifact }}'));
  assert.ok(job.includes('/software/${{ matrix.artifact }}'));
  assert.ok(job.includes('job-handoff.mjs restore stage3'));
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
  assert.match(workflow, /build_ohos: true/);
  for (const key of keys) {
    assert.ok(workflow.includes(`release_key: ${key}\n`));
    assert.ok(workflow.includes(`needs.package-${key}.result == 'success'`));
  }
});
