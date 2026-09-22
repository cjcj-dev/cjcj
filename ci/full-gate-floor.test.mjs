import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

import {FULL_GATE_FLOOR_FIELDS} from '../build/lib/full-gate-floor-schema.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');
const CJCJ_SHA = 'c'.repeat(40);
const CAMPAIGN_ID = `${CJCJ_SHA}-20260811T130000Z-1`;

async function persistentTestRoot() {
  const configured = process.env.RELEASE_EVIDENCE_TEST_ROOT;
  assert.ok(configured, 'RELEASE_EVIDENCE_TEST_ROOT is required; use a persistent path outside /tmp');
  const root = path.resolve(configured);
  assert.ok(root !== '/tmp' && !root.startsWith('/tmp/'), `test evidence root must not be under /tmp: ${root}`);
  await fs.mkdir(root, {recursive: true});
  return root;
}

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function baseline() {
  return {
    difftest: {total: 20, pass: 20, mismatch: 0, fail: 0},
    smoke: {pass: 6, fail: 0},
    bcgate: {shared: 100, byte_identical: 90, differing: 10, compile_errors: 0},
    verify_exit: 0,
  };
}

function results() {
  return {
    schema: 1,
    campaign_id: CAMPAIGN_ID,
    cjcj_head_sha: CJCJ_SHA,
    captured_utc: '2026-08-11T13:30:00Z',
    results: baseline(),
  };
}

async function fixture(t, {floorSource} = {}) {
  const root = await fs.mkdtemp(path.join(await persistentTestRoot(), 'g8-full-gate-'));
  const checkout = path.join(root, 'cjcj');
  const evidence = path.join(root, 'evidence');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const floor = {
    schema: 1,
    status: 'READY',
    campaign_id: CAMPAIGN_ID,
    cjcj_head_sha: CJCJ_SHA,
    measured_utc: '2026-08-11T13:20:00Z',
    evidence: {results: 'G8_FULL_GATE.json'},
    baseline: baseline(),
  };
  await write(checkout, 'build/lib/full-gate-release-floor.mjs', floorSource
    ?? `export const FULL_GATE_RELEASE_FLOOR = ${JSON.stringify(floor, null, 2)};\n`);
  await fs.mkdir(evidence, {recursive: true});
  return {checkout, evidence};
}

