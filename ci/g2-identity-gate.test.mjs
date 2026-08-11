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
