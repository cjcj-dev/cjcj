import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {releasePlatformReadiness} from '../../build/lib/targets.mjs';
import {crossStdArguments} from './compose-package.mjs';

const tuple = 'linux_android_aarch64_cjnative';
const keys = ['linux-x64-android', 'darwin-arm64-android', 'win32-x64-android'];
for (const key of keys) test(`Android producer removes exactly the frozen missing-tuple reason for ${key}`, () => {
  const baseline = [`tuple ${tuple}: no P01-P23 stage cross-builds a runtime and final std for it (P24 cross target)`];
  const result = releasePlatformReadiness(key);
  console.log(`ASSERT_ANDROID_READINESS ${key} ${JSON.stringify(result)}`);
  assert.deepEqual(baseline.filter(reason => !result.reasons.includes(reason)), baseline, 'the Android producer must remove its precise missing-tuple reason');
  assert.deepEqual(result.reasons.filter(reason => !baseline.includes(reason)), [], 'no new blocker');
  assert.equal(result.status, 'buildable');
  assert.equal(result.crossStd[tuple], 'linux-x64');
});

test('Windows Android matrix CLI carries both cross artifacts into package arguments', () => {
  const script = path.join(import.meta.dirname, 'platform-matrix.mjs');
  const run = spawnSync(process.execPath, [script, 'plan', '--platforms', 'win32-x64-android'], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  const plan = JSON.parse(run.stdout);
  assert.deepEqual(plan.source, [{target: 'linux-x64', build_android: true}]);
  const row = plan.package[0];
  const entries = JSON.parse(row?.cross_std_artifacts ?? '[]');
  const args = crossStdArguments(JSON.stringify(entries), '/artifacts with spaces');
  console.log(`ASSERT_ANDROID_CROSS_CONSUMER ${JSON.stringify(args)}`);
  assert.deepEqual(args, ['--cross-std-dir', `${tuple}=/artifacts with spaces/final-std-android-aarch64`,
    '--cross-runtime-dir', `${tuple}=/artifacts with spaces/final-std-android-aarch64/cross-runtime`,
    '--cross-std-dir', 'linux_x86_64_cjnative=/artifacts with spaces/final-std-linux-x64']);
});

test('cross artifact inputs reject duplicates and unsafe names', () => {
  const entry = {tuple, artifact: 'final-std-android-aarch64'};
  assert.throws(() => crossStdArguments(JSON.stringify([entry, entry]), '/artifacts'), /duplicate/);
  assert.throws(() => crossStdArguments(JSON.stringify([{...entry, artifact: '../other'}]), '/artifacts'), /invalid/);
  assert.deepEqual(crossStdArguments('[]', '/artifacts'), []);
});

test('Android producer and package consumer are connected to the real release workflows', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  const source = fs.readFileSync(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const packageWorkflow = fs.readFileSync(path.join(root, '.github/workflows/build-release-package.yml'), 'utf8');
  const packager = fs.readFileSync(path.join(root, 'scripts/package_sdk.mjs'), 'utf8');
  assert.match(source, /run: npx --yes zx@8 ci\/srcbuild\/steps\/build-android-final-std\.mjs/);
  assert.match(source, /name: final-std-android-aarch64\n/);
  assert.match(packageWorkflow, /pattern: final-std-\*/);
  assert.equal((packageWorkflow.match(/npx --yes zx@8 ci\/release\/compose-package\.mjs/g) ?? []).length, 2);
  assert.match(packager, /await installCrossRuntime\(\{root: spec\.slice\(split \+ 1\), stage, tuple, runtimeRef: runtimeSourceCommit\}\)/);
});

test('plain host packages do not add an Android build dependency', () => {
  const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', 'linux-x64'], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(JSON.parse(run.stdout).source, [{target: 'linux-x64'}]);
});
