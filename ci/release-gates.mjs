#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO = path.resolve(HERE, '..');
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const STATUSES = new Set(['MET', 'NOT_MET', 'UNKNOWN']);
const PLATFORMS = ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64'];
const EVIDENCE_REGISTRY = 'GATE_EVIDENCE.json';
const EVIDENCE_BINDING = 'EVIDENCE_BINDING.json';
const DISCOVERABLE_EVIDENCE_GATES = new Set(['G2', 'G8', 'G12', 'G14']);
const GENERIC_BINDING_GATES = new Set(['G12', 'G14']);
const G2_ARTIFACTS = [
  'runtime_dynamic',
  'runtime_static',
  'llvm_llc',
  'llvm_opt',
  'cjcj',
  'std',
];

const GATES = Object.freeze({
  G1: {name: '冻结输入'},
  G2: {name: 'runtime/LLVM pair'},
  G3: {
    name: '五平台 source final std',
    updated: true,
    needsRun: '在相位编排和当前 pins 下跑 source producer；final-std-<platform> 5/5 成功并逐根通过 assertFinalStd',
  },
  G4: {name: 'release DAG 单闭包', updated: true},
  G5: {name: 'package std 完整性'},
  G6: {
    name: 'LLVM tuple',
    needsRun: '跑五 tuple producer；每格非空 llc.gz+opt.gz+manifest+shim，并让 manifest pin/双 SHA/双 version 校验通过',
  },
  G7: {
    name: '组件血缘',
    needsRun: '跑五个 package 格并归档；逐包验证 archive-level manifest、clean 单一 stamp 和全部 artifact SHA',
  },
  G8: {name: '当前 full gate', updated: true},
  G9: {
    name: '五平台 dry-run',
    updated: true,
    needsRun: '在 frozen head + 当前相位编排下跑 release dry-run；5/5 package success、smoke 15/15、Darwin LTO 阳性、10 个外向文件 checksum 全过',
  },
  G10: {
    name: 'selfhost 启动/小程序',
    needsRun: 'final compiler×final host runtime：--version 与最小 compile 各 N=20，SKIPPED_WHO=0，再跑 crashsweep N=50',
  },
  G11: {
    name: 'Conformance',
    needsRun: 'G10 先通后，以 final apparatus 跑 29060/29060；isolation selfhost-only、loader/GC assert/SEGV 均为 0，并绑定 final SHA',
  },
  G12: {name: 'GC release floor'},
  G13: {name: 'loaderlife 直接门'},
  G14: {name: 'Idle writer/FYS'},
  G15: {name: 'cjdb'},
  G16: {name: '签名/SBOM 政策'},
  G17: {name: '执行与证据'},
});

class GateInputError extends Error {
  constructor(kind, message) {
    super(message);
    this.kind = kind;
  }
}

function usage() {
  return [
    'usage: node ci/release-gates.mjs [all|G1..G17] [options]',
    '',
    'options:',
    '  --repo DIR             cjcj checkout (default: checkout containing this script)',
    '  --ref REF              read static G5 inputs from a historical cjcj ref (two-arm control)',
    '  --runtime-repo DIR     local cangjie-runtime git repository for G2/G13 ancestry',
    '  --runtime-ref SHA      deliberate G13 control override; normal runs read ci/runtime_pin.env',
    '  --freeze FILE          release FREEZE.json for G1 (default is derived from the runbook)',
    '  --evidence DIR         persistent release evidence archive for evidence-backed gates',
    '  --json                 print JSON instead of a row/table',
    '',
    'individual exit codes: 0=MET, 1=NOT_MET, 2=UNKNOWN; `all` always exits 0 after printing every gate',
  ].join('\n');
}

function parseArguments(argv) {
  const options = {
    selection: 'all',
    repo: DEFAULT_REPO,
    ref: '',
    runtimeRepo: process.env.CJCJ_GATE_RUNTIME_REPO || '',
    runtimeRef: '',
    freeze: process.env.CJCJ_GATE_FREEZE || '',
    evidence: process.env.CJCJ_GATE_EVIDENCE || '',
    json: false,
  };
  let selectionSeen = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') return {...options, help: true};
    if (argument === '--json') {
      options.json = true;
      continue;
    }
    const fields = new Map([
      ['--repo', 'repo'],
      ['--ref', 'ref'],
      ['--runtime-repo', 'runtimeRepo'],
      ['--runtime-ref', 'runtimeRef'],
      ['--freeze', 'freeze'],
      ['--evidence', 'evidence'],
    ]);
    if (fields.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Error(`${argument} requires a value\n${usage()}`);
      options[fields.get(argument)] = value;
      index += 1;
      continue;
    }
    if (argument.startsWith('--')) throw new Error(`unknown option: ${argument}\n${usage()}`);
    if (selectionSeen) throw new Error(`more than one gate selected: ${options.selection}, ${argument}\n${usage()}`);
    options.selection = argument.toUpperCase();
    selectionSeen = true;
  }
  if (options.selection !== 'ALL' && options.selection !== 'all' && !Object.hasOwn(GATES, options.selection)) {
    throw new Error(`unknown gate: ${options.selection}\n${usage()}`);
  }
  options.selection = options.selection.toUpperCase();
  options.repo = path.resolve(options.repo);
  if (options.runtimeRepo) options.runtimeRepo = path.resolve(options.runtimeRepo);
  if (options.freeze) options.freeze = path.resolve(options.freeze);
  if (options.evidence) options.evidence = path.resolve(options.evidence);
  return options;
}

function commandFor(gate) {
  return `node ci/release-gates.mjs ${gate}`;
}

function gateResult(gate, status, value, extra = {}) {
  if (!STATUSES.has(status)) throw new Error(`invalid status for ${gate}: ${status}`);
  return {
    gate,
    name: GATES[gate].name,
    status,
    command: GATES[gate].needsRun ? `需 run：${GATES[gate].needsRun}` : commandFor(gate),
    value,
    criterion_updated_0811: Boolean(GATES[gate].updated),
    ...extra,
  };
}

function compact(text, limit = 360) {
  const normalized = String(text || '').replace(/\s+/g, ' ').trim();
  return normalized.length <= limit ? normalized : `${normalized.slice(0, limit - 3)}...`;
}

function commandFailure(result) {
  return compact(result.stderr || result.stdout || result.error?.message || `exit=${result.status}`);
}

function spawn(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
}

async function readFile(context, relative, {absence = 'NOT_MET'} = {}) {
  if (context.ref) {
    const result = spawn('git', ['-C', context.repo, 'show', `${context.ref}:${relative}`]);
    if (result.error) throw new GateInputError('UNKNOWN', `cannot run git show for ${relative}: ${result.error.message}`);
    if (result.status !== 0) {
      const status = /does not exist|exists on disk, but not in|Path .* does not exist/.test(result.stderr)
        ? absence
        : 'UNKNOWN';
      throw new GateInputError(status, `cannot read ${relative} at ${context.ref}: ${commandFailure(result)}`);
    }
    return result.stdout;
  }
  const file = path.join(context.repo, ...relative.split('/'));
  try {
    return await fs.readFile(file, 'utf8');
  } catch (error) {
    const status = error.code === 'ENOENT' ? absence : 'UNKNOWN';
    throw new GateInputError(status, `cannot read ${relative}: ${error.code || error.message}`);
  }
}

async function readAbsolute(file, {absence = 'UNKNOWN'} = {}) {
  try {
    return await fs.readFile(file, 'utf8');
  } catch (error) {
    const status = error.code === 'ENOENT' ? absence : 'UNKNOWN';
    throw new GateInputError(status, `cannot read ${file}: ${error.code || error.message}`);
  }
}

function parseEnv(text, label) {
  const values = {};
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) throw new GateInputError('UNKNOWN', `${label} has an invalid line: ${raw}`);
    values[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return values;
}

async function loadPins(context) {
  const [runtime, llvm, source, cjpm] = await Promise.all([
    readFile(context, 'ci/runtime_pin.env', {absence: 'UNKNOWN'}),
    readFile(context, 'ci/llvm_pin.env', {absence: 'UNKNOWN'}),
    readFile(context, 'ci/source_pin.env', {absence: 'UNKNOWN'}),
    readFile(context, 'ci/cjpm_pin.env', {absence: 'UNKNOWN'}),
  ]);
  return {
    runtime: parseEnv(runtime, 'ci/runtime_pin.env'),
    llvm: parseEnv(llvm, 'ci/llvm_pin.env'),
    source: parseEnv(source, 'ci/source_pin.env'),
    cjpm: parseEnv(cjpm, 'ci/cjpm_pin.env'),
  };
}

function git(context, args) {
  const result = spawn('git', ['-C', context.repo, ...args]);
  if (result.error || result.status !== 0) {
    throw new GateInputError('UNKNOWN', `git ${args.join(' ')} failed: ${commandFailure(result)}`);
  }
  return result.stdout.trim();
}

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

function nestedValues(value, key, found = []) {
  if (!value || typeof value !== 'object') return found;
  for (const [name, child] of Object.entries(value)) {
    if (name === key) found.push(child);
    nestedValues(child, key, found);
  }
  return found;
}

async function releaseEvidenceRoot(context) {
  const runbook = await readFile(context, 'ops/coord/RELEASE_0_0_2_RUNBOOK.md', {absence: 'UNKNOWN'});
  const root = runbook.match(/^export RELEASE_EVIDENCE_ROOT=(.+)$/m)?.[1]?.trim();
  if (!root || root.includes('<')) {
    throw new GateInputError('UNKNOWN', 'runbook does not expose one concrete RELEASE_EVIDENCE_ROOT');
  }
  return path.resolve(root);
}

