#!/usr/bin/env node
// The release matrix, derived from build/lib/targets.mjs (cjcj#73, P24).
//
//   plan  [--platforms all|k1,k2] [--github-output FILE] [--summary FILE]
//         Emit the matrices release-matrix.yml fans out over: source cells,
//         package cells, blocked cells (a platform some tuple or capability has
//         no producer for -- it gets a job that fails naming the gap, never a
//         silent skip), and excluded keys. An empty selection is an error.
//   check --platform KEY
//         Run on the platform's runner: assert the host matches the contract
//         and probe the capabilities the platform needs. Exit 1 with MISSING /
//         BLOCKED lines when anything is absent. Blocked platforms always exit 1.
//   table Markdown table of all fourteen platforms for humans.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';
import {
  RELEASE_REQUIREMENTS,
  allReleasePlatforms,
  getReleasePlatform,
  getTarget,
  hostContract,
  releasePlatformReadiness,
} from '../../build/lib/targets.mjs';

const runnerOs = os => ({linux: 'Linux', darwin: 'macOS', win32: 'Windows'})[os];

// The GitHub-hosted runner label's platform and architecture, from its name.
export function runnerHost(runner) {
  if (/^ubuntu-/.test(runner)) return {platform: 'linux', arch: runner.endsWith('-arm') ? 'arm64' : 'x64'};
  if (/^macos-/.test(runner)) return {platform: 'darwin', arch: runner.endsWith('-intel') || runner.endsWith('-large') ? 'x64' : 'arm64'};
  if (/^windows-/.test(runner)) return {platform: 'win32', arch: 'x64'};
  throw new Error(`unknown runner label '${runner}'`);
}

// target key -> the artifact name its source cell uploads its final std under.
const stdArtifact = target => `final-std-${target}`;

export function selectPlatforms(requested) {
  const all = allReleasePlatforms();
  if (!requested || requested === 'all') return all;
  const wanted = requested.split(',').map(entry => entry.trim()).filter(Boolean);
  const unknown = wanted.filter(key => !all.includes(key));
  if (unknown.length) throw new Error(`unknown release platform(s): ${unknown.join(', ')}; valid: ${all.join(', ')}`);
  return all.filter(key => wanted.includes(key));
}

export function planMatrix(requested) {
  const selected = selectPlatforms(requested);
  const source = new Map();
  const packages = [];
  const blocked = [];
  const excluded = [];
  for (const key of selected) {
    const readiness = releasePlatformReadiness(key);
    if (readiness.status === 'excluded') {
      excluded.push({release_key: key, reason: readiness.reasons[0]});
      continue;
    }
    if (readiness.status === 'blocked') {
      blocked.push({release_key: key, runner: readiness.runner, reasons: readiness.reasons.join(' | ')});
      continue;
    }
    const host = getTarget(readiness.host);
    const crossTuples = Object.keys(readiness.crossStd);
    if (crossTuples.length > 1) {
      throw new Error(`${key}: build-release-package.yml takes one cross std, platform carries ${crossTuples.length}: ${crossTuples.join(', ')}`);
    }
    const [crossTuple] = crossTuples;
    const crossTarget = crossTuple ? [...new Set(Object.values(readiness.crossStd))][0] : '';
    if (!source.has(readiness.sourceTarget)) source.set(readiness.sourceTarget, {target: readiness.sourceTarget});
    // A cross std is built by another platform's source cell; selecting the
    // consumer selects its producer, the same edge release.yml draws.
    if (crossTarget && !source.has(crossTarget)) source.set(crossTarget, {target: crossTarget});
    if (crossTuple) {
      // The cross std artifact is named after the tuple's own target key
      // (final-std-windows-x64), produced by the linux-x64 source cell.
      const tupleTarget = [...allTargetKeysForTuple(crossTuple)][0];
      packages.push(packageRow(key, readiness, host, {artifact: stdArtifact(tupleTarget), tuple: crossTuple, producer: crossTarget}));
    } else {
      packages.push(packageRow(key, readiness, host, null));
    }
  }
  if (source.size + packages.length + blocked.length + excluded.length === 0) {
    throw new Error(`no release platform selected from '${requested}'`);
  }
  const windowsSide = packages.some(row => row.host_std_cross_built === 'true');
  return Object.freeze({
    selected,
    source: [...source.values()],
    package: packages,
    blocked,
    excluded,
    windowsSide,
  });
}