function gate(checkout, evidence = '') {
  const args = [command, 'G8', '--repo', checkout];
  if (evidence) args.push('--evidence', evidence);
  args.push('--json');
  const result = spawnSync(process.execPath, args,
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`G8 output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

test('complete full-gate evidence meeting the READY freeze floor is MET', async t => {
  const state = await fixture(t);
  await write(state.evidence, 'G8_FULL_GATE.json', `${JSON.stringify(results(), null, 2)}\n`);
  const {result, value} = gate(state.checkout, state.evidence);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(value.status, 'MET');
  assert.match(value.value, /difftest=20\/20 mismatch=0 fail=0/);
  assert.match(value.value, /VERIFY-EXIT=0/);
});

test('complete evidence below the READY freeze floor is NOT_MET', async t => {
  const state = await fixture(t);
  const failing = results();
  failing.results.bcgate.differing = 11;
  failing.results.verify_exit = 1;
  await write(state.evidence, 'G8_FULL_GATE.json', `${JSON.stringify(failing, null, 2)}\n`);
  const {result, value} = gate(state.checkout, state.evidence);
  assert.equal(result.status, 1, result.stderr);
  assert.equal(value.status, 'NOT_MET');
  assert.match(value.value, /differing11/);
  assert.match(value.value, /verify_exit=1/);
});

test('evidence with a missing full-gate field is UNKNOWN', async t => {
  const state = await fixture(t);
  const incomplete = results();
  delete incomplete.results.bcgate.compile_errors;
  await write(state.evidence, 'G8_FULL_GATE.json', `${JSON.stringify(incomplete, null, 2)}\n`);
  const {result, value} = gate(state.checkout, state.evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /missing=results\.bcgate\.compile_errors/);
});

test('the repository floor stays PENDING and names every unmeasured value', async t => {
  const floorSource = await fs.readFile(
    path.join(repo, 'build', 'lib', 'full-gate-release-floor.mjs'), 'utf8');
  const state = await fixture(t, {floorSource});
  const {result, value} = gate(state.checkout, state.evidence);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /floor status=PENDING/);
  assert.match(value.value, /baseline\.difftest\.total/);
  assert.match(value.value, /baseline\.bcgate\.compile_errors/);
  assert.match(value.value, /baseline\.verify_exit/);
});

// ci/write-full-gate-floor.mjs is the step that takes the floor out of
// PENDING. These tests drive it against the repository's own PENDING floor and
// then run the real gate over what it wrote, so "the writer produces a floor
// the gate accepts" is measured rather than asserted about the module text.

const writer = path.join(repo, 'ci', 'write-full-gate-floor.mjs');
const floorModule = ['build', 'lib', 'full-gate-release-floor.mjs'];

async function pendingFixture(t) {
  const floorSource = await fs.readFile(path.join(repo, ...floorModule), 'utf8');
  const state = await fixture(t, {floorSource});
  return {...state, floor: path.join(state.checkout, ...floorModule)};
}

async function writeResults(state, value = results()) {
  const file = path.join(state.checkout, 'G8_FULL_GATE.json');
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
  return file;
}

function runWriter(state, resultsFile, extra = []) {
  return spawnSync(process.execPath,
    [writer, '--results', resultsFile, '--out', state.floor, ...extra],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
}

function missingFields(value) {
  const list = value.match(/missing=([^；]+)/)?.[1];
  assert.ok(list, `gate value has no missing= list: ${value}`);
  return list.split(',');
}

test('the writer turns the PENDING floor into a READY floor the gate accepts', async t => {
  const state = await pendingFixture(t);
  const before = gate(state.checkout, state.evidence);
  assert.equal(before.value.status, 'UNKNOWN');
  assert.match(before.value.value, /floor status=PENDING/);

  const resultsFile = await writeResults(state);
  const written = runWriter(state, resultsFile);
  assert.equal(written.status, 0, written.stderr);
  assert.match(written.stdout, /^STATUS=READY$/m);
  assert.match(written.stdout, new RegExp(`^CAMPAIGN_ID=${CAMPAIGN_ID}$`, 'm'));

  await write(state.evidence, 'G8_FULL_GATE.json', `${JSON.stringify(results(), null, 2)}\n`);
  const after = gate(state.checkout, state.evidence);
  assert.equal(after.result.status, 0, after.result.stderr);
  assert.equal(after.value.status, 'MET');
  assert.doesNotMatch(after.value.value, /missing=/);
  assert.doesNotMatch(after.value.value, /status=PENDING/);
});

test('the writer refuses an incomplete measurement set, names the field, and leaves the floor PENDING', async t => {
  const state = await pendingFixture(t);
  const before = await fs.readFile(state.floor, 'utf8');
  const incomplete = results();
  delete incomplete.results.smoke.fail;
  delete incomplete.results.bcgate.compile_errors;
  const refused = runWriter(state, await writeResults(state, incomplete));
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /FULL_GATE_FLOOR_REFUSED/);
  assert.match(refused.stderr, /missing=baseline\.smoke\.fail,baseline\.bcgate\.compile_errors/);
  assert.equal(await fs.readFile(state.floor, 'utf8'), before);
  assert.equal(gate(state.checkout, state.evidence).value.status, 'UNKNOWN');
});

test('the writer refuses values that cannot be a measurement and leaves the floor PENDING', async t => {
  const state = await pendingFixture(t);
  const before = await fs.readFile(state.floor, 'utf8');
  const impossible = results();
  impossible.results.difftest.total = -1;
  impossible.results.smoke.pass = 6.5;
  impossible.cjcj_head_sha = 'not-a-sha';
  const refused = runWriter(state, await writeResults(state, impossible));
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /invalid=cjcj_head_sha=not-a-sha/);
  assert.match(refused.stderr, /baseline\.difftest\.total=-1/);
  assert.match(refused.stderr, /baseline\.smoke\.pass=6\.5/);
  assert.equal(await fs.readFile(state.floor, 'utf8'), before);
});

test('the writer refuses a campaign id that does not bind the frozen head', async t => {
  const state = await pendingFixture(t);
  const unbound = results();
  unbound.campaign_id = `${'e'.repeat(40)}-20260811T130000Z-1`;
  const refused = runWriter(state, await writeResults(state, unbound));
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /does not bind cjcj_head_sha/);
});

test('the writer refuses to re-baseline a READY floor from another campaign without --replace', async t => {
  const state = await pendingFixture(t);
  assert.equal(runWriter(state, await writeResults(state)).status, 0);
  const second = results();
  second.campaign_id = `${'f'.repeat(40)}-20260812T130000Z-1`;
  second.cjcj_head_sha = 'f'.repeat(40);
  const secondFile = await writeResults(state, second);
  const refused = runWriter(state, secondFile);
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, new RegExp(`already carries READY floor ${CAMPAIGN_ID}`));
  const replaced = runWriter(state, secondFile, ['--replace']);
  assert.equal(replaced.status, 0, replaced.stderr);
  assert.match(replaced.stdout, new RegExp(`^CAMPAIGN_ID=${second.campaign_id}$`, 'm'));
});

test('the writer requires exactly the fields the G8 gate reports missing', async t => {
  const state = await pendingFixture(t);
  const reported = missingFields(gate(state.checkout, state.evidence).value.value);
  assert.equal(reported[0], 'status=READY');
  assert.deepEqual(reported.slice(1), [...FULL_GATE_FLOOR_FIELDS]);
});