async function defaultFreezePath(context) {
  return path.join(await releaseEvidenceRoot(context), 'FREEZE.json');
}

function parseEvidenceJson(text, label) {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `${label} is unreadable JSON: ${error.message}`);
  }
}

function evidenceRelativeFile(root, relative, label) {
  if (typeof relative !== 'string' || relative.length === 0 || path.isAbsolute(relative) || relative.includes('\\')) {
    throw new GateInputError('UNKNOWN', `${label} is not a normalized relative path`);
  }
  const file = path.resolve(root, ...relative.split('/'));
  const withinRoot = file.startsWith(`${root}${path.sep}`);
  if (!withinRoot || path.relative(root, file).split(path.sep).includes('..')) {
    throw new GateInputError('UNKNOWN', `${label} escapes its evidence root`);
  }
  return file;
}

async function evidencePayloadFiles(root, directory = root) {
  let entries;
  try {
    entries = await fs.readdir(directory, {withFileTypes: true});
  } catch (error) {
    throw new GateInputError('UNKNOWN', `cannot enumerate evidence ${directory}: ${error.code || error.message}`);
  }
  const files = [];
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      throw new GateInputError('UNKNOWN', `evidence contains a symbolic link: ${path.relative(root, file)}`);
    }
    if (entry.isDirectory()) files.push(...await evidencePayloadFiles(root, file));
    else if (entry.isFile()) files.push(path.relative(root, file).split(path.sep).join('/'));
    else throw new GateInputError('UNKNOWN', `evidence contains a non-file entry: ${path.relative(root, file)}`);
  }
  return files;
}

function validMeasurementTime(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

async function validateEvidenceBinding(gate, context, evidence) {
  const root = path.resolve(evidence);
  let rootStat;
  try {
    rootStat = await fs.lstat(root);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `cannot inspect evidence root ${root}: ${error.code || error.message}`);
  }
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    throw new GateInputError('UNKNOWN', `evidence root is not a direct directory: ${root}`);
  }
  const bindingFile = path.join(root, EVIDENCE_BINDING);
  const binding = parseEvidenceJson(await readAbsolute(bindingFile, {absence: 'UNKNOWN'}), bindingFile);
  const failures = [];
  const checkoutHead = git(context, ['rev-parse', 'HEAD']);
  if (binding.schema !== 1) failures.push('schema');
  if (binding.gate !== gate) failures.push(`gate=${binding.gate || '<missing>'}`);
  if (!SHA40.test(String(binding.cjcj_head_sha || '')) || binding.cjcj_head_sha !== checkoutHead) {
    failures.push(`cjcj_head_sha=${binding.cjcj_head_sha || '<missing>'} current=${checkoutHead}`);
  }
  if (typeof binding.producer?.repository !== 'string' || !binding.producer.repository.trim()) {
    failures.push('producer.repository');
  }
  if (!SHA40.test(String(binding.producer?.head_sha || ''))) failures.push('producer.head_sha');
  if (typeof binding.recipe?.id !== 'string' || !binding.recipe.id.trim()) failures.push('recipe.id');
  if (!SHA256.test(String(binding.recipe?.sha256 || ''))) failures.push('recipe.sha256');
  if (!validMeasurementTime(binding.measurement?.started_utc)) failures.push('measurement.started_utc');
  if (!validMeasurementTime(binding.measurement?.finished_utc)) failures.push('measurement.finished_utc');
  if (validMeasurementTime(binding.measurement?.started_utc) && validMeasurementTime(binding.measurement?.finished_utc) &&
      Date.parse(binding.measurement.finished_utc) < Date.parse(binding.measurement.started_utc)) {
    failures.push('measurement.order');
  }
  if (!binding.payload_sha256 || typeof binding.payload_sha256 !== 'object' ||
      Array.isArray(binding.payload_sha256) || Object.keys(binding.payload_sha256).length === 0) {
    failures.push('payload_sha256');
  }
  if (failures.length) {
    throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: ${failures.join(',')}; file=${bindingFile}`);
  }

  const recipeFile = evidenceRelativeFile(root, binding.recipe.file, 'recipe.file');
  if (await sha256(recipeFile) !== binding.recipe.sha256) {
    throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: recipe sha256 mismatch`);
  }
  const producerFile = evidenceRelativeFile(root, binding.producer.head_file, 'producer.head_file');
  const producerText = await readAbsolute(producerFile, {absence: 'UNKNOWN'});
  if (!producerText.split(/\r?\n/).includes(`HEAD=${binding.producer.head_sha}`)) {
    throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: producer HEAD is not bound by ${binding.producer.head_file}`);
  }

  const registered = Object.keys(binding.payload_sha256).sort();
  const actual = (await evidencePayloadFiles(root)).filter(file => file !== EVIDENCE_BINDING).sort();
  if (JSON.stringify(registered) !== JSON.stringify(actual)) {
    throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: payload inventory mismatch`);
  }
  for (const relative of registered) {
    const expected = binding.payload_sha256[relative];
    if (!SHA256.test(String(expected || ''))) {
      throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: invalid sha256 for ${relative}`);
    }
    const file = evidenceRelativeFile(root, relative, `payload_sha256.${relative}`);
    if (await sha256(file) !== expected) {
      throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: sha256 mismatch for ${relative}`);
    }
  }
  if (binding.payload_sha256[binding.recipe.file] !== binding.recipe.sha256) {
    throw new GateInputError('UNKNOWN', `${gate} evidence binding rejected: recipe is absent from payload inventory`);
  }
  return root;
}

async function discoverEvidenceContext(gate, context) {
  if (context.evidence) {
    if (GENERIC_BINDING_GATES.has(gate)) await validateEvidenceBinding(gate, context, context.evidence);
    return context;
  }
  if (!DISCOVERABLE_EVIDENCE_GATES.has(gate)) return context;
  const root = await releaseEvidenceRoot(context);
  const registryFile = path.join(root, EVIDENCE_REGISTRY);
  let registryText;
  try {
    registryText = await fs.readFile(registryFile, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return context;
    throw new GateInputError('UNKNOWN', `cannot read evidence registry ${registryFile}: ${error.code || error.message}`);
  }
  const registry = parseEvidenceJson(registryText, registryFile);
  if (registry.schema !== 1 || !registry.gates || typeof registry.gates !== 'object' || Array.isArray(registry.gates)) {
    throw new GateInputError('UNKNOWN', `evidence registry has an invalid schema: ${registryFile}`);
  }
  const relative = registry.gates[gate];
  if (relative === undefined) return context;
  const evidence = evidenceRelativeFile(root, relative, `registry.gates.${gate}`);
  let realRoot;
  let realEvidence;
  try {
    [realRoot, realEvidence] = await Promise.all([fs.realpath(root), fs.realpath(evidence)]);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `cannot resolve registered ${gate} evidence: ${error.code || error.message}`);
  }
  if (!realEvidence.startsWith(`${realRoot}${path.sep}`)) {
    throw new GateInputError('UNKNOWN', `registry.gates.${gate} resolves outside its evidence root`);
  }
  await validateEvidenceBinding(gate, context, evidence);
  return {...context, evidence};
}

async function evaluateG1(context) {
  const freezeFile = context.freeze || await defaultFreezePath(context);
  let text;
  try {
    text = await readAbsolute(freezeFile, {absence: 'NOT_MET'});
  } catch (error) {
    if (error.kind === 'NOT_MET') return gateResult('G1', 'NOT_MET', `FREEZE.json 不存在：${freezeFile}`);
    throw error;
  }
  let freeze;
  try {
    freeze = JSON.parse(text);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `FREEZE.json is unreadable JSON: ${error.message}`);
  }
  const pins = await loadPins(context);
  const head = git(context, ['rev-parse', 'HEAD']);
  const requiredPins = {
    RUNTIME_REF: pins.runtime.RUNTIME_REF,
    LLVM_SHA: pins.llvm.LLVM_SHA,
    CANGJIE_COMPILER_SHA: pins.llvm.CANGJIE_COMPILER_SHA,
    COMPILER_REF: pins.source.COMPILER_REF,
    TOOLS_REF: pins.source.TOOLS_REF,
    STDX_REF: pins.source.STDX_REF,
    CJPM_FORK_REF: pins.cjpm.CJPM_FORK_REF,
  };
  const failures = [];
  if (!/^[0-9a-f]{40}-\d{8}T\d{6}Z-\d+$/.test(String(freeze.campaign_id || ''))) {
    failures.push('campaign_id');
  }
  if (!SHA40.test(String(freeze.cjcj_head_sha || '')) || freeze.cjcj_head_sha !== head) {
    failures.push(`cjcj_head_sha=${freeze.cjcj_head_sha || '<missing>'}`);
  }
  if (!String(freeze.workflow_ref || '').trim() || String(freeze.workflow_ref).includes('<')) failures.push('workflow_ref');
  for (const [name, expected] of Object.entries(requiredPins)) {
    if (!SHA40.test(String(expected || ''))) failures.push(`${name}:pin-file-invalid`);
    const values = nestedValues(freeze, name);
    if (values.length !== 1 || values[0] !== expected) failures.push(`${name}:freeze-mismatch`);
  }
  const baseDigests = nestedValues(freeze, 'BASE_SDK_SHA256');
  if (baseDigests.length !== 1 || !SHA256.test(String(baseDigests[0] || ''))) failures.push('BASE_SDK_SHA256');
  const policy = path.join(context.repo, 'ops/design/DRYRUN_EXECUTION_POLICY.md');
  const workflow = path.join(context.repo, '.github/workflows/release.yml');
  const expectedHashes = {
    policy_sha256: await sha256(policy),
    orchestrator_sha256: await sha256(workflow),
  };
  for (const [name, expected] of Object.entries(expectedHashes)) {
    const values = nestedValues(freeze, name);
    if (values.length !== 1 || values[0] !== expected) failures.push(`${name}:mismatch`);
  }
  if (!freeze.approval?.user_instruction_or_record_id ||
      String(freeze.approval.user_instruction_or_record_id).includes('<')) failures.push('approval');
  if (failures.length) return gateResult('G1', 'NOT_MET', `freeze=${freezeFile}; failures=${failures.join(',')}`);
  return gateResult('G1', 'MET', `freeze=${freezeFile}; head/pins/base-sdk/policy/workflow/approval 全绑定`);
}

