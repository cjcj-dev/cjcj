import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

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
