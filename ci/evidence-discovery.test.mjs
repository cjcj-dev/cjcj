import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

import {bindEvidence} from './evidence-binding-fixture.mjs';

const command = path.resolve(import.meta.dirname, 'release-gates.mjs');

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function run(root, gate = 'G14') {
  const result = spawnSync(process.execPath, [command, gate, '--repo', root, '--json'], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  return {result, value: JSON.parse(result.stdout)};
}

function git(root, ...args) {
  const result = spawnSync('git', ['-C', root, ...args], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}

function rows() {
  const raw = [];
  const remset = [];
  for (let round = 1; round <= 20; round += 1) {
    for (const load of ['O0', 'O2']) {
      const miss = load === 'O0' && round === 3 ? 108 : 0;
      raw.push([round, load, 1, 0, 2, miss, miss, miss, 'OK', 1, 1].join('\t'));
      remset.push([round, load, 1, 0, 2, miss, miss, miss, 'OK'].join('\t'));
    }
  }
  return {
    raw: [
      'round\tload\tfys\trc\tminors\tmiss\tmissBare\tmissBareNeverSeen\tstatus\tfys_bound\tfallbackFullScan_obs',
      ...raw,
      '',
    ].join('\n'),
    remset: [
      'round\tload\tfys\trc\tminors\tremsetMiss\tmissBare\tmissBareNeverSeen\tstatus',
      ...remset,
      '',
    ].join('\n'),
  };
}

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'evidence-discovery-'));
  const checkout = path.join(root, 'checkout');
  const evidenceRoot = path.join(root, 'release-evidence', '0.0.2');
  const evidence = path.join(evidenceRoot, 'gates', 'G14');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await write(checkout, 'build/lib/release-manifest.mjs', "export const IDLE_WRITER_POLICY = 'FYS_CENSUS';\n");
  await write(checkout, '.github/workflows/release.yml', 'name: release\n');
  await write(checkout, 'ops/coord/RELEASE_0_0_2_RUNBOOK.md',
    `export RELEASE_EVIDENCE_ROOT=${evidenceRoot}\n`);
  git(checkout, 'init', '-q');
  git(checkout, 'add', '.');
  git(checkout, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
    'commit', '-q', '-m', 'fixture');
  const evidenceRows = rows();
  await write(evidence, 'raw.tsv', evidenceRows.raw);
  await write(evidence, 'remset.tsv', evidenceRows.remset);
  const binding = await bindEvidence(evidence, 'G14', checkout);
  await write(evidenceRoot, 'GATE_EVIDENCE.json', `${JSON.stringify({
    schema: 1,
    gates: {G14: 'gates/G14'},
  }, null, 2)}\n`);
  return {checkout, evidenceRoot, evidence, binding};
}

test('default RELEASE_EVIDENCE_ROOT discovery is MET only while its checkout binding matches', async t => {
  const state = await fixture(t);
  const positive = run(state.checkout);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');

  const mismatched = {...state.binding, cjcj_head_sha: 'f'.repeat(40)};
  await write(state.evidence, 'EVIDENCE_BINDING.json', `${JSON.stringify(mismatched, null, 2)}\n`);
  const negative = run(state.checkout);
  assert.equal(negative.result.status, 2, negative.result.stderr);
  assert.equal(negative.value.status, 'UNKNOWN');
  assert.match(negative.value.value, /evidence binding rejected: cjcj_head_sha=.* current=/);
});

test('a payload changed after binding is UNKNOWN', async t => {
  const state = await fixture(t);
  await fs.appendFile(path.join(state.evidence, 'raw.tsv'), '\n');
  const negative = run(state.checkout);
  assert.equal(negative.result.status, 2, negative.result.stderr);
  assert.equal(negative.value.status, 'UNKNOWN');
  assert.match(negative.value.value, /sha256 mismatch for raw\.tsv/);
});

test('a registry path outside RELEASE_EVIDENCE_ROOT is UNKNOWN', async t => {
  const state = await fixture(t);
  await write(state.evidenceRoot, 'GATE_EVIDENCE.json', `${JSON.stringify({
    schema: 1,
    gates: {G14: '../../outside'},
  }, null, 2)}\n`);
  const negative = run(state.checkout);
  assert.equal(negative.result.status, 2, negative.result.stderr);
  assert.equal(negative.value.status, 'UNKNOWN');
  assert.match(negative.value.value, /registry\.gates\.G14 escapes its evidence root/);
});

test('a registry entry that is a symbolic link is UNKNOWN', async t => {
  const state = await fixture(t);
  await fs.symlink('G14', path.join(state.evidenceRoot, 'gates', 'linked-G14'), 'dir');
  await write(state.evidenceRoot, 'GATE_EVIDENCE.json', `${JSON.stringify({
    schema: 1,
    gates: {G14: 'gates/linked-G14'},
  }, null, 2)}\n`);
  const negative = run(state.checkout);
  assert.equal(negative.result.status, 2, negative.result.stderr);
  assert.equal(negative.value.status, 'UNKNOWN');
  assert.match(negative.value.value, /evidence root is not a direct directory/);
});