async function discoverRuntimeRepo(context) {
  if (context.runtimeRepo) return context.runtimeRepo;
  const common = git(context, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  return path.join(path.dirname(path.dirname(common)), 'cangjie_runtime');
}

async function loaderlifeResult(context, gate = 'G13') {
  const pins = await loadPins(context);
  const minimum = pins.runtime.LOADERLIFE_MIN_REF;
  const runtimeRef = context.runtimeRef || pins.runtime.RUNTIME_REF;
  if (!SHA40.test(String(minimum || '')) || !SHA40.test(String(runtimeRef || ''))) {
    return gateResult(gate, 'UNKNOWN', `runtime pin metadata unreadable: minimum=${minimum || '<missing>'} runtime=${runtimeRef || '<missing>'}`);
  }
  const runtimeRepo = await discoverRuntimeRepo(context);
  const probe = spawn('git', ['-C', runtimeRepo, 'merge-base', '--is-ancestor', minimum, runtimeRef]);
  if (probe.error) return gateResult(gate, 'UNKNOWN', `runtime ancestry tool unavailable: ${probe.error.message}`);
  if (probe.status === 0) {
    return gateResult(gate, 'MET', `runtime pin ${runtimeRef} contains loaderlife floor ${minimum}; repo=${runtimeRepo}`);
  }
  if (probe.status === 1) {
    return gateResult(gate, 'NOT_MET', `runtime pin ${runtimeRef} does not contain loaderlife floor ${minimum}; repo=${runtimeRepo}`);
  }
  return gateResult(gate, 'UNKNOWN', `runtime ancestry unreadable: ${commandFailure(probe)}; repo=${runtimeRepo}`);
}

function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, allowed, label, failures) {
  if (!plainObject(value)) return;
  const extra = Object.keys(value).filter(key => !allowed.includes(key));
  if (extra.length) failures.push(`${label} additionalProperties=${extra.join(',')}`);
}

function g2IdentitySchemaState(identity, schema) {
  const missing = [];
  const invalid = [];
  const pending = [];
  if (!plainObject(identity)) {
    return {status: 'NOT_MET', detail: 'G2_IDENTITY.json schema failure: root must be an object'};
  }

  const rootProperties = Object.keys(schema?.properties || {});
  const rootRequired = schema?.required || [];
  if (schema?.type !== 'object' || schema?.properties?.schema_version?.const !== 1 ||
      JSON.stringify(schema?.properties?.status?.enum) !== JSON.stringify(['PENDING', 'READY']) ||
      JSON.stringify(schema?.properties?.artifacts?.required) !== JSON.stringify(G2_ARTIFACTS)) {
    return {status: 'UNKNOWN', detail: 'g2-identity.schema.json does not define the expected six-slot v1 contract'};
  }
  exactKeys(identity, rootProperties, 'root', invalid);
  for (const field of rootRequired) {
    if (!Object.hasOwn(identity, field)) missing.push(field);
  }
  if (identity.schema_version !== 1) invalid.push(`schema_version=${String(identity.schema_version)}`);
  const campaignPattern = new RegExp(schema.properties.campaign_id.pattern);
  if (Object.hasOwn(identity, 'campaign_id') &&
      (typeof identity.campaign_id !== 'string' || !campaignPattern.test(identity.campaign_id))) {
    invalid.push('campaign_id');
  }
  const shaPattern = new RegExp(schema.properties.cjcj_head_sha.pattern);
  if (Object.hasOwn(identity, 'cjcj_head_sha') &&
      (typeof identity.cjcj_head_sha !== 'string' || !shaPattern.test(identity.cjcj_head_sha))) {
    invalid.push('cjcj_head_sha');
  }
  if (Object.hasOwn(identity, 'status') && !schema.properties.status.enum.includes(identity.status)) {
    invalid.push(`status=${String(identity.status)}`);
  }
  const ready = identity.status === 'READY';
  if (Object.hasOwn(identity, 'captured_utc')) {
    if (identity.captured_utc === null) {
      if (ready) missing.push('captured_utc');
      else pending.push('captured_utc');
    } else if (typeof identity.captured_utc !== 'string' ||
               !new RegExp(schema.properties.captured_utc.pattern).test(identity.captured_utc)) {
      invalid.push('captured_utc');
    }
  }

  const artifactSchema = schema.$defs?.artifact_slot;
  const artifactFields = artifactSchema?.required || [];
  if (!plainObject(identity.artifacts)) {
    if (Object.hasOwn(identity, 'artifacts')) invalid.push('artifacts');
  } else {
    exactKeys(identity.artifacts, G2_ARTIFACTS, 'artifacts', invalid);
    for (const name of G2_ARTIFACTS) {
      const artifact = identity.artifacts[name];
      if (!Object.hasOwn(identity.artifacts, name)) {
        missing.push(`artifacts.${name}`);
        continue;
      }
      if (!plainObject(artifact)) {
        invalid.push(`artifacts.${name}`);
        continue;
      }
      exactKeys(artifact, artifactFields, `artifacts.${name}`, invalid);
      for (const field of artifactFields) {
        const label = `artifacts.${name}.${field}`;
        if (!Object.hasOwn(artifact, field)) {
          missing.push(label);
          continue;
        }
        const value = artifact[field];
        if (value === null) {
          if (ready) missing.push(label);
          else pending.push(label);
          continue;
        }
        if (field === 'source_dirty') {
          if (typeof value !== 'boolean') invalid.push(label);
        } else if (typeof value !== 'string' || value.length === 0) {
          invalid.push(label);
        } else if (field === 'sha256' && !SHA256.test(value)) {
          invalid.push(label);
        } else if (field === 'source_commit' && !SHA40.test(value)) {
          invalid.push(label);
        }
      }
    }
  }

  if (missing.length) return {status: 'UNKNOWN', detail: `G2_IDENTITY.json missing=${missing.join(',')}`};
  if (invalid.length) return {status: 'NOT_MET', detail: `G2_IDENTITY.json schema_failures=${invalid.join(';')}`};
  if (!ready) {
    return {status: 'UNKNOWN',
      detail: `G2_IDENTITY.json status=PENDING; missing=status=READY${pending.length ? `,${pending.join(',')}` : ''}`};
  }
  return {status: 'MET', detail: 'G2_IDENTITY.json status=READY and schema complete'};
}

function parseG2Json(text, label) {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `${label} is unreadable JSON: ${error.message}`);
  }
}

async function evaluateG2(context) {
  const ancestry = await loaderlifeResult(context, 'G2');
  if (ancestry.status !== 'MET') return ancestry;
  if (!context.evidence) {
    return gateResult('G2', 'UNKNOWN', `${ancestry.value}; missing=--evidence archive,` +
      'G2_IDENTITY.json.status=READY,G2_IDENTITY.json.captured_utc,' +
      'G2_IDENTITY.json.artifacts.{runtime_dynamic,runtime_static,llvm_llc,llvm_opt,cjcj,std}.' +
      '{artifact_path,sha256,provenance_stamp,source_commit,source_dirty}');
  }
  const verifier = path.join(context.repo, 'scripts/archive_release_evidence.mjs');
  const verified = spawn(process.execPath, [verifier, 'verify', '--archive', context.evidence], {cwd: context.repo});
  if (verified.error) return gateResult('G2', 'UNKNOWN', `evidence verifier unavailable: ${verified.error.message}`);
  if (verified.status !== 0) return gateResult('G2', 'NOT_MET', `evidence rejected: ${commandFailure(verified)}`);

  const identityFile = path.join(path.dirname(path.resolve(context.evidence)), 'G2_IDENTITY.json');
  const [identityText, schemaText, runText, pins] = await Promise.all([
    readAbsolute(identityFile, {absence: 'UNKNOWN'}),
    readFile(context, 'ci/release-evidence/g2-identity.schema.json', {absence: 'UNKNOWN'}),
    readAbsolute(path.join(context.evidence, 'run.json'), {absence: 'UNKNOWN'}),
    loadPins(context),
  ]);
  const identity = parseG2Json(identityText, identityFile);
  const schema = parseG2Json(schemaText, 'ci/release-evidence/g2-identity.schema.json');
  const run = parseG2Json(runText, path.join(context.evidence, 'run.json'));
  const schemaState = g2IdentitySchemaState(identity, schema);
  if (schemaState.status !== 'MET') {
    return gateResult('G2', schemaState.status, `${ancestry.value}; archive=valid; ${schemaState.detail}`);
  }

  const failures = [];
  if (!identity.campaign_id.startsWith(`${identity.cjcj_head_sha}-`)) {
    failures.push('campaign_id does not bind cjcj_head_sha');
  }
  if (run.head_sha !== identity.cjcj_head_sha) {
    failures.push(`archive head=${run.head_sha || '<missing>'} identity head=${identity.cjcj_head_sha}`);
  }
  const expectedCommits = {
    runtime_dynamic: pins.runtime.RUNTIME_REF,
    runtime_static: pins.runtime.RUNTIME_REF,
    llvm_llc: pins.llvm.LLVM_SHA,
    llvm_opt: pins.llvm.LLVM_SHA,
    cjcj: identity.cjcj_head_sha,
  };
  const stampPrefixes = {
    runtime_dynamic: 'CJRT-COMMIT',
    runtime_static: 'CJRT-COMMIT',
    llvm_llc: 'CJLLVM-COMMIT',
    llvm_opt: 'CJLLVM-COMMIT',
    cjcj: 'CJCJ-COMMIT',
    std: 'CJSTD-COMMIT',
  };
  for (const name of G2_ARTIFACTS) {
    const artifact = identity.artifacts[name];
    const expectedCommit = expectedCommits[name];
    if (expectedCommit && artifact.source_commit !== expectedCommit) {
      failures.push(`${name}.source_commit=${artifact.source_commit} expected=${expectedCommit}`);
    }
    if (artifact.source_dirty !== false) failures.push(`${name}.source_dirty=${artifact.source_dirty}`);
    const marker = `${stampPrefixes[name]}:${artifact.source_commit}`;
    if (!artifact.provenance_stamp.includes(marker)) failures.push(`${name}.provenance_stamp lacks ${marker}`);
    if (artifact.provenance_stamp.includes('-dirty')) failures.push(`${name}.provenance_stamp is dirty`);
  }
  if (failures.length) {
    return gateResult('G2', 'NOT_MET', `${ancestry.value}; archive=valid; identity=READY; failures=${failures.join(';')}`);
  }
  return gateResult('G2', 'MET', `${ancestry.value}; archive=valid; G2_IDENTITY.json READY; ` +
    'six slots schema-complete, clean, stamped, and bound to archive head/runtime/LLVM pins');
}

