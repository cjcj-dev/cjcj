import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {releasePlatformReadiness} from '../../build/lib/targets.mjs';
import {crossStdArguments} from './cross-std-arguments.mjs';

const tuples = ['ios_aarch64_cjnative', 'ios_simulator_aarch64_cjnative', 'ios_simulator_x86_64_cjnative'];
const entries = tuples.map(tuple => ({tuple, artifact: `final-std-${tuple.replaceAll('_', '-')}`}));
test('iOS producer removes exactly the three frozen missing-tuple reasons', () => {
  const baseline = tuples.map(tuple => `tuple ${tuple}: no P01-P23 stage cross-builds a runtime and final std for it (P24 cross target)`);
  const result = releasePlatformReadiness('darwin-arm64-ios');
  console.log(`ASSERT_IOS_READINESS ${JSON.stringify(result)}`);
  assert.deepEqual(baseline.filter(reason => !result.reasons.includes(reason)), baseline, 'remove precisely the iOS missing-producer reasons');
  assert.deepEqual(result.reasons.filter(reason => !baseline.includes(reason)), [], 'no unrelated new blocker');
  assert.equal(result.status, 'buildable');
  assert.deepEqual(result.crossStd, Object.fromEntries(tuples.map(tuple => [tuple, 'darwin-arm64'])));
});

test('iOS matrix CLI carries three cross runtimes and final stds into package arguments', () => {
  const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', 'darwin-arm64-ios'], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  const plan = JSON.parse(run.stdout);
  assert.deepEqual(plan.source, [{target: 'darwin-arm64', build_ios: true}]);
  const args = crossStdArguments(plan.package[0]?.cross_std_artifacts ?? '[]', '/artifacts with spaces');
  console.log(`ASSERT_IOS_CROSS_CONSUMER ${JSON.stringify(args)}`);
  assert.deepEqual(args, entries.flatMap(({tuple, artifact}) => [
    '--cross-std-dir', `${tuple}=/artifacts with spaces/${artifact}`,
    '--cross-runtime-dir', `${tuple}=/artifacts with spaces/${artifact}/cross-runtime`,
  ]), 'each iOS tuple must carry runtime and final std together');
});

test('iOS release workflow consumes the same tuple artifacts and requires package success', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  const source = fs.readFileSync(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const release = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
  const jobs = release.split(/\n  (?=[a-z0-9-]+:\n)/);
  const job = jobs.find(entry => entry.includes('release_key: darwin-arm64-ios')) ?? '';
  const scalar = (text, key) => text.match(new RegExp(String.raw`^\s*${key}:\s*(.+?)\s*$`, 'm'))?.[1];
  assert.equal(scalar(job, 'platform'), 'darwin-arm64');
  assert.equal(scalar(job, 'std_artifact'), 'final-std-darwin-arm64');
  assert.equal(scalar(job, 'needs'), '[package-p4-darwin-arm64, source-p4-darwin-arm64]');
  assert.deepEqual(JSON.parse(scalar(job, 'cross_std_artifacts')?.replace(/^'|'$/g, '') ?? '[]'), entries);
  for (const {tuple, artifact} of entries) {
    assert.ok(source.includes(`name: ${artifact}\n`), artifact);
    assert.ok(source.includes(`/software/final-std-ios/${tuple}\n`), tuple);
  }
  const producer = jobs.find(entry => entry.includes('targets: darwin-arm64')) ?? '';
  assert.equal(scalar(producer, 'build_ios'), 'true');
  const publish = jobs.find(entry => entry.startsWith('publish:')) ?? '';
  assert.ok(scalar(publish, 'needs')?.includes('package-darwin-arm64-ios'));
  assert.ok(publish.includes("needs.package-darwin-arm64-ios.result == 'success'"));
});

test('plain Darwin host selection does not request iOS builds', () => {
  const run = spawnSync(process.execPath, [path.join(import.meta.dirname, 'platform-matrix.mjs'), 'plan', '--platforms', 'darwin-arm64'], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(JSON.parse(run.stdout).source, [{target: 'darwin-arm64'}]);
});
