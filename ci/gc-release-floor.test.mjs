import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {GC_RELEASE_FLOOR} from '../build/lib/gc-release-floor.mjs';
import {observeRun} from '../build/lib/gc-campaign.mjs';
import {campaignFixture, rebind, gcLog, stdoutLog} from './gc-campaign-fixture.mjs';
const repo = path.resolve(import.meta.dirname, '..');
const gate = root => {
  const r = spawnSync(process.execPath, [path.join(repo, 'ci/release-gates.mjs'), 'G12', '--repo', repo, '--evidence', root, '--json'], {encoding: 'utf8'});
  return {rc: r.status, ...JSON.parse(r.stdout)};
};
async function fixture(t, mutate) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g12-v2-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await campaignFixture(root, 'G12', repo, mutate);
  return root;
}
test('single-profile floor removes retired mechanisms and retains four blockers', () => {
  assert.deepEqual(GC_RELEASE_FLOOR.blocking.map(x => x.id), ['F1', 'F2', 'F3', 'F4']);
  assert.deepEqual(GC_RELEASE_FLOOR.recording.map(x => x.id), ['R1', 'R2', 'R4']);
});
test('G12 raw evidence recomputes all four blockers and nanosecond records', async t => {
  const result = gate(await fixture(t));
  assert.equal(result.rc, 0, JSON.stringify(result));
  assert.deepEqual(result.checks.map(x => x.status), Array(4).fill('MET'));
  assert.equal(result.records[1].value.median, 2);
  assert.equal(result.records[2].value.liveBytes.max, 10);
});
for (const target of ['F1', 'F2', 'F3', 'F4']) {
  test(`G12 ${target} target invariant is executed and rejects its single mutation`, async t => {
    const root = await fixture(t, data => {
      if (data.receipt.round !== 1 || data.receipt.mode !== 'verify') return;
      if (target === 'F1') data.stdout = data.stdout.replaceAll('635925223159200', '1');
      if (target === 'F2') data.log = data.log.replace('run=1 ', 'run=2 ');
      if (target === 'F3') data.log += 'Missing remembered field at 0x100\n';
      if (target === 'F4') data.log = data.log.split('\n').filter(l => !l.includes('name=Pause_Mark_End')).join('\n');
    });
    const result = gate(root);
    assert.equal(result.rc, 1, JSON.stringify(result));
    assert.deepEqual(result.checks.filter(x => x.status !== 'MET').map(x => x.id), [target]);
    console.log(`TARGET_ASSERTION_EXECUTED ${target}`);
  });
}
test('zero aborts without an aborting remembered positive control are UNKNOWN', async t => {
  const root = await fixture(t, data => { if (data.receipt.mode === 'control') data.receipt.rc = 124; });
  const result = gate(root);
  assert.equal(result.rc, 2);
  assert.equal(result.checks[2].status, 'UNKNOWN');
});
test('missing LOADAVG_END is rejected after rebinding, at the metadata assertion', async t => {
  const root = await fixture(t);
  const file = path.join(root, 'meta.txt');
  await fs.writeFile(file, (await fs.readFile(file, 'utf8')).replace(/^LOADAVG_END=.*\n/m, ''));
  await rebind(root, 'G12', repo);
  const result = gate(root);
  assert.equal(result.rc, 2);
  assert.match(result.value, /missing LOADAVG_END/);
  console.log('TARGET_ASSERTION_EXECUTED LOADAVG_END');
});
test('TSV tampering cannot substitute for raw process output', async t => {
  const root = await fixture(t);
  await fs.appendFile(path.join(root, 'runs.tsv'), '\n');
  await rebind(root, 'G12', repo);
  const result = gate(root);
  assert.equal(result.rc, 2);
  assert.match(result.value, /runs.tsv: summary disagrees/);
});
test('every producer payload is required by the archive binding', async t => {
  const root = await fixture(t);
  const binding = JSON.parse(await fs.readFile(path.join(root, 'EVIDENCE_BINDING.json'), 'utf8'));
  const files = [...Object.keys(binding.payload_sha256), 'EVIDENCE_BINDING.json'];
  for (const file of files) {
    const full = path.join(root, file), saved = await fs.readFile(full);
    await fs.unlink(full);
    const result = gate(root);
    await fs.writeFile(full, saved);
    assert.equal(result.rc, 2, `${file}: ${JSON.stringify(result)}`);
  }
  assert.equal(gate(root).rc, 0);
  console.log(`TARGET_ASSERTION_EXECUTED missing-payload N=${files.length}`);
});
test('old generation and wrong-scope mark-end cannot satisfy young completion', () => {
  const log = gcLog().replace('gc_tag=y name=Pause_Mark_End', 'gc_tag=O name=Pause_Mark_End');
  assert.equal(observeRun(stdoutLog(), log).completed, 0);
});
test('major preclean permits two completed young generations with one sequence', () => {
  const first = gcLog().replaceAll('gc_tag=y', 'gc_tag=Y');
  const second = first.replace('run=1 ', 'run=2 ');
  const observed = observeRun(stdoutLog(), first + second);
  assert.equal(observed.generations, 2);
  assert.equal(observed.completed, 2);
  assert.equal(observed.minorSequence, true);
});
test('archived G12 schema 1 raw log is rejected, never backfilled with zero counters', async () => {
  const legacy = await fs.readFile(path.join(repo, 'ci/release/fixtures/g12-legacy-gc.txt'), 'utf8');
  assert.throws(() => observeRun('', legacy), /unsupported GCLOG schema 1/);
});
