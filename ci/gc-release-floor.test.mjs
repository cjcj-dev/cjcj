import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

import {GC_RELEASE_FLOOR} from '../build/lib/gc-release-floor.mjs';
import {bindEvidence} from './evidence-binding-fixture.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');
const WORKLOAD_SHA = 'e75cdefd2a3d92e7d4e15d44d89ac7a2cb2167f035be44685c7cdd2ad1f4226a';
const RUNTIME_SHA = '0657e70329e4e8f725c2b276ca6aa1223905015ec661615fba19e9e39634b1ea';
const RUNTIME_COMMIT = 'e3d93add5a6ade686fa3a78093c2222aa0c63e98';

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function gate(evidence) {
  const result = spawnSync(process.execPath,
    [command, 'G12', '--repo', repo, '--evidence', evidence, '--json'],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`G12 output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

function runRows(failing) {
  const header = [
    'round', 'arm', 'load', 'rc', 'wall_s', 'class', 'si_code', 'si_addr', 'pc_bucket', 'insn',
    'minor', 'major', 'collected_mib', 'fwd_empty', 'reject', 'checksum', 'wave_done',
  ];
  const rows = [];
  for (let round = 1; round <= 20; round += 1) {
    for (const arm of ['DEFAULT', 'FYS0']) {
      for (const load of ['nw_e75', 'hello_alloc']) {
        const fail = (failing === 'F1' && arm === 'DEFAULT' && load === 'nw_e75' && round === 1) ||
          (failing === 'F2' && arm === 'DEFAULT' && load === 'hello_alloc' && round === 1);
        rows.push([
          round, arm, load, fail ? 139 : 0, load === 'nw_e75' ? '9.372' : '0.085', fail ? 'SEGV' : 'OK',
          fail ? 1 : '-', fail ? '0x10' : '-', fail ? 'CJ_MCC_ReadRefField' : '-', '-',
          load === 'nw_e75' ? 9 : 1, 0, load === 'nw_e75' ? 136.5 : 20, load === 'nw_e75' ? 199 : 13,
          0, load === 'nw_e75' ? '635925223159200' : '-', load === 'nw_e75' ? 12 : 0,
        ].join('\t'));
      }
    }
  }
  return `${header.join('\t')}\n${rows.join('\n')}\n`;
}

function f3Log(total = 0) {
  return Array.from({length: 20}, (_, index) =>
    `[GCV2][f3-deadarm] point=atexit total=${index === 0 ? total : 0} soft_null=${index === 0 ? total : 0} ` +
      `region_garbage=${index === 0 ? total : 0} region_free=0 invalid_object_active_region=0 ` +
      'unknown=0 class_sum_ok=1 env_assert=0').join('\n') + '\n';
}

function markSurvivalLog(count) {
  return Array.from({length: count}, (_, index) =>
    `2026-08-11 10:03:08.696346 281286 E [GCV2][nullslot][edgemiss] n=${index + 1} ` +
      'fromHaveMark=1 mBit=1 f3Bit=0 sameLive=1 sameBm=1 sameWord=1 sameReg=1').join('\n') +
    (count ? '\n' : '');
}

const REMSET_HEADER = [
  'round', 'load', 'fys', 'rc', 'wall_s', 'load_begin', 'minors', 'edges', 'hit', 'miss', 'missPct',
  'missBare', 'missBareNeverSeen', 'missBareDisplaced', 'missLe8', 'missGt8', 'missRecLost', 'missEarly',
  'perMinorMiss', 'remsetSizeHint', 'status', 'nonzero_minors', 'max_miss_minor', 'med_miss_minor',
  'checksum', 'bare_type', 'bare_off', 'census_log',
];

function remsetRow({round, load, fys, miss}) {
  const edges = 10560;
  const values = {
    round, load, fys, rc: 0, wall_s: '7.8', load_begin: '14.80', minors: 5, edges,
    hit: edges - miss, miss, missPct: miss ? '40.00' : '0.00', missBare: miss,
    missBareNeverSeen: miss, missBareDisplaced: 0, missLe8: 0, missGt8: 0, missRecLost: 0,
    missEarly: 0, perMinorMiss: miss / 5, remsetSizeHint: load === 'O0' ? 2628 : 2112,
    status: 'OK', nonzero_minors: miss ? 1 : 0, max_miss_minor: miss, med_miss_minor: 0,
    checksum: '635925223159200', bare_type: '', bare_off: '', census_log: '',
  };
  return REMSET_HEADER.map(name => values[name]).join('\t');
}

function remsetRows(failing, positiveControls) {
  const rows = [];
  if (positiveControls) {
    rows.push(remsetRow({round: 0, load: 'CTRL', fys: 1, miss: 4224}));
    rows.push(remsetRow({round: 0, load: 'CTRL', fys: 0, miss: 4224}));
  }
  for (let round = 1; round <= 20; round += 1) {
    for (const fys of [1, 0]) {
      for (const load of ['O0', 'O2']) {
        const miss = failing === 'F5' && fys === 1 && load === 'O0' && round === 1 ? 237 :
          failing === 'F6' && fys === 0 && load === 'O0' && round === 1 ? 88 : 0;
        rows.push(remsetRow({round, load, fys, miss}));
      }
    }
  }
  return `${REMSET_HEADER.join('\t')}\n${rows.join('\n')}\n`;
}

function throughputRows() {
  const header = ['round', 'arm', 'rc', 'task_ms', 'wall_s', 'minor', 'major', 'gc_starts', 'checksum', 'status'];
  const rows = [];
  for (let round = 1; round <= 20; round += 1) {
    rows.push([round, 'A', 0, '8187.17', '6.377', 7, 6, 13, '635925223159200', 'OK'].join('\t'));
    rows.push([round, 'B', 0, '1691.02', '1.092', 0, 3, 3, '635925223159200', 'OK'].join('\t'));
  }
  return `${header.join('\t')}\n${rows.join('\n')}\n`;
}

function phaseLog() {
  return [
    '2026-08-05 20:14:15.683115 537047 [GCLOG] v=1 rec=phase seq=2 name=young.mark_closure us=42012',
    '2026-08-05 20:14:15.721468 537047 [GCLOG] v=1 rec=phase seq=2 name=young.ref_fix us=30264',
    '2026-08-05 20:14:15.742160 537047 [GCLOG] v=1 rec=phase seq=2 name=young.copy us=20686',
    '2026-08-05 20:14:15.744166 537047 [GCLOG] v=1 rec=phase seq=2 name=young.evac_finish us=2001',
    'young collection stw time: 103,437us',
    '',
  ].join('\n');
}

async function evidenceFixture(t, {failing = '', positiveControls = true, verdict = ''} = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g12-floor-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await write(root, 'meta.txt', [
    '=== INTERLEAVE START 2026-08-11T08:19:12+08:00 ===',
    `${RUNTIME_SHA}  /root/g12/so/libcangjie-runtime.so`,
    `${WORKLOAD_SHA}  /root/g12/bin/natural_wave_notime.O0.e75cdefd`,
    `CJRT-COMMIT:${RUNTIME_COMMIT}`,
    'HEAP=256MB N=20 CORES=0-31',
    verdict,
    '=== INTERLEAVE DONE 2026-08-11T08:22:23+08:00 ===',
    '',
  ].join('\n'));
  await write(root, 'runs.tsv', runRows(failing));
  await write(root, 'remset.tsv', remsetRows(failing, positiveControls));
  await write(root, 'throughput.tsv', throughputRows());
  await write(root, 'gc.log', phaseLog());
  await write(root, 'default/f3.log', f3Log(failing === 'F3' ? 194 : 0));
  await write(root, 'default/f3-control.log', positiveControls ? f3Log(194) : '');
  await write(root, 'default/marksurvive.log', markSurvivalLog(failing === 'F4' ? 79 : 0));
  await write(root, 'default/marksurvive-control.log', positiveControls ? markSurvivalLog(79) : '');
  await write(root, 'fys0/f3.log', f3Log(0));
  await write(root, 'fys0/f3-control.log', positiveControls ? f3Log(194) : '');
  await write(root, 'fys0/marksurvive.log', markSurvivalLog(0));
  await write(root, 'fys0/marksurvive-control.log', positiveControls ? markSurvivalLog(79) : '');
  await bindEvidence(root, 'G12', repo);
  return root;
}

test('the frozen floor contains six blockers and four recording items', () => {
  assert.deepEqual(GC_RELEASE_FLOOR.blocking.map(item => item.id), ['F1', 'F2', 'F3', 'F4', 'F5', 'F6']);
  assert.deepEqual(GC_RELEASE_FLOOR.recording.map(item => item.id), ['R1', 'R2', 'R3', 'R4']);
  assert.equal(GC_RELEASE_FLOOR.measurement.runs, 20);
  assert.equal(GC_RELEASE_FLOOR.measurement.heap_mib, 256);
  assert.equal(GC_RELEASE_FLOOR.measurement.workload_sha8, 'e75cdefd');
  for (const id of ['F3', 'F4', 'F5']) {
    const criterion = GC_RELEASE_FLOOR.blocking.find(item => item.id === id);
    assert.equal(criterion.maximum_count, 0);
    assert.equal(criterion.positive_control_minimum, 1);
  }
});

test('complete recomputed evidence is MET and carries all four records', async t => {
  const evidence = await evidenceFixture(t);
  const {result, value} = gate(evidence);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(value.status, 'MET');
  assert.deepEqual(value.checks.map(item => item.status), Array(6).fill('MET'));
  assert.deepEqual(value.records.map(item => item.id), ['R1', 'R2', 'R3', 'R4']);
});

for (const id of ['F1', 'F2', 'F3', 'F4', 'F5', 'F6']) {
  test(`complete negative control for ${id} is NOT_MET`, async t => {
    const evidence = await evidenceFixture(t, {failing: id});
    const {result, value} = gate(evidence);
    assert.equal(result.status, 1, result.stderr);
    assert.equal(value.status, 'NOT_MET');
    assert.equal(value.checks.find(item => item.id === id).status, 'NOT_MET');
  });
}

test('an unreadable evidence path is UNKNOWN, not NOT_MET', () => {
  const missing = path.join(os.tmpdir(), `g12-missing-${process.pid}`);
  const {result, value} = gate(missing);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /cannot read/);
});

test('a parse failure is UNKNOWN, not NOT_MET', async t => {
  const evidence = await evidenceFixture(t);
  await write(evidence, 'runs.tsv', 'not\ta\tknown\theader\n1\t2\t3\t4\n');
  await bindEvidence(evidence, 'G12', repo);
  const {result, value} = gate(evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /lacks columns/);
});

test('all-zero counters without positive controls are UNKNOWN', async t => {
  const evidence = await evidenceFixture(t, {positiveControls: false});
  const {result, value} = gate(evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.equal(value.checks.find(item => item.id === 'F3').status, 'UNKNOWN');
  assert.equal(value.checks.find(item => item.id === 'F4').status, 'UNKNOWN');
  assert.equal(value.checks.find(item => item.id === 'F5').status, 'UNKNOWN');
});

test('human verdict strings are ignored by the integer computation', async t => {
  const evidence = await evidenceFixture(t, {verdict: 'VERDICT=NOT_MET'});
  const {result, value} = gate(evidence);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(value.status, 'MET');
});
