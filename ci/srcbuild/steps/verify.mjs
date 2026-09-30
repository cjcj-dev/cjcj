#!/usr/bin/env zx

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {assertPackagedLineage} from '../../../build/lib/package-lineage.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {verifyRepeatedCjo} from '../verify-repeated-cjo.mjs';

$.stdio = 'inherit';

const root = path.resolve(import.meta.dirname, '../../..');
const sdk = argv._.map(String).filter(value => !value.startsWith('-'))[0];
if (!sdk) throw new Error('usage: verify.mjs [--no-fail-fast] <sdk-dir>');
// Diagnostic mode only. The default is unchanged: the first failing phase ends
// the run, so the release gate keeps failing exactly where it failed before.
// With --no-fail-fast every phase is still attempted, the failures are all
// collected, and the run still exits non-zero so every SDK phase can be
// measured in one pass without changing its failure criteria.
const noFailFast = process.env.CJCJ_VERIFY_NO_FAIL_FAST === '1'
  || argv['fail-fast'] === false
  || process.argv.includes('--no-fail-fast');
const phaseResults = [];

// zx puts the useful part of a failed command ("exit code: 1") below the stack
// frames and leaves the first line of the message empty, so a naive first-line
// slice makes every process failure render as an empty detail.
function describeFailure(error) {
  const lines = String(error?.message ?? error).split('\n').map(line => line.trim()).filter(Boolean);
  const head = lines.find(line => !line.startsWith('at ') && line !== 'Error:') || lines[0] || String(error);
  const fields = [];
  if (typeof error?.exitCode === 'number') fields.push(`exit=${error.exitCode}`);
  if (error?.signal) fields.push(`signal=${error.signal}`);
  if (fields.length === 0 || !head.startsWith('exit code:')) fields.push(head);
  return fields.join(' ').slice(0, 400) || String(error);
}

async function phase(name, body) {
  const started = process.hrtime.bigint();
  try {
    await body();
    const wall = Number(process.hrtime.bigint() - started) / 1e9;
    phaseResults.push({name, status: 'PASS', wall, detail: ''});
    if (noFailFast) console.log(`[phase] ${name} PASS wall=${wall.toFixed(3)}s`);
  } catch (error) {
    if (!noFailFast) throw error;
    const wall = Number(process.hrtime.bigint() - started) / 1e9;
    const detail = describeFailure(error);
    phaseResults.push({name, status: 'FAIL', wall, detail});
    console.error(`[phase] ${name} FAIL wall=${wall.toFixed(3)}s detail=${detail}`);
  }
}
const workspace = process.env.CANGJIE_WORKSPACE;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
if (!workspace || !targetKey) throw new Error('CANGJIE_WORKSPACE and CJCJ_SRCBUILD_TARGET are required');
const target = getTarget(targetKey);
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}
const self = `${sdk}/bin/cjc`;
const timeoutCommand = target.spec.os === 'darwin' ? 'gtimeout' : 'timeout';

await $`test -x ${self}`;
process.env.CANGJIE_HOME = sdk;
process.env.PATH = `${sdk}/bin:${sdk}/tools/bin:${process.env.PATH}`;
const libraryPath = [
  `${sdk}/third_party/llvm/lib`,
  `${sdk}/runtime/lib/${target.spec.runtimeTuple}`,
  `${sdk}/tools/lib`,
  process.env[target.spec.loaderEnv] || '',
].filter(Boolean).join(path.delimiter);
process.env[target.spec.loaderEnv] = libraryPath;
if (target.spec.os === 'darwin') process.env.DYLD_FALLBACK_LIBRARY_PATH = libraryPath;
process.env.cjHeapSize ||= '12GB';

const work = `${process.env.RUNNER_TEMP || '/tmp'}/cjcj-srcbuild-verify`;
await fs.rm(work, {recursive: true, force: true});
await fs.mkdir(work, {recursive: true});

async function probeTempExec(rootDir, label) {
  if (!rootDir) return `${label}=unset`;
  let probeDir;
  try {
    probeDir = await fs.mkdtemp(path.join(rootDir, 'cjcj-preflight-exec-'));
    const probe = path.join(probeDir, 'probe.sh');
    await fs.writeFile(probe, '#!/bin/sh\nexit 0\n', {mode: 0o755});
    const result = await $({nothrow: true, quiet: true, stdio: 'pipe'})`${probe}`;
    const mount = target.spec.os === 'darwin'
      ? await $({nothrow: true, quiet: true, stdio: 'pipe'})`df -P ${probeDir}`
      : await $({nothrow: true, quiet: true, stdio: 'pipe'})`findmnt -no TARGET,FSTYPE,OPTIONS -T ${probeDir}`;
    return `${label}=${rootDir} exec=${result.exitCode} mount=${mount.stdout.trim() || '<unavailable>'}`;
  } catch (error) {
    return `${label}=${rootDir} probe-error=${String(error)}`;
  } finally {
    if (probeDir) await fs.rm(probeDir, {recursive: true, force: true});
  }
}

