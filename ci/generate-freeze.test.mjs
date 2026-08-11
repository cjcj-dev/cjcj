import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '..');
const generator = path.join(repo, 'ci', 'generate-freeze.mjs');
const gateCommand = path.join(repo, 'ci', 'release-gates.mjs');
const PIN_FILES = [
  'ci/runtime_pin.env',
  'ci/llvm_pin.env',
  'ci/source_pin.env',
  'ci/cjpm_pin.env',
];
const G2_ARTIFACTS = [
  'runtime_dynamic',
  'runtime_static',
  'llvm_llc',
  'llvm_opt',
  'cjcj',
  'std',
];

function run(program, args, options = {}) {
  return spawnSync(program, args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
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
  return file;
}

function commit(root, message) {
  git(root, 'add', '.');
  git(root, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
    'commit', '-q', '-m', message);
  return git(root, 'rev-parse', 'HEAD');
}

async function fixture(root) {
  const checkout = path.join(root, 'cjcj');
  await fs.mkdir(checkout);
  git(checkout, 'init', '-q');
  git(checkout, 'remote', 'add', 'origin', 'https://github.com/cjcj-dev/cjcj.git');
  for (const relative of [
    ...PIN_FILES,
    'ops/design/DRYRUN_EXECUTION_POLICY.md',
    '.github/workflows/release.yml',
  ]) {
    await write(checkout, relative, await fs.readFile(path.join(repo, relative), 'utf8'));
  }
  const baseSdk = await write(checkout, 'fixture/base-sdk.tar.gz', 'fixture base SDK bytes\n');
  const head = commit(checkout, 'fixture release state');
  return {baseSdk, checkout, head};
}

function generate(checkout, evidenceRoot, baseSdk, sequence, approvalRecord = '') {
  const args = [
    generator,
    '--repo', checkout,
    '--evidence-root', evidenceRoot,
    '--base-sdk', baseSdk,
    '--sequence', String(sequence),
  ];
  if (approvalRecord) args.push('--approval-record', approvalRecord);
  const result = run(process.execPath, args);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const freezeFile = result.stdout.match(/^FREEZE_JSON=(.+)$/m)?.[1];
  const g2IdentityFile = result.stdout.match(/^G2_IDENTITY=(.+)$/m)?.[1];
  assert.ok(freezeFile, `generator omitted FREEZE_JSON:\n${result.stdout}`);
  assert.ok(g2IdentityFile, `generator omitted G2_IDENTITY:\n${result.stdout}`);
  return {freezeFile, g2IdentityFile, output: result.stdout};
}

function g1(checkout, freezeFile) {
  const result = run(process.execPath, [
    gateCommand,
    'G1',
    '--repo', checkout,
    '--freeze', freezeFile,
    '--json',
  ]);
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`G1 output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

async function copyWithApproval(source, destination, approval) {
  const freeze = JSON.parse(await fs.readFile(source, 'utf8'));
  freeze.approval.user_instruction_or_record_id = approval;
  await fs.writeFile(destination, `${JSON.stringify(freeze, null, 2)}\n`);
  return destination;
}

test('freeze generator roundtrips through G1 and keeps every negative control closed', async t => {
  const scratch = await fs.mkdtemp(path.join(path.dirname(repo), 'freezegen-test-'));
  t.after(() => fs.rm(scratch, {recursive: true, force: true}));
  const evidenceRoot = path.join(scratch, 'evidence');
  const state = await fixture(scratch);

  const approved = generate(
    state.checkout, evidenceRoot, state.baseSdk, 1, 'TEST-ONLY-INJECTED-APPROVAL');
  const approvedFreeze = JSON.parse(await fs.readFile(approved.freezeFile, 'utf8'));
  assert.match(approvedFreeze.campaign_id,
    new RegExp(`^${state.head}-[0-9]{8}T[0-9]{6}Z-1$`));
  assert.equal(approvedFreeze.cjcj_head_sha, state.head);
  assert.equal(approvedFreeze.workflow_ref, git(state.checkout, 'branch', '--show-current'));
  assert.deepEqual(Object.keys(approvedFreeze.pins), [
    'RUNTIME_REF',
    'LLVM_SHA',
    'CANGJIE_COMPILER_SHA',
    'COMPILER_REF',
    'TOOLS_REF',
    'STDX_REF',
    'CJPM_FORK_REF',
  ]);
  assert.match(approvedFreeze.BASE_SDK_SHA256, /^[0-9a-f]{64}$/);
  const roundtrip = g1(state.checkout, approved.freezeFile);
  assert.equal(roundtrip.result.status, 0, roundtrip.result.stderr);
  assert.equal(roundtrip.value.status, 'MET');
  console.log('ROUNDTRIP injected-test-approval G1=MET');

  const g2 = JSON.parse(await fs.readFile(approved.g2IdentityFile, 'utf8'));
  assert.equal(g2.status, 'PENDING');
  assert.equal(g2.campaign_id, approvedFreeze.campaign_id);
  assert.deepEqual(Object.keys(g2.artifacts), G2_ARTIFACTS);
  for (const artifact of Object.values(g2.artifacts)) {
    assert.deepEqual(artifact, {
      artifact_path: null,
      sha256: null,
      provenance_stamp: null,
      source_commit: null,
      source_dirty: null,
    });
  }

  const runtimePinFile = path.join(state.checkout, 'ci/runtime_pin.env');
  const runtimePin = await fs.readFile(runtimePinFile, 'utf8');
  await fs.writeFile(runtimePinFile,
    runtimePin.replace(/^RUNTIME_REF=[0-9a-f]{40}$/m, `RUNTIME_REF=${'f'.repeat(40)}`));
  const pinNegative = g1(state.checkout, approved.freezeFile);
  assert.equal(pinNegative.result.status, 1, pinNegative.result.stderr);
  assert.equal(pinNegative.value.status, 'NOT_MET');
  assert.match(pinNegative.value.value, /RUNTIME_REF:freeze-mismatch/);
  console.log('NEG pin RUNTIME_REF=NOT_MET');
  await fs.writeFile(runtimePinFile, runtimePin);

  await write(state.checkout, 'head-change.txt', 'advance HEAD\n');
  const changedHead = commit(state.checkout, 'advance fixture head');
  assert.notEqual(changedHead, state.head);
  const headNegative = g1(state.checkout, approved.freezeFile);
  assert.equal(headNegative.result.status, 1, headNegative.result.stderr);
  assert.equal(headNegative.value.status, 'NOT_MET');
  assert.match(headNegative.value.value, /cjcj_head_sha=/);
  console.log('NEG changed HEAD=NOT_MET');

  const workflowBound = generate(
    state.checkout, evidenceRoot, state.baseSdk, 2, 'TEST-ONLY-INJECTED-APPROVAL');
  const releaseFile = path.join(state.checkout, '.github/workflows/release.yml');
  const release = await fs.readFile(releaseFile, 'utf8');
  await fs.writeFile(releaseFile, `${release}\n# one-byte-class test mutation\n`);
  const workflowNegative = g1(state.checkout, workflowBound.freezeFile);
  assert.equal(workflowNegative.result.status, 1, workflowNegative.result.stderr);
  assert.equal(workflowNegative.value.status, 'NOT_MET');
  assert.match(workflowNegative.value.value, /orchestrator_sha256:mismatch/);
  console.log('NEG release.yml byte=orchestrator_sha256:mismatch');
  await fs.writeFile(releaseFile, release);

  const empty = generate(state.checkout, evidenceRoot, state.baseSdk, 3);
  const emptyNegative = g1(state.checkout, empty.freezeFile);
  assert.equal(emptyNegative.result.status, 1, emptyNegative.result.stderr);
  assert.equal(emptyNegative.value.status, 'NOT_MET');
  assert.match(emptyNegative.value.value, /failures=approval(?:,|$)/);
  console.log('NEG empty approval=NOT_MET');

  const placeholderFile = path.join(scratch, 'placeholder-freeze.json');
  await copyWithApproval(empty.freezeFile, placeholderFile, '<approval-record>');
  const placeholderNegative = g1(state.checkout, placeholderFile);
  assert.equal(placeholderNegative.result.status, 1, placeholderNegative.result.stderr);
  assert.equal(placeholderNegative.value.status, 'NOT_MET');
  assert.match(placeholderNegative.value.value, /failures=approval(?:,|$)/);
  console.log('NEG placeholder approval=NOT_MET');

  const rejectedPlaceholder = run(process.execPath, [
    generator,
    '--repo', state.checkout,
    '--evidence-root', evidenceRoot,
    '--base-sdk', state.baseSdk,
    '--sequence', '4',
    '--approval-record', '<approval-record>',
  ]);
  assert.equal(rejectedPlaceholder.status, 1);
  assert.match(rejectedPlaceholder.stderr, /must not contain placeholder brackets/);
});
