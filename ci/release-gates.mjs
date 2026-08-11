#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO = path.resolve(HERE, '..');
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const STATUSES = new Set(['MET', 'NOT_MET', 'UNKNOWN']);
const PLATFORMS = ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64'];

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

async function defaultFreezePath(context) {
  const runbook = await readFile(context, 'ops/coord/RELEASE_0_0_2_RUNBOOK.md', {absence: 'UNKNOWN'});
  const root = runbook.match(/^export RELEASE_EVIDENCE_ROOT=(.+)$/m)?.[1]?.trim();
  if (!root || root.includes('<')) {
    throw new GateInputError('UNKNOWN', 'runbook does not expose one concrete RELEASE_EVIDENCE_ROOT');
  }
  return path.join(root, 'FREEZE.json');
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

async function evaluateG2(context) {
  const ancestry = await loaderlifeResult(context, 'G2');
  if (ancestry.status !== 'MET') return ancestry;
  if (!context.evidence) {
    return gateResult('G2', 'UNKNOWN', `${ancestry.value}; 未指定持久 evidence，无法读取同轮 runtime 动/静态库、LLVM、cjcj、std 的二进制戳与 dirty 状态`);
  }
  const verifier = path.join(context.repo, 'scripts/archive_release_evidence.mjs');
  const verified = spawn(process.execPath, [verifier, 'verify', '--archive', context.evidence], {cwd: context.repo});
  if (verified.error) return gateResult('G2', 'UNKNOWN', `evidence verifier unavailable: ${verified.error.message}`);
  if (verified.status !== 0) return gateResult('G2', 'NOT_MET', `evidence rejected: ${commandFailure(verified)}`);
  return gateResult('G2', 'UNKNOWN', 'release evidence archive is internally valid, but its current schema does not enumerate both runtime dynamic/static artifacts; G2 cannot be promoted to MET from incomplete identity evidence');
}

function runTests(context, files) {
  if (context.ref) throw new GateInputError('UNKNOWN', 'targeted node tests cannot run against --ref without a checkout');
  const result = spawn(process.execPath, ['--test', '--test-timeout=300000', ...files], {cwd: context.repo});
  if (result.error) throw new GateInputError('UNKNOWN', `node test runner unavailable: ${result.error.message}`);
  if (result.status !== 0) return {status: 'NOT_MET', detail: commandFailure(result)};
  const pass = result.stdout.match(/^# pass (\d+)$/m)?.[1] || '?';
  const fail = result.stdout.match(/^# fail (\d+)$/m)?.[1] || '?';
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

async function evaluateG8(context) {
  const manifest = await readFile(context, 'build/lib/release-manifest.mjs');
  const recordsFreezeBaseline = /(?:freeze|frozen)[A-Za-z0-9_]*baseline/i.test(manifest) &&
    ['difftest', 'smoke', 'bcgate', 'verify_exit'].every(field => manifest.includes(field));
  if (!recordsFreezeBaseline) {
    return gateResult('G8', 'NOT_MET', '判据 0811 已更新；release manifest 尚未记录 freeze 基线的 difftest/smoke/bcgate/VERIFY 数值，旧 2005/2472/467 不沿用');
  }
  return gateResult('G8', 'UNKNOWN', '判据 0811 已更新；manifest 已有 freeze-baseline 字段，但未提供绑定当前 freeze 的实测 manifest，不能判 MET/NOT_MET');
}

async function evaluateG12(context) {
  const [manifest, release] = await Promise.all([
    readFile(context, 'build/lib/release-manifest.mjs'),
    readFile(context, '.github/workflows/release.yml'),
  ]);
  const text = `${manifest}\n${release}`;
  const hasFrozenIntegers = /gc[_-]?release[_-]?floor/i.test(text) &&
    ['DEFAULT', 'GOLD', 'ALOT'].every(name => new RegExp(`${name}[^\\n]*(?:N20|N10|ok)`, 'i').test(text));
  return hasFrozenIntegers
    ? gateResult('G12', 'UNKNOWN', '整数 GC floor 已接入 release 配置；未提供同 final archive 的 NEW/GOLD/ALOT 结果，不能继续判定')
    : gateResult('G12', 'NOT_MET', 'release manifest/workflow 中没有冻结的 DEFAULT/GOLD/ALOT 整数门值');
}

async function evaluateG14(context) {
  const [manifest, release] = await Promise.all([
    readFile(context, 'build/lib/release-manifest.mjs'),
    readFile(context, '.github/workflows/release.yml'),
  ]);
  const text = `${manifest}\n${release}`;
  const choice = text.match(/idle[_-]?writer[_-]?policy\s*[:=]\s*['"](FYS_CENSUS|ZERO_MISS)['"]/i)?.[1];
  if (!choice) return gateResult('G14', 'NOT_MET', 'release config 未记录 A=FYS_CENSUS 或 B=ZERO_MISS 的唯一选择');
  return gateResult('G14', 'UNKNOWN', `release choice=${choice}; 尚无与该选择绑定的启动日志或 N20 remsetMiss/missBare 证据`);
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
    return await evaluators[gate](context);
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