function allTargetKeysForTuple(tuple) {
  const keys = new Set();
  for (const target of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64', 'windows-x64']) {
    if (getTarget(target).spec.runtimeTuple === tuple) keys.add(target);
  }
  if (keys.size === 0) throw new Error(`no target owns tuple ${tuple}`);
  return keys;
}

function packageRow(key, readiness, host, cross) {
  const windows = host.spec.crossCompile;
  return {
    release_key: key,
    platform: readiness.host,
    runner: readiness.runner,
    llvm_platform: host.spec.llvmPlatform,
    sdk_runtime_dir: host.spec.runtimeTuple,
    // Windows produces its final compiler inside the package job (W2); every
    // native host hands its own final-compiler-<target> over.
    compiler_artifact: windows ? '' : `final-compiler-${readiness.host}`,
    std_artifact: stdArtifact(readiness.host),
    cross_std_artifact: cross ? cross.artifact : '',
    cross_std_tuple: cross ? cross.tuple : '',
    host_std_cross_built: windows ? 'true' : 'false',
  };
}

// Capability probes, run on the runner itself.
export function probeRequirement(name, env = process.env, exec = execFileSync) {
  const contract = RELEASE_REQUIREMENTS[name];
  if (!contract) throw new Error(`unknown requirement '${name}'`);
  if (contract.envCandidates) {
    for (const variable of contract.envCandidates) {
      const root = env[variable];
      if (root && fs.existsSync(path.join(root, contract.marker))) return {present: true, detail: `${variable}=${root}`};
    }
    return {present: false, detail: `none of ${contract.envCandidates.join('/')} points at a directory containing ${contract.marker}`};
  }
  if (contract.xcrunSdks) {
    const found = [];
    for (const sdk of contract.xcrunSdks) {
      try {
        const out = exec('xcrun', ['--sdk', sdk, '--show-sdk-path'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).trim();
        if (out) found.push(`${sdk}=${out}`);
      } catch {
        return {present: false, detail: `xcrun --sdk ${sdk} --show-sdk-path failed (found: ${found.join(', ') || 'none'})`};
      }
    }
    return {present: true, detail: found.join(', ')};
  }
  throw new Error(`requirement '${name}' declares no probe`);
}

export function checkPlatform(key, {platform = process.platform, arch = process.arch, env = process.env, exec = execFileSync} = {}) {
  const readiness = releasePlatformReadiness(key);
  const definition = getReleasePlatform(key);
  const lines = [];
  const problems = [];
  const expected = runnerHost(readiness.runner);
  lines.push(`PLATFORM ${key} status=${readiness.status} host=${readiness.host} runner=${readiness.runner} source_target=${readiness.sourceTarget || '-'}`);
  if (platform !== expected.platform || arch !== expected.arch) {
    problems.push(`HOST mismatch: runner ${readiness.runner} is ${expected.platform}/${expected.arch}, this job runs on ${platform}/${arch}`);
  } else {
    lines.push(`HOST ok ${platform}/${arch} (${readiness.runner})`);
  }
  if (readiness.status === 'buildable') {
    // The package host contract from targets.mjs, for the native package hosts.
    const contract = hostContract(readiness.host);
    if (!contract.crossCompile) lines.push(`CONTRACT ${contract.requiredHost}`);
  }
  for (const requirement of definition.requires) {
    const probe = probeRequirement(requirement, env, exec);
    lines.push(`${probe.present ? 'PRESENT' : 'MISSING'} ${requirement}: ${probe.detail}`);
    if (!probe.present) problems.push(`MISSING ${requirement}: ${RELEASE_REQUIREMENTS[requirement].summary} (${probe.detail})`);
  }
  for (const reason of readiness.reasons) problems.push(`${readiness.status.toUpperCase()} ${reason}`);
  return {ok: problems.length === 0, lines, problems, readiness};
}

export function renderTable() {
  const rows = allReleasePlatforms().map(key => {
    const readiness = releasePlatformReadiness(key);
    const definition = getReleasePlatform(key);
    const tuples = [getTarget(definition.host).spec.runtimeTuple, ...definition.crossTuples].join(', ');
    const dropped = definition.droppedTuples.length ? definition.droppedTuples.join(', ') : '-';
    const requires = definition.requires.length ? definition.requires.join(', ') : '-';
    const runnerText = `${readiness.runner} (${runnerOs(runnerHost(readiness.runner).platform)}/${runnerHost(readiness.runner).arch})`;
    return `| ${key} | ${definition.officialArchive} | ${readiness.host} | ${runnerText} | ${tuples} | ${dropped} | ${requires} | ${readiness.status} | ${readiness.reasons.join('; ') || '-'} |`;
  });
  return [
    '| official key | official archive | host SDK (target key) | runner | tuples carried | dropped (ARM32) | runner needs | status | why not buildable |',
    '|---|---|---|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function writeOutputs(file, plan) {
  const lines = [
    `selected=${plan.selected.join(',')}`,
    `source_matrix=${JSON.stringify({include: plan.source})}`,
    `package_matrix=${JSON.stringify({include: plan.package})}`,
    `blocked_matrix=${JSON.stringify({include: plan.blocked})}`,
    `excluded=${plan.excluded.map(entry => entry.release_key).join(',')}`,
    `package_keys=${plan.package.map(row => row.platform).join(',')}`,
    `has_source=${plan.source.length > 0}`,
    `has_package=${plan.package.length > 0}`,
    `has_blocked=${plan.blocked.length > 0}`,
    `windows_side=${plan.windowsSide}`,
  ];
  fs.appendFileSync(file, `${lines.join('\n')}\n`);
}

function renderPlanSummary(plan) {
  const lines = ['### Release matrix plan', ''];
  lines.push(`selected: ${plan.selected.join(', ')}`, '');
  lines.push('| cell | platforms |', '|---|---|');
  lines.push(`| source | ${plan.source.map(row => row.target).join(', ') || '-'} |`);
  lines.push(`| package | ${plan.package.map(row => `${row.release_key} → ${row.platform} on ${row.runner}`).join('<br>') || '-'} |`);
  lines.push(`| blocked (red by design) | ${plan.blocked.map(row => `${row.release_key} on ${row.runner}`).join('<br>') || '-'} |`);
  lines.push(`| excluded | ${plan.excluded.map(row => `${row.release_key}: ${row.reason}`).join('<br>') || '-'} |`);
  lines.push(`| windows-side jobs | ${plan.windowsSide} |`);
  return `${lines.join('\n')}\n\n`;
}

export function main(argv, {log = console.log, error = console.error} = {}) {
  const [command, ...rest] = argv;
  const {values} = parseArgs({
    args: rest,
    options: {
      platforms: {type: 'string', default: 'all'},
      platform: {type: 'string'},
      'github-output': {type: 'string'},
      summary: {type: 'string'},
    },
  });
  if (command === 'plan') {
    const plan = planMatrix(values.platforms);
    log(JSON.stringify(plan, null, 2));
    if (values['github-output']) writeOutputs(values['github-output'], plan);
    if (values.summary) fs.appendFileSync(values.summary, renderPlanSummary(plan));
    return 0;
  }
  if (command === 'check') {
    if (!values.platform) throw new Error('check requires --platform');
    const result = checkPlatform(values.platform);
    for (const line of result.lines) log(line);
    for (const problem of result.problems) error(`::error::${values.platform}: ${problem}`);
    if (values.summary) {
      fs.appendFileSync(values.summary, `### ${values.platform}: ${result.ok ? 'ready' : result.readiness.status}\n\n${[...result.lines, ...result.problems].map(line => `- ${line}`).join('\n')}\n\n`);
    }
    return result.ok ? 0 : 1;
  }
  if (command === 'table') {
    log(renderTable());
    return 0;
  }
  throw new Error('usage: platform-matrix.mjs plan|check|table ...');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    process.exitCode = 2;
  }
}