function runTests(context, files) {
  if (context.ref) throw new GateInputError('UNKNOWN', 'targeted node tests cannot run against --ref without a checkout');
  const result = spawn(process.execPath, ['--test', '--test-timeout=300000', ...files], {cwd: context.repo});
  if (result.error) throw new GateInputError('UNKNOWN', `node test runner unavailable: ${result.error.message}`);
  if (result.status !== 0) return {status: 'NOT_MET', detail: commandFailure(result)};
  const pass = result.stdout.match(/^(?:#|ℹ)\s*pass\s+(\d+)$/m)?.[1] || '?';
  const fail = result.stdout.match(/^(?:#|ℹ)\s*fail\s+(\d+)$/m)?.[1] || '?';
  return {status: 'MET', detail: `tests pass=${pass} fail=${fail}`};
}

async function evaluateG4(context) {
  const release = await readFile(context, '.github/workflows/release.yml');
  const sourceCalls = release.match(/uses:\s*\.\/\.github\/workflows\/srcbuild\.yml/g)?.length || 0;
  const phases = [...release.matchAll(/^  source-p(\d+)-[^:]+:\s*$/gm)].map(match => Number(match[1]));
  const uniquePhases = new Set(phases);
  const tests = runTests(context, [
    'ci/srcbuild/tests/phase-control.test.mjs',
    'ci/srcbuild/tests/release-wire.test.mjs',
    'ci/srcbuild/tests/workflow-inputs.test.mjs',
    'ci/srcbuild/tests/platform-contract.test.mjs',
  ]);
  const structural = sourceCalls > 0 && sourceCalls === phases.length && phases.length === uniquePhases.size;
  const status = structural && tests.status === 'MET' ? 'MET' : 'NOT_MET';
  return gateResult('G4', status,
    `判据 0811 已更新；srcbuild_calls=${sourceCalls} source_phases=${phases.length} unique_source_phases=${uniquePhases.size}; ${tests.detail}`);
}

function stepBlock(workflow, name) {
  const start = workflow.indexOf(`- name: ${name}`);
  if (start < 0) return '';
  const end = workflow.indexOf('\n      - name:', start + 1);
  return workflow.slice(start, end < 0 ? workflow.length : end);
}

async function evaluateG5(context) {
  const [checker, workflow] = await Promise.all([
    readFile(context, 'scripts/check_packaged_std.mjs'),
    readFile(context, '.github/workflows/build-release-package.yml'),
  ]);
  const classes = checker.match(/const CLASS_NAMES\s*=\s*\[([^\]]+)\]/)?.[1]
    ?.match(/['"][^'"]+['"]/g)?.map(value => value.slice(1, -1)) || [];
  const expectedClasses = ['cjo', 'bc', 'static-ffi', 'shared', 'provenance'];
  const invocationCount = workflow.match(/node scripts\/check_packaged_std\.mjs/g)?.length || 0;
  const block = stepBlock(workflow, 'Verify packaged standard library');
  const staticPass = JSON.stringify(classes) === JSON.stringify(expectedClasses) &&
    invocationCount === 1 && /if:\s*inputs\.verify/.test(block) && /timeout-minutes:\s*2/.test(block) &&
    !/continue-on-error/.test(block) && ['--sdk', '--std', '--platform'].every(value => block.includes(value));
  if (!staticPass) {
    return gateResult('G5', 'NOT_MET',
      `classes=${classes.join(',') || '<none>'} workflow_consumers=${invocationCount} bounded=${/timeout-minutes:\s*2/.test(block)}`);
  }
  if (context.ref) {
    return gateResult('G5', 'MET', `ref=${context.ref}; classes=5 workflow_consumers=1 bounded_fail_closed=yes`);
  }
  const tests = runTests(context, [
    'build/test/package-std-integrity.test.mjs',
    'ci/srcbuild/tests/release-wire.test.mjs',
  ]);
  return gateResult('G5', tests.status,
    `classes=5 workflow_consumers=1 bounded_fail_closed=yes; ${tests.detail}`);
}

const G8_METRIC_PATHS = [
  'difftest.total',
  'difftest.pass',
  'difftest.mismatch',
  'difftest.fail',
  'smoke.pass',
  'smoke.fail',
  'bcgate.shared',
  'bcgate.byte_identical',
  'bcgate.differing',
  'bcgate.compile_errors',
  'verify_exit',
];

function nestedField(value, dotted) {
  return dotted.split('.').reduce((current, field) => current?.[field], value);
}

function validateG8Metrics(value, label, {pending = false} = {}) {
  const missing = [];
  const invalid = [];
  for (const metric of G8_METRIC_PATHS) {
    const actual = nestedField(value, metric);
    if (actual === undefined || actual === null) {
      missing.push(`${label}.${metric}`);
    } else if (!Number.isSafeInteger(actual) || actual < 0) {
      invalid.push(`${label}.${metric}=${String(actual)}`);
    }
  }
  if (pending) return {status: 'UNKNOWN', detail: `missing=status=READY,${missing.join(',')}`};
  if (missing.length) return {status: 'UNKNOWN', detail: `missing=${missing.join(',')}`};
  if (invalid.length) return {status: 'NOT_MET', detail: `invalid=${invalid.join(',')}`};
  return {status: 'MET', detail: 'complete'};
}

async function loadG8Floor(context) {
  if (context.ref) throw new GateInputError('UNKNOWN', 'G8 evidence evaluation requires a checkout, not --ref');
  const file = path.join(context.repo, 'build', 'lib', 'full-gate-release-floor.mjs');
  let imported;
  try {
    imported = await import(pathToFileURL(file).href);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `cannot load frozen G8 floor: ${error.code || error.message}`);
  }
  const floor = imported.FULL_GATE_RELEASE_FLOOR;
  if (!plainObject(floor) || floor.schema !== 1) {
    throw new GateInputError('UNKNOWN', 'frozen G8 floor does not expose the v1 contract');
  }
  if (!['PENDING', 'READY'].includes(floor.status)) {
    return {floor, state: {status: 'NOT_MET', detail: `invalid=status=${String(floor.status)}`}};
  }
  const pending = floor.status === 'PENDING';
  const missing = [];
  const invalid = [];
  for (const [field, pattern] of [
    ['campaign_id', /^[0-9a-f]{40}-[0-9]{8}T[0-9]{6}Z-[1-9][0-9]*$/],
    ['cjcj_head_sha', SHA40],
    ['measured_utc', /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/],
  ]) {
    const value = floor[field];
    if (value === undefined || value === null) missing.push(field);
    else if (typeof value !== 'string' || !pattern.test(value)) invalid.push(field);
  }
  const resultsFile = floor.evidence?.results;
  if (typeof resultsFile !== 'string' || !resultsFile) {
    if (resultsFile === undefined || resultsFile === null) missing.push('evidence.results');
    else invalid.push('evidence.results');
  }
  const metrics = validateG8Metrics(floor.baseline, 'baseline', {pending});
  if (pending) {
    return {floor, state: {status: 'UNKNOWN',
      detail: `floor status=PENDING; missing=status=READY,${[...missing, ...G8_METRIC_PATHS.map(name => `baseline.${name}`)].join(',')}`}};
  }
  if (missing.length || metrics.status === 'UNKNOWN') {
    const metricDetail = metrics.status === 'UNKNOWN' ? metrics.detail.replace(/^missing=/, '') : '';
    return {floor, state: {status: 'UNKNOWN',
      detail: `missing=${[...missing, metricDetail].filter(Boolean).join(',')}`}};
  }
  if (invalid.length || metrics.status === 'NOT_MET') {
    return {floor, state: {status: 'NOT_MET',
      detail: `invalid=${[...invalid, metrics.status === 'NOT_MET' ? metrics.detail : ''].filter(Boolean).join(',')}`}};
  }
  if (!floor.campaign_id.startsWith(`${floor.cjcj_head_sha}-`)) {
    return {floor, state: {status: 'NOT_MET', detail: 'campaign_id does not bind cjcj_head_sha'}};
  }
  return {floor, state: {status: 'MET', detail: 'READY'}};
}

function validateG8Results(results) {
  if (!plainObject(results)) return {status: 'NOT_MET', detail: 'G8_FULL_GATE.json root must be an object'};
  const missing = [];
  const invalid = [];
  if (results.schema === undefined || results.schema === null) missing.push('schema');
  else if (results.schema !== 1) invalid.push(`schema=${String(results.schema)}`);
  for (const [field, pattern] of [
    ['campaign_id', /^[0-9a-f]{40}-[0-9]{8}T[0-9]{6}Z-[1-9][0-9]*$/],
    ['cjcj_head_sha', SHA40],
    ['captured_utc', /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/],
  ]) {
    const value = results[field];
    if (value === undefined || value === null) missing.push(field);
    else if (typeof value !== 'string' || !pattern.test(value)) invalid.push(field);
  }
  const metrics = validateG8Metrics(results.results, 'results');
  if (missing.length || metrics.status === 'UNKNOWN') {
    const metricDetail = metrics.status === 'UNKNOWN' ? metrics.detail.replace(/^missing=/, '') : '';
    return {status: 'UNKNOWN', detail: `missing=${[...missing, metricDetail].filter(Boolean).join(',')}`};
  }
  if (invalid.length || metrics.status === 'NOT_MET') {
    return {status: 'NOT_MET',
      detail: `invalid=${[...invalid, metrics.status === 'NOT_MET' ? metrics.detail : ''].filter(Boolean).join(',')}`};
  }
  return {status: 'MET', detail: 'complete'};
}

async function readG8Results(context, relative) {
  const root = path.resolve(context.evidence);
  const file = path.resolve(root, ...relative.split('/'));
  if (file !== root && !file.startsWith(`${root}${path.sep}`)) {
    throw new GateInputError('UNKNOWN', `G8 evidence path escapes archive root: ${relative}`);
  }
  return {file, text: await readAbsolute(file, {absence: 'UNKNOWN'})};
}

async function evaluateG8(context) {
  const {floor, state} = await loadG8Floor(context);
  if (state.status !== 'MET') {
    return gateResult('G8', state.status, `判据 0811 已更新；${state.detail}；旧 2005/2472/467 未沿用`);
  }
  if (!context.evidence) {
    return gateResult('G8', 'UNKNOWN',
      `判据 0811 已更新；floor=READY；missing=--evidence/${floor.evidence.results}`);
  }
  const evidence = await readG8Results(context, floor.evidence.results);
  const results = parseG2Json(evidence.text, evidence.file);
  const resultState = validateG8Results(results);
  if (resultState.status !== 'MET') {
    return gateResult('G8', resultState.status,
      `判据 0811 已更新；floor=READY；${floor.evidence.results} ${resultState.detail}`);
  }

  const failures = [];
  if (results.campaign_id !== floor.campaign_id) {
    failures.push(`campaign_id=${results.campaign_id} expected=${floor.campaign_id}`);
  }
  if (results.cjcj_head_sha !== floor.cjcj_head_sha) {
    failures.push(`cjcj_head_sha=${results.cjcj_head_sha} expected=${floor.cjcj_head_sha}`);
  }
  const baseline = floor.baseline;
  const current = results.results;
  if (current.difftest.total < baseline.difftest.total) {
    failures.push(`difftest.total=${current.difftest.total}<${baseline.difftest.total}`);
  }
  if (current.difftest.pass !== current.difftest.total || current.difftest.mismatch !== 0 ||
      current.difftest.fail !== 0) {
    failures.push(`difftest=${current.difftest.pass}/${current.difftest.total}` +
      ` mismatch=${current.difftest.mismatch} fail=${current.difftest.fail}`);
  }
  if (current.smoke.pass < baseline.smoke.pass || current.smoke.fail !== 0) {
    failures.push(`smoke=pass${current.smoke.pass}/fail${current.smoke.fail}; baseline_pass=${baseline.smoke.pass}`);
  }
  if (current.bcgate.shared < baseline.bcgate.shared ||
      current.bcgate.byte_identical < baseline.bcgate.byte_identical ||
      current.bcgate.differing > baseline.bcgate.differing || current.bcgate.compile_errors !== 0) {
    failures.push(`bcgate=shared${current.bcgate.shared}/identical${current.bcgate.byte_identical}` +
      `/differing${current.bcgate.differing}/compile_errors${current.bcgate.compile_errors}; ` +
      `baseline=${baseline.bcgate.shared}/${baseline.bcgate.byte_identical}/${baseline.bcgate.differing}`);
  }
  if (current.verify_exit !== 0) failures.push(`verify_exit=${current.verify_exit}`);
  if (failures.length) {
    return gateResult('G8', 'NOT_MET', `判据 0811 已更新；floor=${floor.campaign_id}; failures=${failures.join(';')}`);
  }
  return gateResult('G8', 'MET', `判据 0811 已更新；floor=${floor.campaign_id}; ` +
    `difftest=${current.difftest.pass}/${current.difftest.total} mismatch=0 fail=0; ` +
    `smoke=${current.smoke.pass}/0; bcgate shared=${current.bcgate.shared} ` +
    `byte_identical=${current.bcgate.byte_identical} differing=${current.bcgate.differing} compile_errors=0; ` +
    'VERIFY-EXIT=0');
}

function parseG12Tsv(text, label) {
  const lines = text.split(/\r?\n/).filter(line => line.length > 0);
  if (lines.length < 2) throw new GateInputError('UNKNOWN', `${label} has no data rows`);
  const header = lines[0].split('\t');
  if (header.some((name, index) => !name || header.indexOf(name) !== index)) {
    throw new GateInputError('UNKNOWN', `${label} has an invalid or duplicate TSV header`);
  }
  return lines.slice(1).map((line, rowIndex) => {
    const fields = line.split('\t');
    if (fields.length !== header.length) {
      throw new GateInputError('UNKNOWN',
        `${label} row ${rowIndex + 2} has ${fields.length} fields; expected ${header.length}`);
    }
    return Object.fromEntries(header.map((name, index) => [name, fields[index]]));
  });
}

function requireG12Columns(rows, names, label) {
  const available = new Set(Object.keys(rows[0] || {}));
  const missing = names.filter(name => !available.has(name));
  if (missing.length) throw new GateInputError('UNKNOWN', `${label} lacks columns: ${missing.join(',')}`);
}

function g12Integer(value, label) {
  if (!/^-?\d+$/.test(String(value))) {
    throw new GateInputError('UNKNOWN', `${label} is not an integer: ${value || '<empty>'}`);
  }
  const number = Number(value);
  if (!Number.isSafeInteger(number)) throw new GateInputError('UNKNOWN', `${label} is outside the safe integer range`);
  return number;
}

function g12Number(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new GateInputError('UNKNOWN', `${label} is not a finite number`);
  return number;
}

function g12Median(values) {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function g12Fields(line) {
  return Object.fromEntries([...line.matchAll(/(?:^|\s)([A-Za-z][A-Za-z0-9_]*)=([^\s]+)/g)]
    .map(match => [match[1], match[2]]));
}

function g12Criterion(id, status, value) {
  return {id, status, value};
}

function completeG12Rows(rows, predicate, runs, label) {
  const selected = rows.filter(predicate);
  const rounds = selected.map((row, index) => g12Integer(row.round, `${label}.round[${index}]`));
  const expected = Array.from({length: runs}, (_, index) => index + 1);
  const unique = [...new Set(rounds)].sort((left, right) => left - right);
  if (selected.length !== runs || JSON.stringify(unique) !== JSON.stringify(expected)) {
    return {status: 'UNKNOWN', rows: selected,
      reason: `${label} samples=${selected.length} unique_rounds=${unique.length}; expected=${runs}`};
  }
  return {status: 'MET', rows: selected};
}

async function loadG12Floor(context) {
  if (context.ref) throw new GateInputError('UNKNOWN', 'G12 evidence evaluation requires a checkout, not --ref');
  const file = path.join(context.repo, 'build', 'lib', 'gc-release-floor.mjs');
  let imported;
  try {
    imported = await import(pathToFileURL(file).href);
  } catch (error) {
    throw new GateInputError('UNKNOWN', `cannot load frozen G12 floor: ${error.code || error.message}`);
  }
  const floor = imported.GC_RELEASE_FLOOR;
  const blockers = floor?.blocking?.map(item => item.id);
  const records = floor?.recording?.map(item => item.id);
  if (floor?.schema !== 1 || JSON.stringify(blockers) !== JSON.stringify(['F1', 'F2', 'F3', 'F4', 'F5', 'F6']) ||
      JSON.stringify(records) !== JSON.stringify(['R1', 'R2', 'R3', 'R4'])) {
    throw new GateInputError('UNKNOWN', 'frozen G12 floor does not contain exactly F1-F6 and R1-R4');
  }
  return floor;
}

async function readG12Evidence(context, relative) {
  const root = path.resolve(context.evidence);
  const file = path.resolve(root, ...relative.split('/'));
  const withinRoot = file === root || file.startsWith(`${root}${path.sep}`);
  if (!withinRoot) throw new GateInputError('UNKNOWN', `G12 evidence path escapes archive root: ${relative}`);
  return readAbsolute(file, {absence: 'UNKNOWN'});
}

function validateG12Metadata(text, floor) {
  const {heap_mib: heap, workload_sha8: sha8, runs} = floor.measurement;
  if (!new RegExp(`\\b${sha8}[0-9a-f]{56}\\b`).test(text)) {
    throw new GateInputError('UNKNOWN', `G12 metadata lacks full workload SHA beginning ${sha8}`);
  }
  if (!new RegExp(`\\bHEAP=${heap}MB\\s+N=${runs}\\b`).test(text)) {
    throw new GateInputError('UNKNOWN', `G12 metadata lacks HEAP=${heap}MB N=${runs}`);
  }
  if (!/^[0-9a-f]{64}\s+.*libcangjie-runtime\.(?:so|dylib|dll)\b/m.test(text)) {
    throw new GateInputError('UNKNOWN', 'G12 metadata lacks runtime SHA-256');
  }
  if (!/\bCJRT-COMMIT:[0-9a-f]{40}\b/.test(text)) {
    throw new GateInputError('UNKNOWN', 'G12 metadata lacks a clean CJRT-COMMIT provenance stamp');
  }
  if (!/INTERLEAVE START\b/.test(text) || !/INTERLEAVE DONE\b/.test(text)) {
    throw new GateInputError('UNKNOWN', 'G12 metadata does not prove a completed interleaved window');
  }
}

function evaluateG12Runs(rows, floor, profileName) {
  requireG12Columns(rows, ['round', 'arm', 'load', 'rc', 'class', 'minor'], 'G12 runs.tsv');
  const profile = floor.measurement.profiles[profileName];
  const runs = floor.measurement.runs;
  const f1Floor = floor.blocking.find(item => item.id === 'F1');
  const f2Floor = floor.blocking.find(item => item.id === 'F2');
  const workload = completeG12Rows(rows,
    row => row.arm === profile.run_arm && row.load === 'nw_e75', runs, `${profileName}.nw_e75`);
  const hello = completeG12Rows(rows,
    row => row.arm === profile.run_arm && row.load === 'hello_alloc', runs, `${profileName}.hello_alloc`);
  const f1 = workload.status === 'UNKNOWN'
    ? g12Criterion('F1', 'UNKNOWN', workload.reason)
    : (() => {
        const rc0 = workload.rows.filter((row, index) =>
          g12Integer(row.rc, `${profileName}.nw_e75.rc[${index}]`) === 0).length;
        const passed = workload.rows.length === f1Floor.expected_runs && rc0 === f1Floor.expected_rc0;
        return g12Criterion('F1', passed ? 'MET' : 'NOT_MET',
          `N=${workload.rows.length} rc0=${rc0}/${f1Floor.expected_rc0}`);
      })();
  const f2 = hello.status === 'UNKNOWN'
    ? g12Criterion('F2', 'UNKNOWN', hello.reason)
    : (() => {
        const rc0 = hello.rows.filter((row, index) =>
          g12Integer(row.rc, `${profileName}.hello_alloc.rc[${index}]`) === 0).length;
        const gcRuns = hello.rows.filter((row, index) =>
          g12Integer(row.minor, `${profileName}.hello_alloc.minor[${index}]`) >=
            f2Floor.minimum_minor_cycles_per_run).length;
        const passed = hello.rows.length === f2Floor.expected_runs && rc0 === f2Floor.expected_rc0 &&
          gcRuns === f2Floor.expected_runs;
        return g12Criterion('F2', passed ? 'MET' : 'NOT_MET',
          `N=${hello.rows.length} rc0=${rc0}/${f2Floor.expected_rc0} gc_runs=${gcRuns}/${f2Floor.expected_runs}`);
      })();
  return {f1, f2};
}

function evaluateG12F3(candidateText, controlText, floor) {
  const criterion = floor.blocking.find(item => item.id === 'F3');
  const candidateLines = candidateText.split(/\r?\n/)
    .filter(line => line.includes('[GCV2][f3-deadarm]') && /\bpoint=atexit\b/.test(line));
  if (candidateLines.length !== floor.measurement.runs) {
    return g12Criterion('F3', 'UNKNOWN',
      `atexit_count_lines=${candidateLines.length}; expected=${floor.measurement.runs}`);
  }
  const candidate = candidateLines.reduce((sum, line, index) => {
    const fields = g12Fields(line);
    if (g12Integer(fields.class_sum_ok, `F3.class_sum_ok[${index}]`) !== 1) {
      throw new GateInputError('UNKNOWN', `F3 class_sum_ok is not 1 at sample ${index + 1}`);
    }
    return sum + g12Integer(fields.total, `F3.total[${index}]`);
  }, 0);
  const controlLines = controlText.split(/\r?\n/)
    .filter(line => line.includes('[GCV2][f3-deadarm]') && /\bpoint=atexit\b/.test(line));
  const control = controlLines.reduce((sum, line, index) =>
    sum + g12Integer(g12Fields(line).total, `F3.control.total[${index}]`), 0);
  if (control < criterion.positive_control_minimum) {
    return g12Criterion('F3', 'UNKNOWN',
      `count=${candidate} positive_control=${control}; required>=${criterion.positive_control_minimum}`);
  }
  return g12Criterion('F3', candidate <= criterion.maximum_count ? 'MET' : 'NOT_MET',
    `count=${candidate} maximum=${criterion.maximum_count} positive_control=${control}`);
}

function markSurvivalSignatureCount(text) {
  return text.split(/\r?\n/).filter(line => line.includes('[GCV2]') &&
    /\bsameWord=1\b/.test(line) && /\bmBit=1\b/.test(line) && /\bf3Bit=0\b/.test(line)).length;
}

function evaluateG12F4(candidateText, controlText, floor) {
  const criterion = floor.blocking.find(item => item.id === 'F4');
  const candidate = markSurvivalSignatureCount(candidateText);
  const control = markSurvivalSignatureCount(controlText);
  if (control < criterion.positive_control_minimum) {
    return g12Criterion('F4', 'UNKNOWN',
      `count=${candidate} positive_control=${control}; required>=${criterion.positive_control_minimum}`);
  }
  return g12Criterion('F4', candidate <= criterion.maximum_count ? 'MET' : 'NOT_MET',
    `count=${candidate} maximum=${criterion.maximum_count} positive_control=${control}`);
}

function evaluateG12F5(rows, floor, profileName) {
  requireG12Columns(rows,
    ['round', 'load', 'fys', 'rc', 'minors', 'missBareNeverSeen', 'remsetSizeHint', 'status'],
    'G12 remset.tsv');
  const criterion = floor.blocking.find(item => item.id === 'F5');
  const profile = floor.measurement.profiles[profileName];
  const counts = {};
  for (const load of criterion.loads) {
    const selected = completeG12Rows(rows,
      row => row.load === load && g12Integer(row.fys, `F5.${load}.fys`) === profile.full_young_scan,
      floor.measurement.runs, `${profileName}.remset.${load}`);
    if (selected.status === 'UNKNOWN') return g12Criterion('F5', 'UNKNOWN', selected.reason);
    for (const [index, row] of selected.rows.entries()) {
      if (g12Integer(row.rc, `F5.${load}.rc[${index}]`) !== 0 || row.status !== 'OK' ||
          g12Integer(row.minors, `F5.${load}.minors[${index}]`) < 1) {
        return g12Criterion('F5', 'UNKNOWN', `${profileName}.${load} has an incomplete counter run`);
      }
    }
    counts[load] = selected.rows.reduce((sum, row, index) =>
      sum + g12Integer(row.missBareNeverSeen, `F5.${load}.missBareNeverSeen[${index}]`), 0);
  }
  const controls = rows.filter(row => row.load === 'CTRL' &&
    g12Integer(row.fys, 'F5.CTRL.fys') === profile.full_young_scan);
  const control = controls.reduce((sum, row, index) =>
    sum + g12Integer(row.missBareNeverSeen, `F5.CTRL.missBareNeverSeen[${index}]`), 0);
  if (control < criterion.positive_control_minimum) {
    return g12Criterion('F5', 'UNKNOWN',
      `counts=${JSON.stringify(counts)} positive_control=${control}; required>=${criterion.positive_control_minimum}`);
  }
  const passed = Object.values(counts).every(count => count <= criterion.maximum_count);
  return g12Criterion('F5', passed ? 'MET' : 'NOT_MET',
    `O0=${counts.O0} O2=${counts.O2} maximum=${criterion.maximum_count} positive_control=${control}`);
}

function evaluateG12Records(remsetRows, throughputRows, phaseText, floor) {
  const phaseNames = floor.recording.find(item => item.id === 'R1').phases;
  const phaseUs = Object.fromEntries(phaseNames.map(name => [name, []]));
  for (const line of phaseText.split(/\r?\n/)) {
    const match = line.match(/\[GCLOG\].*\brec=phase\b.*\bname=(young\.[A-Za-z0-9_.-]+)\s+us=(\d+)\b/);
    if (match && Object.hasOwn(phaseUs, match[1])) phaseUs[match[1]].push(g12Integer(match[2], `R1.${match[1]}`));
  }
  if (Object.values(phaseUs).some(values => values.length === 0)) {
    throw new GateInputError('UNKNOWN', 'R1 lacks one or more four-pillar [GCLOG] phase records');
  }
  const phaseSums = Object.fromEntries(Object.entries(phaseUs)
    .map(([name, values]) => [name, values.reduce((sum, value) => sum + value, 0)]));
  const fourPillarTotal = Object.values(phaseSums).reduce((sum, value) => sum + value, 0);
  if (fourPillarTotal <= 0) throw new GateInputError('UNKNOWN', 'R1 four-pillar phase total is zero');
  const shares = Object.fromEntries(Object.entries(phaseSums)
    .map(([name, value]) => [name, Number((value / fourPillarTotal).toFixed(6))]));

  const defaultFys = floor.measurement.profiles.DEFAULT.full_young_scan;
  const remset = {};
  for (const load of floor.recording.find(item => item.id === 'R2').loads) {
    const selected = completeG12Rows(remsetRows,
      row => row.load === load && g12Integer(row.fys, `R2.${load}.fys`) === defaultFys,
      floor.measurement.runs, `R2.${load}`);
    if (selected.status === 'UNKNOWN') throw new GateInputError('UNKNOWN', selected.reason);
    const values = selected.rows.map((row, index) =>
      g12Integer(row.remsetSizeHint, `R2.${load}.remsetSizeHint[${index}]`));
    remset[load] = {median: g12Median(values), max: Math.max(...values)};
  }

  requireG12Columns(throughputRows, ['round', 'arm', 'rc', 'task_ms', 'minor', 'status'],
    'G12 throughput.tsv');
  const r3 = floor.recording.find(item => item.id === 'R3');
  const task = {};
  for (const arm of [r3.generational_arm, r3.minor_disabled_arm]) {
    const selected = completeG12Rows(throughputRows, row => row.arm === arm,
      floor.measurement.runs, `R3.${arm}`);
    if (selected.status === 'UNKNOWN') throw new GateInputError('UNKNOWN', selected.reason);
    for (const [index, row] of selected.rows.entries()) {
      if (g12Integer(row.rc, `R3.${arm}.rc[${index}]`) !== 0 || row.status !== 'OK') {
        throw new GateInputError('UNKNOWN', `R3 arm ${arm} contains an incomplete run`);
      }
      const minor = g12Integer(row.minor, `R3.${arm}.minor[${index}]`);
      if (arm === r3.minor_disabled_arm && minor !== 0) {
        throw new GateInputError('UNKNOWN', `R3 minor-disabled arm ${arm} observed minor=${minor}`);
      }
    }
    task[arm] = g12Median(selected.rows.map((row, index) =>
      g12Number(row.task_ms, `R3.${arm}.task_ms[${index}]`)));
  }
  if (task[r3.minor_disabled_arm] <= 0) throw new GateInputError('UNKNOWN', 'R3 denominator is not positive');
  const ratio = task[r3.generational_arm] / task[r3.minor_disabled_arm];

  const stw = [...phaseText.matchAll(/young collection stw time:\s*([0-9,]+)us/g)]
    .map((match, index) => g12Integer(match[1].replaceAll(',', ''), `R4.stw[${index}]`));
  if (stw.length === 0) throw new GateInputError('UNKNOWN', 'R4 lacks young collection STW duration lines');
  return [
    {id: 'R1', value: shares},
    {id: 'R2', value: remset},
    {id: 'R3', value: {median_task_ms: task, ratio: Number(ratio.toFixed(6))}},
    {id: 'R4', value: {samples: stw.length, median_us: g12Median(stw), max_us: Math.max(...stw)}},
  ];
}

async function evaluateG12(context) {
  const floor = await loadG12Floor(context);
  if (!context.evidence) {
    return gateResult('G12', 'UNKNOWN',
      'GC floor F1-F6 已冻结；未指定 --evidence，无法读取计数行/TSV/日志');
  }
  const profileFiles = floor.evidence.profiles;
  const [metadata, runText, remsetText, throughputText, phaseText,
    defaultF3, defaultF3Control, defaultF4, defaultF4Control,
    fys0F3, fys0F3Control, fys0F4, fys0F4Control] = await Promise.all([
    readG12Evidence(context, floor.evidence.metadata),
    readG12Evidence(context, floor.evidence.run_results),
    readG12Evidence(context, floor.evidence.remset_results),
    readG12Evidence(context, floor.evidence.throughput_results),
    readG12Evidence(context, floor.evidence.phase_log),
    readG12Evidence(context, profileFiles.DEFAULT.f3_counts),
    readG12Evidence(context, profileFiles.DEFAULT.f3_positive_control),
    readG12Evidence(context, profileFiles.DEFAULT.mark_survival),
    readG12Evidence(context, profileFiles.DEFAULT.mark_survival_positive_control),
    readG12Evidence(context, profileFiles.FYS0.f3_counts),
    readG12Evidence(context, profileFiles.FYS0.f3_positive_control),
    readG12Evidence(context, profileFiles.FYS0.mark_survival),
    readG12Evidence(context, profileFiles.FYS0.mark_survival_positive_control),
  ]);
  validateG12Metadata(metadata, floor);
  const runRows = parseG12Tsv(runText, 'G12 runs.tsv');
  const remsetRows = parseG12Tsv(remsetText, 'G12 remset.tsv');
  const throughputRows = parseG12Tsv(throughputText, 'G12 throughput.tsv');

  const defaultRuns = evaluateG12Runs(runRows, floor, 'DEFAULT');
  const defaultChecks = [
    defaultRuns.f1,
    defaultRuns.f2,
    evaluateG12F3(defaultF3, defaultF3Control, floor),
    evaluateG12F4(defaultF4, defaultF4Control, floor),
    evaluateG12F5(remsetRows, floor, 'DEFAULT'),
  ];
  const fys0Runs = evaluateG12Runs(runRows, floor, 'FYS0');
  const fys0Checks = [
    fys0Runs.f1,
    fys0Runs.f2,
    evaluateG12F3(fys0F3, fys0F3Control, floor),
    evaluateG12F4(fys0F4, fys0F4Control, floor),
    evaluateG12F5(remsetRows, floor, 'FYS0'),
  ];
  const f6Status = fys0Checks.some(item => item.status === 'UNKNOWN') ? 'UNKNOWN' :
    fys0Checks.every(item => item.status === 'MET') ? 'MET' : 'NOT_MET';
  const f6 = g12Criterion('F6', f6Status,
    `FYS=0 ${fys0Checks.map(item => `${item.id}:${item.status}`).join(',')}`);
  const checks = [...defaultChecks, f6];
  const records = evaluateG12Records(remsetRows, throughputRows, phaseText, floor);
  const status = checks.some(item => item.status === 'UNKNOWN') ? 'UNKNOWN' :
    checks.every(item => item.status === 'MET') ? 'MET' : 'NOT_MET';
  const values = checks.map(item => `${item.id}=${item.status}(${item.value})`).join('; ');
  return gateResult('G12', status, values, {
    floor: {release: floor.release, heap_mib: floor.measurement.heap_mib,
      workload_sha8: floor.measurement.workload_sha8, runs: floor.measurement.runs},
    checks,
    records,
  });
}

async function readG14Evidence(context, relative) {
  const root = path.resolve(context.evidence);
  const file = path.resolve(root, ...relative.split('/'));
  const withinRoot = file === root || file.startsWith(`${root}${path.sep}`);
  if (!withinRoot) throw new GateInputError('UNKNOWN', `G14 evidence path escapes archive root: ${relative}`);
  return readAbsolute(file, {absence: 'UNKNOWN'});
}

function g14ObservedFys(row, label) {
  const bound = String(row.fys_bound).split(',');
  if (bound.length === 0 || bound.some(value => !/^[01]$/.test(value))) {
    throw new GateInputError('UNKNOWN', `${label}.fys_bound does not contain runtime FYS values`);
  }
  const first = g12Integer(row.fallbackFullScan_obs, `${label}.fallbackFullScan_obs`);
  if (first !== 0 && first !== 1) {
    throw new GateInputError('UNKNOWN', `${label}.fallbackFullScan_obs is not 0 or 1`);
  }
  return new Set([...bound.map(Number), first]);
}

function g14Distribution(rows, field, label) {
  const values = rows.map((row, index) => g12Integer(row[field], `${label}.${field}[${index}]`));
  if (values.some(value => value < 0)) {
    throw new GateInputError('UNKNOWN', `${label}.${field} contains a negative count`);
  }
  return {
    nonzero_runs: values.filter(value => value > 0).length,
    sum: values.reduce((sum, value) => sum + value, 0),
    max: Math.max(...values),
  };
}

async function evaluateG14(context) {
  const [manifest, release] = await Promise.all([
    readFile(context, 'build/lib/release-manifest.mjs'),
    readFile(context, '.github/workflows/release.yml'),
  ]);
  const text = `${manifest}\n${release}`;
  const choice = text.match(/idle[_-]?writer[_-]?policy\s*[:=]\s*['"](FYS_CENSUS|ZERO_MISS)['"]/i)?.[1];
  if (!choice) return gateResult('G14', 'NOT_MET', 'release config 未记录 A=FYS_CENSUS 或 B=ZERO_MISS 的唯一选择');
  if (!context.evidence) {
    return gateResult('G14', 'UNKNOWN',
      `release choice=${choice}; 未指定 --evidence，无法读取运行期 FYS 与 N20 remsetMiss/missBare 证据`);
  }

  const expectedFys = choice === 'FYS_CENSUS' ? 1 : 0;
  const [rawText, remsetText] = await Promise.all([
    readG14Evidence(context, 'raw.tsv'),
    readG14Evidence(context, 'remset.tsv'),
  ]);
  const rawRows = parseG12Tsv(rawText, 'G14 raw.tsv');
  const remsetRows = parseG12Tsv(remsetText, 'G14 remset.tsv');
  const remsetColumns = [
    'round', 'load', 'fys', 'rc', 'minors', 'remsetMiss', 'missBare', 'missBareNeverSeen', 'status',
  ];
  const rawColumns = [
    'round', 'load', 'fys', 'rc', 'minors', 'miss', 'missBare', 'missBareNeverSeen', 'status',
    'fys_bound', 'fallbackFullScan_obs',
  ];
  requireG12Columns(rawRows, rawColumns, 'G14 raw.tsv');
  requireG12Columns(remsetRows, remsetColumns, 'G14 remset.tsv');

  const samples = {};
  const bindingMismatches = [];
  for (const load of ['O0', 'O2']) {
    const raw = completeG12Rows(rawRows,
      row => row.load === load && g12Integer(row.fys, `G14.raw.${load}.fys`) === expectedFys,
      20, `G14.raw.${load}.FYS${expectedFys}`);
    const remset = completeG12Rows(remsetRows,
      row => row.load === load && g12Integer(row.fys, `G14.remset.${load}.fys`) === expectedFys,
      20, `G14.remset.${load}.FYS${expectedFys}`);
    if (raw.status === 'UNKNOWN') throw new GateInputError('UNKNOWN', raw.reason);
    if (remset.status === 'UNKNOWN') throw new GateInputError('UNKNOWN', remset.reason);

    const rawByRound = new Map(raw.rows.map(row => [g12Integer(row.round, `G14.raw.${load}.round`), row]));
    for (const [index, row] of remset.rows.entries()) {
      const round = g12Integer(row.round, `G14.remset.${load}.round[${index}]`);
      const rawRow = rawByRound.get(round);
      for (const [rawField, remsetField] of [
        ['rc', 'rc'], ['minors', 'minors'], ['miss', 'remsetMiss'],
        ['missBare', 'missBare'], ['missBareNeverSeen', 'missBareNeverSeen'],
      ]) {
        const rawValue = g12Integer(rawRow[rawField], `G14.raw.${load}.${rawField}[${index}]`);
        const remsetValue = g12Integer(row[remsetField], `G14.remset.${load}.${remsetField}[${index}]`);
        if (rawValue !== remsetValue) {
          throw new GateInputError('UNKNOWN',
            `G14 ${load} round=${round} disagrees between raw.tsv and remset.tsv for ${remsetField}`);
        }
      }
      if (row.status !== 'OK' || rawRow.status !== 'OK' || g12Integer(row.rc, `G14.${load}.rc[${index}]`) !== 0 ||
          g12Integer(row.minors, `G14.${load}.minors[${index}]`) < 1) {
        throw new GateInputError('UNKNOWN', `G14 ${load} round=${round} is not a complete counter run`);
      }
      const observed = g14ObservedFys(rawRow, `G14.raw.${load}[${index}]`);
      if (observed.size !== 1 || !observed.has(expectedFys)) bindingMismatches.push(`${load}:r${round}`);
    }
    samples[load] = {
      runs: remset.rows.length,
      remsetMiss: g14Distribution(remset.rows, 'remsetMiss', `G14.${load}`),
      missBare: g14Distribution(remset.rows, 'missBare', `G14.${load}`),
      missBareNeverSeen: g14Distribution(remset.rows, 'missBareNeverSeen', `G14.${load}`),
    };
  }

  if (bindingMismatches.length > 0) {
    return gateResult('G14', 'NOT_MET',
      `release choice=${choice}; runtime FYS expected=${expectedFys}, mismatched=${bindingMismatches.length}/40 (${bindingMismatches.join(',')})`,
      {choice, expected_fys: expectedFys, samples});
  }
  const summary = Object.entries(samples).map(([load, value]) =>
    `${load}:N=${value.runs} remsetMiss[nz=${value.remsetMiss.nonzero_runs},sum=${value.remsetMiss.sum},max=${value.remsetMiss.max}] ` +
      `missBareNeverSeen[nz=${value.missBareNeverSeen.nonzero_runs},sum=${value.missBareNeverSeen.sum},max=${value.missBareNeverSeen.max}]`)
    .join('; ');
  const zeroMiss = Object.values(samples).every(sample =>
    sample.remsetMiss.sum === 0 && sample.missBare.sum === 0);
  const status = choice === 'FYS_CENSUS' || zeroMiss ? 'MET' : 'NOT_MET';
  const criterion = choice === 'FYS_CENSUS' ? 'census distribution recorded' : `zero_miss=${zeroMiss}`;
  return gateResult('G14', status,
    `release choice=${choice}; runtime FYS=${expectedFys} bound=40/40; ${summary}; ${criterion}`,
    {choice, expected_fys: expectedFys, samples});
}

async function evaluateG15(context) {
  const [python, packageWorkflow, release] = await Promise.all([
    readFile(context, 'build/lib/python-bundle.mjs'),
    readFile(context, '.github/workflows/build-release-package.yml'),
    readFile(context, '.github/workflows/release.yml'),
  ]);
  const version = python.match(/RELEASE_PYTHON_VERSION\s*=\s*['"](3\.11\.\d+)['"]/)?.[1] || '';
  const bundleArgs = packageWorkflow.match(/--python-bundle/g)?.length || 0;
  const verifiers = packageWorkflow.match(/verify_packaged_cjdb\.mjs/g)?.length || 0;
  const packageJobs = release.match(/uses:\s*\.\/\.github\/workflows\/build-release-package\.yml/g)?.length || 0;
  const structural = Boolean(version) && bundleArgs === 2 && verifiers === 2 && packageJobs === 5;
  if (!structural) {
    return gateResult('G15', 'NOT_MET',
      `python=${version || '<missing>'} python_bundle_args=${bundleArgs} cjdb_verifiers=${verifiers} package_jobs=${packageJobs}`);
  }
  const tests = runTests(context, [
    'build/test/python-bundle.test.mjs',
    'ci/srcbuild/tests/release-wire.test.mjs',
  ]);
  return gateResult('G15', tests.status,
    `policy=A bundled Python ${version}; package_jobs=5 unix+windows verifiers=2; ${tests.detail}`);
}

async function evaluateG16(context) {
  const manifest = await readFile(context, 'build/lib/release-manifest.mjs');
  const policy = manifest.match(/RELEASE_SIGNATURE_POLICY\s*=\s*['"]([^'"]+)['"]/)?.[1] || '';
  const allowed = ['SHA_ONLY', 'SIGNED', 'SIGNED+SBOM'];
  if (!allowed.includes(policy)) return gateResult('G16', 'NOT_MET', `signature_policy=${policy || '<empty>'}`);
  const tests = runTests(context, ['build/test/release-manifest.test.mjs']);
  return gateResult('G16', tests.status, `signature_policy=${policy}; ${tests.detail}`);
}

async function evaluateG17(context) {
  const [policy, runbook, manifestSource, ciWorkflow] = await Promise.all([
    readFile(context, 'ops/design/DRYRUN_EXECUTION_POLICY.md'),
    readFile(context, 'ops/coord/RELEASE_0_0_2_RUNBOOK.md'),
    readFile(context, 'ci/test-manifest.mjs'),
    readFile(context, '.github/workflows/ci.yml'),
  ]);
  const ready = /EXECUTION_UNBLOCKED_PENDING_USER_APPROVAL/.test(policy);
  const runbookShape = /freeze[^\n]*producer[^\n]*dry-run|freeze[^\n]*候选 run/i.test(runbook);
  const manifestLive = /phase-control\.test\.mjs/.test(manifestSource) &&
    /node ci\/test-manifest\.mjs list/.test(ciWorkflow);
  if (!(ready && runbookShape && manifestLive)) {
    return gateResult('G17', 'NOT_MET', `policy_ready=${ready} runbook=${runbookShape} phase_test_live=${manifestLive}`);
  }
  const tests = runTests(context, [
    'ci/srcbuild/tests/phase-control.test.mjs',
    'ci/test-manifest.test.mjs',
  ]);
  return gateResult('G17', tests.status,
    `policy=EXECUTION_UNBLOCKED_PENDING_USER_APPROVAL runbook=yes phase_test_live=yes; ${tests.detail}`);
}

async function evaluate(gate, context) {
  if (GATES[gate].needsRun) return gateResult(gate, 'UNKNOWN', `NEEDS_RUN: ${GATES[gate].needsRun}`);
  const evaluators = {
    G1: evaluateG1,
    G2: evaluateG2,
    G4: evaluateG4,
    G5: evaluateG5,
    G8: evaluateG8,
    G12: evaluateG12,
    G13: contextValue => loaderlifeResult(contextValue),
    G14: evaluateG14,
    G15: evaluateG15,
    G16: evaluateG16,
    G17: evaluateG17,
  };
  try {
    return await evaluators[gate](await discoverEvidenceContext(gate, context));
  } catch (error) {
    if (error instanceof GateInputError) return gateResult(gate, error.kind, error.message);
    return gateResult(gate, 'UNKNOWN', `unexpected evaluator error: ${error.message}`);
  }
}

function escapeCell(value) {
  return String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
}

function printTable(results) {
  console.log('| 门 | 状态 | 依据命令 | 上次算出来的值 |');
  console.log('|---|---|---|---|');
  for (const result of results) {
    const label = `${result.gate} ${result.name}${result.criterion_updated_0811 ? '（判据 0811 已更新）' : ''}`;
    console.log(`| ${escapeCell(label)} | ${result.status} | ${escapeCell(result.command)} | ${escapeCell(result.value)} |`);
  }
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    console.log(usage());
    return;
  }
  const selected = options.selection === 'ALL' ? Object.keys(GATES) : [options.selection];
  const results = [];
  for (const gate of selected) results.push(await evaluate(gate, options));
  if (options.json) console.log(JSON.stringify(options.selection === 'ALL' ? results : results[0], null, 2));
  else if (options.selection === 'ALL') printTable(results);
  else printTable(results);
  if (options.selection !== 'ALL') {
    process.exitCode = results[0].status === 'MET' ? 0 : results[0].status === 'NOT_MET' ? 1 : 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}

export {GATES, evaluate, parseArguments};
