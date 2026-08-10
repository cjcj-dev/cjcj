#!/usr/bin/env zx

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {runGrepProbe} from '../../../build/lib/fail-closed-probes.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';

$.stdio = 'inherit';

const root = path.resolve(import.meta.dirname, '../../..');
const sdk = argv._[0];
if (!sdk) throw new Error('usage: verify.mjs <sdk-dir>');
const workspace = process.env.CANGJIE_WORKSPACE;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
if (!workspace || !targetKey) throw new Error('CANGJIE_WORKSPACE and CJCJ_SRCBUILD_TARGET are required');
const target = getTarget(targetKey);
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}
const self = `${sdk}/bin/cjc`;
const oracle = `${workspace}/cangjie_compiler/output/bin/cjc`;
let jobs = Number(process.env.CJCJ_VERIFY_JOBS || os.cpus().length || 1);
if (!Number.isSafeInteger(jobs) || jobs < 1) throw new Error(`invalid CJCJ_VERIFY_JOBS: ${process.env.CJCJ_VERIFY_JOBS}`);
jobs = String(Math.min(jobs, 16));
const timeoutCommand = target.spec.os === 'darwin' ? 'gtimeout' : 'timeout';

await $`test -x ${self}`;
await $`test -x ${oracle}`;
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
const oracleDeps = target.spec.os === 'darwin'
  ? await $({nothrow: true, quiet: true, stdio: 'pipe'})`otool -L ${oracle}`
  : await $({nothrow: true, quiet: true, stdio: 'pipe'})`ldd ${oracle}`;
const oracleDepsOutput = `${oracleDeps.stdout}${oracleDeps.stderr}`;
const oracleDepsNotFound = oracleDepsOutput.split(/\r?\n/).filter(line => /not found/i.test(line));
const cgroupMemory = await readCgroupMemory();

console.log('[preflight] runner-specific probes');
for (const line of tempExec) console.log(`  temp-exec: ${line}`);
console.log(`  sccache: path=${sccachePath.stdout.trim() || '<absent>'} env-keys=${sccacheKeys.join(',') || '<none>'}`);
console.log(`  oracle-deps: inspector=${target.spec.os === 'darwin' ? 'otool' : 'ldd'} exit=${oracleDeps.exitCode} not-found=${oracleDepsNotFound.join(' | ') || '<none>'}`);
console.log(`  cgroup-memory: ${cgroupMemory}`);

async function reportPreflightFailure(label, result) {
  console.error(`[preflight] ${label} failed: exit=${result.exitCode}`);
  if (result.stdout) process.stderr.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  console.error(`[preflight] PATH=${process.env.PATH}`);
  console.error(`[preflight] ${target.spec.loaderEnv}=${process.env[target.spec.loaderEnv]}`);
  console.error(`[preflight] CANGJIE_HOME=${process.env.CANGJIE_HOME}`);
  console.error(`[preflight] oracle dependencies not-found: ${oracleDepsNotFound.join(' | ') || '<none>'}`);
  console.error(`[preflight] temp exec: ${tempExec.join(' || ')}`);
  console.error(`[preflight] sccache env keys: ${sccacheKeys.join(',') || '<none>'}`);
  console.error(`[preflight] cgroup memory: ${cgroupMemory}`);
}

console.log('[preflight] oracle --version');
const oracleVersion = await $({nothrow: true, quiet: true, stdio: 'pipe'})`${oracle} --version`;
if (oracleVersion.exitCode !== 0) {
  await reportPreflightFailure('oracle --version', oracleVersion);
  throw new Error('reference oracle preflight failed');
}
if (oracleVersion.stdout) process.stdout.write(oracleVersion.stdout);
if (oracleVersion.stderr) process.stderr.write(oracleVersion.stderr);

const corpus = `${root}/scripts/difftest_corpus`;
const firstCorpusName = (await fs.readdir(corpus)).filter(name => name.endsWith('.cj')).sort()[0];
if (!firstCorpusName) throw new Error(`reference oracle preflight failed: no .cj files in ${corpus}`);
const firstCorpus = path.join(corpus, firstCorpusName);
const preflightOutput = path.join(work, 'ref-preflight');
console.log(`[preflight] reference compile: ${firstCorpusName}`);
const referenceCompile = await $({nothrow: true, quiet: true, stdio: 'pipe', cwd: work})`${timeoutCommand} 180 ${oracle} ${firstCorpus} -o ${preflightOutput}`;
await fs.rm(preflightOutput, {force: true});
if (referenceCompile.exitCode !== 0) {
  await reportPreflightFailure(`reference compile ${firstCorpusName}`, referenceCompile);
  throw new Error('reference oracle preflight failed');
}
if (referenceCompile.stdout) process.stdout.write(referenceCompile.stdout);
if (referenceCompile.stderr) process.stderr.write(referenceCompile.stderr);
console.log('[preflight] PASS items=6 probes=4/4');

console.log('[difftest] compare selfhost SDK and source-built C++ oracle');
const difftestEnv = {
  ...process.env,
  DIFFTEST_TC: sdk,
  DIFFTEST_SELF: self,
  DIFFTEST_REF: oracle,
};
await $({env: difftestEnv})`set -o pipefail; npx --yes zx@8 ${root}/scripts/difftest.mjs -j ${jobs} | tee ${work}/difftest.log`;
await $`grep -Eq 'TOTAL=[0-9]+[[:space:]]+PASS=[0-9]+[[:space:]]+MISMATCH=0[[:space:]]+FAIL=0' ${work}/difftest.log`;

console.log('[smoke] verify deployed SDK');
await $`npx --yes zx@8 ${root}/ci/smoke/run_smoke.mjs ${self} ${work}/smoke`;

console.log('[selfcheck] verify compiler packages');
const packages = [
  'option', 'conditional_compilation', 'mangle', 'frontend_tool', 'incremental_compilation',
  'modules', 'driver', 'meta_transformation', 'lex', 'ast', 'frontend', 'cjc', 'basic', 'codegen', 'macro',
];
for (const pkg of packages) {
  console.log(`[selfcheck] package ${pkg}`);
  await $`${timeoutCommand} 900 ${self} --package ${root}/packages/${pkg}/src --module-name cjcj --import-path ${root}/target/release --output-type=staticlib -o ${work}/${pkg}.a`;
}

console.log('[bcgate] verify bitcode parity');
await $`set -o pipefail; python3 ${root}/scripts/bcgate.py --self ${self} --base ${oracle} --corpus ${root}/scripts/difftest_corpus -j ${jobs} | tee ${work}/bcgate.log`;
await $`grep -Eq 'byte-identical: [0-9]+ \\(100\\.0%\\)[[:space:]]+\\|[[:space:]]+differing: 0' ${work}/bcgate.log`;
await $`grep -Eq 'compile-errors: 0' ${work}/bcgate.log`;
const onlyOneSide = await runGrepProbe({
  label: 'bcgate one-side divergence grep',
  run: () => $({nothrow: true})`grep -q 'functions present on only one side' ${work}/bcgate.log`,
});
if (onlyOneSide.matched) throw new Error('bcgate failed: functions are present on only one side');
console.log('[verify] source build passed');
