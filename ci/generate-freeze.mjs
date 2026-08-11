#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO = path.resolve(HERE, '..');
const DEFAULT_EVIDENCE_ROOT = '/root/cj_build/evidence';
const SHA40 = /^[0-9a-f]{40}$/;

const PIN_SOURCES = Object.freeze({
  RUNTIME_REF: 'ci/runtime_pin.env',
  LLVM_SHA: 'ci/llvm_pin.env',
  CANGJIE_COMPILER_SHA: 'ci/llvm_pin.env',
  COMPILER_REF: 'ci/source_pin.env',
  TOOLS_REF: 'ci/source_pin.env',
  STDX_REF: 'ci/source_pin.env',
  CJPM_FORK_REF: 'ci/cjpm_pin.env',
});

const G2_ARTIFACTS = Object.freeze([
  'runtime_dynamic',
  'runtime_static',
  'llvm_llc',
  'llvm_opt',
  'cjcj',
  'std',
]);

function usage() {
  return [
    'usage: node ci/generate-freeze.mjs --base-sdk FILE [options]',
    '',
    'options:',
    '  --repo DIR              clean cjcj checkout (default: checkout containing this script)',
    '  --evidence-root DIR     campaign parent (default: /root/cj_build/evidence)',
    '  --workflow-ref REF      dispatch ref; defaults to the current branch',
    '  --sequence N            positive campaign sequence (default: 1)',
    '  --approval-record ID    explicit user instruction or approval record; no default exists',
    '',
    'The command creates <evidence-root>/<campaign_id>/{FREEZE.json,G2_IDENTITY.json}.',
    'Without --approval-record, FREEZE.json deliberately contains an empty approval and G1 stays NOT_MET.',
  ].join('\n');
}

function parseArguments(argv) {
  const values = {
    repo: DEFAULT_REPO,
    evidenceRoot: DEFAULT_EVIDENCE_ROOT,
    workflowRef: '',
    sequence: 1,
    approvalRecord: '',
    baseSdk: '',
  };
  const fields = new Map([
    ['--repo', 'repo'],
    ['--evidence-root', 'evidenceRoot'],
    ['--workflow-ref', 'workflowRef'],
    ['--sequence', 'sequence'],
    ['--approval-record', 'approvalRecord'],
    ['--base-sdk', 'baseSdk'],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') return {...values, help: true};
    if (!fields.has(argument)) throw new Error(`unknown argument: ${argument}\n${usage()}`);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`${argument} requires a value\n${usage()}`);
    values[fields.get(argument)] = value;
    index += 1;
  }
  if (!values.baseSdk) throw new Error(`--base-sdk is required\n${usage()}`);
  if (!/^[1-9][0-9]*$/.test(String(values.sequence))) {
    throw new Error(`--sequence must be a positive integer: ${values.sequence}`);
  }
  values.sequence = Number(values.sequence);
  values.repo = path.resolve(values.repo);
  values.evidenceRoot = path.resolve(values.evidenceRoot);
  values.baseSdk = path.resolve(values.baseSdk);
  return values;
}

