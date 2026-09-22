import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');
const LLVM_SHA = 'b'.repeat(40);
const CJCJ_SHA = 'c'.repeat(40);
const STD_SHA = 'd'.repeat(40);
const CAMPAIGN_ID = `${CJCJ_SHA}-20260811T120000Z-1`;
const ARTIFACT_NAMES = [
  'runtime_dynamic',
  'runtime_static',
  'llvm_llc',
  'llvm_opt',
  'cjcj',
  'std',
];

function run(program, args, options = {}) {
  return spawnSync(program, args, {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...options});
}

function git(root, ...args) {
  const result = run('git', ['-C', root, ...args]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function commit(root, message) {
  git(root, 'add', '.');
  git(root, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', message);
  return git(root, 'rev-parse', 'HEAD');
}

function identity(runtimeSha) {
  const commits = {
    runtime_dynamic: runtimeSha,
    runtime_static: runtimeSha,
    llvm_llc: LLVM_SHA,
    llvm_opt: LLVM_SHA,
    cjcj: CJCJ_SHA,
    std: STD_SHA,
  };
  const prefixes = {
    runtime_dynamic: 'CJRT-COMMIT',
    runtime_static: 'CJRT-COMMIT',
    llvm_llc: 'CJLLVM-COMMIT',
    llvm_opt: 'CJLLVM-COMMIT',
    cjcj: 'CJCJ-COMMIT',
    std: 'CJSTD-COMMIT',
  };
  return {
    schema_version: 1,
    campaign_id: CAMPAIGN_ID,
    cjcj_head_sha: CJCJ_SHA,
    captured_utc: '2026-08-11T12:30:00Z',
    status: 'READY',
    artifacts: Object.fromEntries(ARTIFACT_NAMES.map((name, index) => [name, {
      artifact_path: `/synthetic/${name}`,
      sha256: String(index + 1).repeat(64),
      provenance_stamp: `${prefixes[name]}:${commits[name]}`,
      source_commit: commits[name],
      source_dirty: false,
    }])),
  };
}

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g2-identity-gate-'));
  const checkout = path.join(root, 'cjcj');
  const runtime = path.join(root, 'runtime');
  const campaign = path.join(root, 'campaign');
  const archive = path.join(campaign, 'archive');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await fs.mkdir(checkout, {recursive: true});
  await fs.mkdir(runtime, {recursive: true});
  await fs.mkdir(archive, {recursive: true});

  git(runtime, 'init', '-q');
  await write(runtime, 'history.txt', 'loaderlife\n');
  const loaderlife = commit(runtime, 'loaderlife');
  await fs.appendFile(path.join(runtime, 'history.txt'), 'release pin\n');
  const runtimePin = commit(runtime, 'release pin');

  await write(checkout, 'ci/runtime_pin.env', [
    `RUNTIME_REF=${runtimePin}`,
    `LOADERLIFE_MIN_REF=${loaderlife}`,
    '',
  ].join('\n'));
  await write(checkout, 'ci/llvm_pin.env', `LLVM_SHA=${LLVM_SHA}\n`);
  await write(checkout, 'ci/source_pin.env', '# unused\n');
  await write(checkout, 'ci/cjpm_pin.env', '# unused\n');
  await fs.mkdir(path.join(checkout, 'ci', 'release-evidence'), {recursive: true});
  await fs.copyFile(path.join(repo, 'ci', 'release-evidence', 'g2-identity.schema.json'),
    path.join(checkout, 'ci', 'release-evidence', 'g2-identity.schema.json'));
  await write(checkout, 'scripts/archive_release_evidence.mjs', [
    "if (process.argv[2] !== 'verify' || process.argv[3] !== '--archive') process.exit(9);",
    "console.log('ARCHIVE_EVIDENCE_OK synthetic fixture');",
    '',
  ].join('\n'));
  await write(archive, 'run.json', `${JSON.stringify({head_sha: CJCJ_SHA})}\n`);
  return {archive, campaign, checkout, runtime, runtimePin};
}

function gate(state) {
  const result = run(process.execPath, [
    command,
    'G2',
    '--repo', state.checkout,
    '--runtime-repo', state.runtime,
    '--evidence', state.archive,
    '--json',
  ]);
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`G2 output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

async function writeIdentity(state, value) {
  await write(state.campaign, 'G2_IDENTITY.json', `${JSON.stringify(value, null, 2)}\n`);
}

test('complete clean READY identity is MET after archive verification', async t => {
  const state = await fixture(t);
  await writeIdentity(state, identity(state.runtimePin));
  const {result, value} = gate(state);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(value.status, 'MET');
  assert.match(value.value, /six slots schema-complete, clean, stamped/);
});

test('complete dirty READY identity is NOT_MET', async t => {
  const state = await fixture(t);
  const dirty = identity(state.runtimePin);
  dirty.artifacts.runtime_static.source_dirty = true;
  dirty.artifacts.runtime_static.provenance_stamp += '-dirty';
  await writeIdentity(state, dirty);
  const {result, value} = gate(state);
  assert.equal(result.status, 1, result.stderr);
  assert.equal(value.status, 'NOT_MET');
  assert.match(value.value, /runtime_static\.source_dirty=true/);
});

test('READY identity with a missing slot field is UNKNOWN', async t => {
  const state = await fixture(t);
  const incomplete = identity(state.runtimePin);
  delete incomplete.artifacts.std.sha256;
  await writeIdentity(state, incomplete);
  const {result, value} = gate(state);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /missing=artifacts\.std\.sha256/);
});

test('generated PENDING identity names every unavailable field and stays UNKNOWN', async t => {
  const state = await fixture(t);
  const pending = identity(state.runtimePin);
  pending.status = 'PENDING';
  pending.captured_utc = null;
  for (const artifact of Object.values(pending.artifacts)) {
    for (const field of Object.keys(artifact)) artifact[field] = null;
  }
  await writeIdentity(state, pending);
  const {result, value} = gate(state);
  assert.equal(result.status, 2, result.stderr);
  assert.equal(value.status, 'UNKNOWN');
  assert.match(value.value, /status=PENDING/);
  assert.match(value.value, /artifacts\.runtime_dynamic\.artifact_path/);
  assert.match(value.value, /artifacts\.std\.source_dirty/);
});

// ci/capture-g2-identity.mjs is the step that fills the skeleton. These tests
// drive it end to end against the same fixture the gate tests use: capture
// first, then the real gate, so "the capture writes a record the gate accepts"
// is measured rather than asserted about the JSON shape alone.

const capture = path.join(repo, 'ci', 'capture-g2-identity.mjs');
const STAMP_PREFIXES = Object.freeze({
  runtime_dynamic: 'CJRT-COMMIT',
  runtime_static: 'CJRT-COMMIT',
  llvm_llc: 'CJLLVM-COMMIT',
  llvm_opt: 'CJLLVM-COMMIT',
  cjcj: 'CJCJ-COMMIT',
  std: 'CJSTD-COMMIT',
});

// The record ci/generate-freeze.mjs writes: six slots of nulls, status PENDING.
function skeleton() {
  return {
    schema_version: 1,
    campaign_id: CAMPAIGN_ID,
    cjcj_head_sha: CJCJ_SHA,
    captured_utc: null,
    status: 'PENDING',
    artifacts: Object.fromEntries(ARTIFACT_NAMES.map(name => [name, {
      artifact_path: null,
      sha256: null,
      provenance_stamp: null,
      source_commit: null,
      source_dirty: null,
    }])),
  };
}

async function stampedArtifact(root, name, stampValue) {
  const file = path.join(root, name);
  await fs.mkdir(root, {recursive: true});
  await fs.writeFile(file, Buffer.concat([
    Buffer.from(`${name}-payload`, 'ascii'),
    Buffer.from(`\0${STAMP_PREFIXES[name]}:${stampValue}\0`, 'ascii'),
    Buffer.from('trailing-bytes', 'ascii'),
  ]));
  return file;
}

// Six artifacts stamped with the commits the fixture pins expect.
async function artifactSet(state, {overrides = {}} = {}) {
  const commits = {
    runtime_dynamic: state.runtimePin,
    runtime_static: state.runtimePin,
    llvm_llc: LLVM_SHA,
    llvm_opt: LLVM_SHA,
    cjcj: CJCJ_SHA,
    std: STD_SHA,
    ...overrides,
  };
  const root = path.join(state.campaign, 'artifacts');
  const files = {};
  for (const name of ARTIFACT_NAMES) files[name] = await stampedArtifact(root, name, commits[name]);
  return files;
}

function captureArguments(state, files, extra = []) {
  const args = [capture, '--identity', path.join(state.campaign, 'G2_IDENTITY.json')];
  for (const name of ARTIFACT_NAMES) {
    if (files[name] === undefined) continue;
    args.push(`--${name.replaceAll('_', '-')}`, files[name]);
  }
  return [...args, ...extra];
}

function runCapture(state, files, extra = []) {
  return run(process.execPath, captureArguments(state, files, extra));
}

async function readIdentity(state) {
  return JSON.parse(await fs.readFile(path.join(state.campaign, 'G2_IDENTITY.json'), 'utf8'));
}

test('capture fills the generated skeleton and the gate accepts the result', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const before = gate(state);
  assert.equal(before.value.status, 'UNKNOWN');
  assert.match(before.value.value, /status=PENDING/);
  for (const name of ARTIFACT_NAMES) {
    assert.match(before.value.value, new RegExp(`artifacts\\.${name}\\.sha256`));
  }

  const files = await artifactSet(state);
  const captured = runCapture(state, files);
  assert.equal(captured.status, 0, captured.stderr);
  assert.match(captured.stdout, /^STATUS=READY$/m);

  const identity = await readIdentity(state);
  assert.equal(identity.status, 'READY');
  assert.match(identity.captured_utc, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  assert.equal(identity.campaign_id, CAMPAIGN_ID);
  for (const name of ARTIFACT_NAMES) {
    const slot = identity.artifacts[name];
    assert.equal(slot.artifact_path, files[name]);
    assert.match(slot.sha256, /^[0-9a-f]{64}$/);
    assert.equal(slot.source_dirty, false);
    assert.match(slot.provenance_stamp, new RegExp(`^${STAMP_PREFIXES[name]}:[0-9a-f]{40}$`));
  }

  const after = gate(state);
  assert.equal(after.result.status, 0, after.result.stderr);
  assert.equal(after.value.status, 'MET');
  assert.doesNotMatch(after.value.value, /missing=/);
  assert.match(after.value.value, /six slots schema-complete, clean, stamped/);
});

test('capture cross-checks a supplied source checkout and rejects a stamp that disagrees with its HEAD', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const files = await artifactSet(state);
  const agreeing = runCapture(state, files, ['--runtime-repo', state.runtime]);
  assert.equal(agreeing.status, 0, agreeing.stderr);
  const identity = await readIdentity(state);
  assert.equal(identity.artifacts.runtime_dynamic.source_commit, state.runtimePin);

  await writeIdentity(state, skeleton());
  const stale = await artifactSet(state, {overrides: {runtime_static: 'a'.repeat(40)}});
  const disagreeing = run(process.execPath, captureArguments(state, stale, ['--runtime-repo', state.runtime]));
  assert.equal(disagreeing.status, 1, disagreeing.stdout);
  assert.match(disagreeing.stderr, /runtime_static: CJRT-COMMIT:a{40} does not match .* HEAD/);
  assert.equal((await readIdentity(state)).status, 'PENDING');
});

test('capture refuses a slot whose artifact is absent and leaves the record PENDING', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const files = await artifactSet(state);
  await fs.rm(files.llvm_opt);
  const refused = runCapture(state, files);
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /G2_IDENTITY_CAPTURE_REFUSED/);
  assert.match(refused.stderr, /llvm_opt: artifact is unreadable/);
  assert.doesNotMatch(refused.stderr, /llvm_llc:/);
  const identity = await readIdentity(state);
  assert.equal(identity.status, 'PENDING');
  assert.equal(identity.artifacts.llvm_llc.sha256, null);
  assert.equal(gate(state).value.status, 'UNKNOWN');
});

test('capture refuses when a slot argument is omitted and names exactly that slot', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const files = await artifactSet(state);
  delete files.std;
  const refused = runCapture(state, files);
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /std: --std was not supplied/);
  assert.doesNotMatch(refused.stderr, /cjcj: --cjcj was not supplied/);
  assert.equal((await readIdentity(state)).status, 'PENDING');
});

test('capture refuses an artifact that carries no lineage stamp', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const files = await artifactSet(state);
  await fs.writeFile(files.cjcj, 'a compiler nobody stamped\n');
  const refused = runCapture(state, files);
  assert.equal(refused.status, 1, refused.stdout);
  assert.match(refused.stderr, /cjcj: CJCJ-COMMIT occurrence must be exactly 1 .*actual count=0/);
  assert.equal((await readIdentity(state)).status, 'PENDING');
});

test('capture records a dirty build truthfully instead of laundering it', async t => {
  const state = await fixture(t);
  await writeIdentity(state, skeleton());
  const files = await artifactSet(state, {overrides: {std: `${STD_SHA}-dirty`}});
  const captured = runCapture(state, files);
  assert.equal(captured.status, 0, captured.stderr);
  const identity = await readIdentity(state);
  assert.equal(identity.artifacts.std.source_dirty, true);
  assert.equal(identity.artifacts.std.source_commit, STD_SHA);
  assert.equal(identity.artifacts.std.provenance_stamp, `CJSTD-COMMIT:${STD_SHA}-dirty`);
  const {result, value} = gate(state);
  assert.equal(result.status, 1, result.stderr);
  assert.equal(value.status, 'NOT_MET');
  assert.match(value.value, /std\.source_dirty=true/);
});
