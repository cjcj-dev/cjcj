import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

import {bindEvidence} from './evidence-binding-fixture.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function gate(evidence, checkout = repo) {
  const result = spawnSync(process.execPath,
    [command, 'G14', '--repo', checkout, '--evidence', evidence, '--json'],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`G14 output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

async function evidenceFixture(t, {fys = 1, observed = fys, missing = '', miss = 0, checkout = repo} = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g14-policy-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const rawHeader = [
    'round', 'load', 'fys', 'rc', 'minors', 'miss', 'missBare', 'missBareNeverSeen', 'status',
    'fys_bound', 'fallbackFullScan_obs',
  ];
  const remsetHeader = [
    'round', 'load', 'fys', 'rc', 'minors', 'remsetMiss', 'missBare', 'missBareNeverSeen', 'status',
  ];
  const raw = [];
  const remset = [];
  for (let round = 1; round <= 20; round += 1) {
    for (const load of ['O0', 'O2']) {
      if (missing === `${load}:${round}`) continue;
      const count = load === 'O0' && round === 3 ? miss : 0;
      raw.push([round, load, fys, 0, 2, count, count, count, 'OK', observed, observed].join('\t'));
      remset.push([round, load, fys, 0, 2, count, count, count, 'OK'].join('\t'));
    }
  }
  await write(root, 'raw.tsv', `${rawHeader.join('\t')}\n${raw.join('\n')}\n`);
  await write(root, 'remset.tsv', `${remsetHeader.join('\t')}\n${remset.join('\n')}\n`);
  await bindEvidence(root, 'G14', checkout);
  return root;
}

async function policyCheckout(t, choice) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g14-checkout-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await write(root, 'build/lib/release-manifest.mjs', `export const IDLE_WRITER_POLICY = '${choice}';\n`);
  await write(root, '.github/workflows/release.yml', 'name: release\n');
  for (const args of [
    ['init', '-q'],
    ['add', '.'],
    ['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-q', '-m', 'fixture'],
  ]) {
    const result = spawnSync('git', ['-C', root, ...args], {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr || result.stdout);
  }
  return root;
}

test('FYS_CENSUS accepts a complete bound N20 distribution without imposing the G12 zero floor', async t => {
  const evidence = await evidenceFixture(t, {miss: 108});
  const {result, value} = gate(evidence);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(value.status, 'MET');
  assert.equal(value.choice, 'FYS_CENSUS');
  assert.equal(value.expected_fys, 1);
  assert.deepEqual(value.samples.O0.remsetMiss, {nonzero_runs: 1, sum: 108, max: 108});
});

test('an empty G14 evidence directory is UNKNOWN, not NOT_MET', async t => {
  const evidence = await fs.mkdtemp(path.join(os.tmpdir(), 'g14-empty-'));
  t.after(() => fs.rm(evidence, {recursive: true, force: true}));
  const {result, value} = gate(evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /cannot read/);
});

test('runtime FYS=0 with release choice FYS_CENSUS is NOT_MET', async t => {
  const evidence = await evidenceFixture(t, {observed: 0});
  const {result, value} = gate(evidence);
  assert.equal(result.status, 1, result.stderr);
  assert.equal(value.status, 'NOT_MET');
  assert.match(value.value, /runtime FYS expected=1, mismatched=40\/40/);
});

test('a readable but incomplete N20 distribution is UNKNOWN', async t => {
  const evidence = await evidenceFixture(t, {missing: 'O2:20'});
  const {result, value} = gate(evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /samples=19 unique_rounds=19; expected=20/);
});

test('ZERO_MISS keeps the manifest zero criterion after runtime FYS=0 binding', async t => {
  const checkout = await policyCheckout(t, 'ZERO_MISS');
  const zero = await evidenceFixture(t, {fys: 0, observed: 0, checkout});
  const positive = gate(zero, checkout);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');

  const nonzero = await evidenceFixture(t, {fys: 0, observed: 0, miss: 1, checkout});
  const negative = gate(nonzero, checkout);
  assert.equal(negative.result.status, 1, negative.result.stderr);
  assert.equal(negative.value.status, 'NOT_MET');
  assert.match(negative.value.value, /zero_miss=false/);
});