function runGit(repo, args, {allowFailure = false} = {}) {
  const result = spawnSync('git', ['-C', repo, ...args], {encoding: 'utf8'});
  if (result.error || result.status !== 0) {
    if (allowFailure) return '';
    const detail = String(result.stderr || result.stdout || result.error?.message || '').trim();
    throw new Error(`git ${args.join(' ')} failed${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout.trim();
}

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

async function loadPins(repo) {
  const files = new Map();
  const pins = {};
  for (const [name, relative] of Object.entries(PIN_SOURCES)) {
    if (!files.has(relative)) files.set(relative, await fs.readFile(path.join(repo, relative), 'utf8'));
    const matches = files.get(relative).split(/\r?\n/).filter(line => line.startsWith(`${name}=`));
    if (matches.length !== 1) {
      throw new Error(`${relative} must contain exactly one literal ${name}= line; found ${matches.length}`);
    }
    const value = matches[0].slice(name.length + 1);
    if (!SHA40.test(value)) throw new Error(`${relative} has invalid ${name}: ${value || '<empty>'}`);
    pins[name] = value;
  }
  return pins;
}

function resolveWorkflowRef(repo, requested, head) {
  const workflowRef = requested || runGit(repo, ['symbolic-ref', '--quiet', '--short', 'HEAD'], {allowFailure: true});
  if (!workflowRef) throw new Error('detached HEAD requires an explicit --workflow-ref');
  if (workflowRef.includes('<') || workflowRef.includes('>') || /\s/.test(workflowRef)) {
    throw new Error(`workflow ref is a placeholder or contains whitespace: ${workflowRef}`);
  }
  const resolved = runGit(repo, ['rev-parse', `${workflowRef}^{commit}`]);
  if (resolved !== head) {
    throw new Error(`workflow ref must resolve exactly to frozen HEAD: ref=${workflowRef} resolved=${resolved} head=${head}`);
  }
  return workflowRef;
}

function approvalValue(explicit) {
  if (!explicit) return '';
  if (explicit.trim() !== explicit || explicit.includes('<') || explicit.includes('>') || /[\r\n]/.test(explicit)) {
    throw new Error('approval record must be explicit, single-line, trimmed, and must not contain placeholder brackets');
  }
  return explicit;
}

function utcStamp(now) {
  return now.toISOString().replace(/\.\d{3}Z$/, 'Z').replaceAll('-', '').replaceAll(':', '');
}

function pendingArtifact() {
  return {
    artifact_path: null,
    sha256: null,
    provenance_stamp: null,
    source_commit: null,
    source_dirty: null,
  };
}

function g2Skeleton(campaignId, head) {
  return {
    schema_version: 1,
    campaign_id: campaignId,
    cjcj_head_sha: head,
    captured_utc: null,
    status: 'PENDING',
    artifacts: Object.fromEntries(G2_ARTIFACTS.map(name => [name, pendingArtifact()])),
  };
}

function assertEvidenceRoot(root) {
  if (root === '/' || root === '/tmp' || root.startsWith('/tmp/')) {
    throw new Error(`evidence root must be persistent and narrowly scoped, not ${root}`);
  }
}

export async function generateFreeze(options, now = new Date()) {
  const repo = path.resolve(options.repo || DEFAULT_REPO);
  const evidenceRoot = path.resolve(options.evidenceRoot || DEFAULT_EVIDENCE_ROOT);
  const baseSdk = path.resolve(options.baseSdk);
  assertEvidenceRoot(evidenceRoot);

  const dirty = runGit(repo, ['status', '--porcelain=v1', '--untracked-files=normal']);
  if (dirty) throw new Error(`refusing to freeze a dirty checkout:\n${dirty}`);
  const head = runGit(repo, ['rev-parse', 'HEAD']);
  if (!SHA40.test(head)) throw new Error(`HEAD is not a full lowercase commit: ${head}`);
  const workflowRef = resolveWorkflowRef(repo, options.workflowRef || '', head);
  const repository = runGit(repo, ['remote', 'get-url', 'origin']);
  const pins = await loadPins(repo);

  const baseStat = await fs.stat(baseSdk);
  if (!baseStat.isFile() || baseStat.size === 0) throw new Error(`base SDK must be a non-empty file: ${baseSdk}`);
  const sequence = Number(options.sequence || 1);
  if (!Number.isSafeInteger(sequence) || sequence < 1) throw new Error(`invalid campaign sequence: ${options.sequence}`);
  const campaignId = `${head}-${utcStamp(now)}-${sequence}`;
  const campaignDir = path.join(evidenceRoot, campaignId);
  const approvalRecord = approvalValue(options.approvalRecord || '');

  const freeze = {
    schema_version: 1,
    campaign_id: campaignId,
    repository,
    cjcj_head_sha: head,
    workflow_ref: workflowRef,
    pins,
    BASE_SDK_SHA256: await sha256(baseSdk),
    policy_sha256: await sha256(path.join(repo, 'ops/design/DRYRUN_EXECUTION_POLICY.md')),
    orchestrator_sha256: await sha256(path.join(repo, '.github/workflows/release.yml')),
    approval: {
      user_instruction_or_record_id: approvalRecord,
    },
  };

  await fs.mkdir(evidenceRoot, {recursive: true});
  try {
    await fs.mkdir(campaignDir);
  } catch (error) {
    if (error.code === 'EEXIST') throw new Error(`campaign already exists and is immutable: ${campaignDir}`);
    throw error;
  }
  await fs.writeFile(path.join(campaignDir, 'FREEZE.json'), `${JSON.stringify(freeze, null, 2)}\n`, {flag: 'wx'});
  await fs.writeFile(path.join(campaignDir, 'G2_IDENTITY.json'), `${JSON.stringify(g2Skeleton(campaignId, head), null, 2)}\n`, {flag: 'wx'});

  return {
    approvalProvided: Boolean(approvalRecord),
    campaignDir,
    campaignId,
    freezeFile: path.join(campaignDir, 'FREEZE.json'),
    g2IdentityFile: path.join(campaignDir, 'G2_IDENTITY.json'),
  };
}

async function main(argv) {
  const options = parseArguments(argv);
  if (options.help) {
    console.log(usage());
    return 0;
  }
  const generated = await generateFreeze(options);
  console.log(`CAMPAIGN_ID=${generated.campaignId}`);
  console.log(`FREEZE_JSON=${generated.freezeFile}`);
  console.log(`G2_IDENTITY=${generated.g2IdentityFile}`);
  console.log(`APPROVAL=${generated.approvalProvided ? 'explicit' : 'empty; G1 remains NOT_MET'}`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then(
    code => { process.exitCode = code; },
    error => {
      console.error(`FREEZE_GENERATION_FAILED: ${error.message}`);
      process.exitCode = 1;
    });
}