async function readCgroupMemory() {
  const files = [
    '/sys/fs/cgroup/memory.max',
    '/sys/fs/cgroup/memory.current',
    '/sys/fs/cgroup/memory.events',
    '/sys/fs/cgroup/memory/memory.limit_in_bytes',
    '/sys/fs/cgroup/memory/memory.usage_in_bytes',
    '/sys/fs/cgroup/memory/memory.failcnt',
  ];
  const values = [];
  for (const file of files) {
    try {
      values.push(`${file}=${(await fs.readFile(file, 'utf8')).trim().replaceAll('\n', ',')}`);
    } catch (error) {
      if (error?.code !== 'ENOENT') values.push(`${file}=read-error:${error?.code || String(error)}`);
    }
  }
  return values.length === 0 ? '<unavailable>' : values.join(' ');
}

const tempExec = [];
const tempRoots = [
  ['RUNNER_TEMP', process.env.RUNNER_TEMP],
  ['TMPDIR', os.tmpdir()],
];
for (const [label, rootDir] of tempRoots) {
  if (!tempExec.some(line => line.includes(`=${rootDir} `))) tempExec.push(await probeTempExec(rootDir, label));
}
const sccacheKeys = Object.keys(process.env).filter(key => key === 'RUSTC_WRAPPER' || key.startsWith('SCCACHE_')).sort();
const sccachePath = await $({nothrow: true, quiet: true, stdio: 'pipe'})`sh -c 'command -v sccache || true'`;
const cgroupMemory = await readCgroupMemory();

console.log('[preflight] runner-specific probes');
for (const line of tempExec) console.log(`  temp-exec: ${line}`);
console.log(`  sccache: path=${sccachePath.stdout.trim() || '<absent>'} env-keys=${sccacheKeys.join(',') || '<none>'}`);
console.log(`  cgroup-memory: ${cgroupMemory}`);

// Bootstrap produces the deployed SDK, not a source C++ reference compiler.
// Oracle comparisons remain available through scripts/difftest.mjs and bcgate.py
// for callers that explicitly provide that separate compiler.

await phase('lineage', async () => {
  await assertPackagedLineage(sdk, {
    allowNightlyStd: process.env.CJCJ_ALLOW_NIGHTLY_STD === '1',
  });
});

await phase('smoke', async () => {
  console.log('[smoke] verify deployed SDK');
  await $`npx --yes zx@8 ${root}/ci/smoke/run_smoke.mjs ${self} ${work}/smoke`;
});

await phase('selfcheck', async () => {
  console.log('[selfcheck] verify compiler packages');
  const packages = [
    'option', 'conditional_compilation', 'mangle', 'frontend_tool', 'incremental_compilation',
    'modules', 'driver', 'meta_transformation', 'lex', 'ast', 'frontend', 'cjc', 'basic', 'codegen', 'macro',
  ];
  const failedPackages = [];
  for (const pkg of packages) {
    console.log(`[selfcheck] package ${pkg}`);
    const compiled = await $({nothrow: noFailFast})`${timeoutCommand} 900 ${self} --package ${root}/packages/${pkg}/src --module-name cjcj --import-path ${root}/target/release --output-type=staticlib -o ${work}/${pkg}.a`;
    if (!noFailFast) continue;
    if (compiled.exitCode === 0) {
      console.log(`[selfcheck] package ${pkg} PASS`);
    } else {
      failedPackages.push(`${pkg}:exit=${compiled.exitCode ?? 'null'}:signal=${compiled.signal ?? 'none'}`);
      console.error(`[selfcheck] package ${pkg} FAIL exit=${compiled.exitCode ?? 'null'} signal=${compiled.signal ?? 'none'}`);
    }
  }
  if (noFailFast) {
    console.log(`[selfcheck] summary: total=${packages.length} pass=${packages.length - failedPackages.length} fail=${failedPackages.length}`);
    if (failedPackages.length > 0) throw new Error(`selfcheck failed packages: ${failedPackages.join(' ')}`);
  }
});

await phase('selfdet', () => verifyRepeatedCjo({
  compiler: self,
  sourceDir: path.join(root, 'packages', 'conditional_compilation', 'src'),
  importPath: path.join(root, 'target', 'release'),
  outputDir: path.join(work, 'selfdet'),
  timeoutCommand,
}));

if (noFailFast) {
  console.log('[verify] --no-fail-fast summary');
  for (const result of phaseResults) {
    console.log(`  ${result.status.padEnd(4)} ${result.name} wall=${result.wall.toFixed(3)}s${result.detail ? ` detail=${result.detail}` : ''}`);
  }
  const failedPhases = phaseResults.filter(result => result.status === 'FAIL');
  console.log(`[verify] phases=${phaseResults.length} pass=${phaseResults.length - failedPhases.length} fail=${failedPhases.length}`);
  if (failedPhases.length > 0) {
    console.error(`[verify] source build failed: ${failedPhases.map(result => result.name).join(',')}`);
    process.exit(1);
  }
}
console.log('[verify] source build passed');
