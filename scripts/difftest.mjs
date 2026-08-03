#!/usr/bin/env zx
// Corpus differential gate: compare self-host and reference compile/run results with deterministic parallel aggregation.
//
// Invariant: runtime used to load selfhost + its products must come from the tree under test
// (DIFFTEST_SELF_TC, or home next to DIFFTEST_SELF). DIFFTEST_TC is the official/bootstrap
// toolchain (ref compiler + llvm tools). Never silently red on ABI mismatch — print HARNESS.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {access, constants as fsConstants} from 'node:fs';
import {promisify} from 'node:util';

const accessAsync = promisify(access);

const repo = path.resolve(import.meta.dirname, '..');
const tc = process.env.DIFFTEST_TC || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458';
const self = process.env.DIFFTEST_SELF || `${repo}/target/release/bin/cjcj::cjc`;
const ref = process.env.DIFFTEST_REF || '/root/.cjv/bin/cjc';

const RUNTIME_SUB = 'runtime/lib/linux_x86_64_cjnative';
const HARNESS_TAG = 'HARNESS';

function toolchainLd(home) {
  if (!home) return '';
  return [
    `${home}/third_party/llvm/lib`,
    `${home}/${RUNTIME_SUB}`,
    `${home}/tools/lib`,
  ].join(':');
}

function mergeLd(...parts) {
  return parts.filter(p => p && p.length).join(':');
}

async function exists(file) {
  try {
    await accessAsync(file, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function resolveSelfHome(selfBin, bootstrapTc) {
  if (process.env.DIFFTEST_SELF_TC) {
    return path.resolve(process.env.DIFFTEST_SELF_TC);
  }
  const nextToSelf = path.resolve(path.dirname(path.resolve(selfBin)), '..');
  if (await exists(path.join(nextToSelf, RUNTIME_SUB, 'libcangjie-runtime.so'))) {
    return nextToSelf;
  }
  return path.resolve(bootstrapTc);
}

function withEnv(base, extra) {
  return {...base, ...extra};
}

function commandSubstitution(text) {
  return text.replace(/\n+$/, '');
}

function bashQ(text, limit = 30) {
  const value = text.slice(0, limit);
  if (value === '') return "''";
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(value)) return value;
  return `$'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t')}'`;
}

function isAbiLoadError(text) {
  return /symbol lookup error|undefined symbol|version `[^']+' not found|cannot open shared object file|error while loading shared libraries/i.test(text);
}

async function preflightSelf(selfBin, selfHome, bootstrapTc, selfLd, selfCangjieHome) {
  if (!(await exists(selfBin))) {
    console.error(`${HARNESS_TAG}: missing DIFFTEST_SELF binary: ${selfBin}`);
    process.exit(2);
  }
  const selfRt = path.join(selfHome, RUNTIME_SUB, 'libcangjie-runtime.so');
  if (!(await exists(selfRt))) {
    console.error(`${HARNESS_TAG}: self runtime not found under tree-under-test: ${selfRt}`);
    console.error(`${HARNESS_TAG}: set DIFFTEST_SELF_TC to a SDK/home that pairs with ${selfBin}`);
    process.exit(2);
  }

  const env = withEnv(process.env, {
    CANGJIE_HOME: selfCangjieHome,
    LD_LIBRARY_PATH: selfLd,
  });
  const probe = await $({nothrow: true, quiet: true, env})`timeout 15 ${selfBin} --version`;
  const out = `${probe.stdout}${probe.stderr}`;
  if (probe.exitCode === 0) return;

  if (isAbiLoadError(out)) {
    console.error(`${HARNESS_TAG}: selfhost failed to load with tree-under-test runtime (ABI/runtime mismatch)`);
    console.error(`${HARNESS_TAG}: DIFFTEST_SELF=${selfBin}`);
    console.error(`${HARNESS_TAG}: selfHome=${selfHome} bootstrapTc=${bootstrapTc}`);
    console.error(`${HARNESS_TAG}: LD_LIBRARY_PATH(prefix)=${selfLd.split(':').slice(0, 4).join(':')}`);
    console.error(`${HARNESS_TAG}: ${out.split(/\r?\n/).find(Boolean) || '<no output>'}`);
    process.exit(2);
  }
  console.error(`${HARNESS_TAG}: selfhost --version exited ${probe.exitCode} (not a clean load probe)`);
  console.error(`${HARNESS_TAG}: ${out.split(/\r?\n/).find(Boolean) || '<no output>'}`);
  process.exit(2);
}

const selfHome = await resolveSelfHome(self, tc);
// Runtime for self + products MUST come from the tree under test (selfHome).
// CANGJIE_HOME still needs llvm tools (opt/llc): use selfHome when it has them,
// else bootstrap DIFFTEST_TC. LD prefers selfHome runtime first so products do
// not silently load a stale DIFFTEST_TC so (the original false-red bug).
// If selfHome runtime and TC tools are ABI-mismatched, preflight or product
// HARNESS tags fire — never ordinary silent red.
const selfHasLlvm = await exists(path.join(selfHome, 'third_party/llvm/bin/llc'));
const selfCangjieHome = selfHasLlvm ? selfHome : tc;
const selfLd = mergeLd(
  toolchainLd(selfHome),
  selfHome !== selfCangjieHome ? toolchainLd(selfCangjieHome) : '',
  process.env.LD_LIBRARY_PATH || '',
);
const refLd = mergeLd(toolchainLd(tc), process.env.LD_LIBRARY_PATH || '');
const refEnv = withEnv(process.env, {CANGJIE_HOME: tc, LD_LIBRARY_PATH: refLd});
const selfEnv = withEnv(process.env, {CANGJIE_HOME: selfCangjieHome, LD_LIBRARY_PATH: selfLd});

if (argv['skip-preflight'] === undefined) {
  await preflightSelf(self, selfHome, tc, selfLd, selfCangjieHome);
}

async function classify(file) {
  const name = path.basename(file, '.cj');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-difftest-'));
  try {
    const referenceBuild = await $({cwd: work, nothrow: true, quiet: true, env: refEnv})`timeout 180 ${ref} ${file} -o ${path.join(work, `${name}.ref`)}`;
    await fs.writeFile(path.join(work, `${name}.rlog`), referenceBuild.stdout + referenceBuild.stderr);
    let rout = '<REF-COMPILE-FAIL>';
    let rexit = -1;
    if (referenceBuild.exitCode === 0) {
      const referenceRun = await $({cwd: work, nothrow: true, quiet: true, env: refEnv})`timeout 30 ${path.join(work, `${name}.ref`)}`;
      rout = commandSubstitution(referenceRun.stdout);
      rexit = referenceRun.exitCode;
    }

    const selfBuild = await $({cwd: work, nothrow: true, quiet: true, env: selfEnv})`timeout 180 ${self} ${file} -o ${path.join(work, `${name}.self`)} --set-runtime-rpath`;
    await fs.writeFile(path.join(work, `${name}.slog`), selfBuild.stdout + selfBuild.stderr);
    if (selfBuild.exitCode === 0) {
      const selfRun = await $({cwd: work, nothrow: true, quiet: true, env: selfEnv})`timeout 30 ${path.join(work, `${name}.self`)}`;
      const sout = commandSubstitution(selfRun.stdout);
      const selfCombined = `${selfRun.stdout}${selfRun.stderr}`;
      if (isAbiLoadError(selfCombined)) {
        return `FAIL\t${name}\t${HARNESS_TAG}: product ABI/runtime mismatch: ${bashQ(selfCombined.split(/\r?\n/).find(Boolean) || '', 120)}`;
      }
      if (sout === rout && selfRun.exitCode === rexit) return `PASS\t${name}\texit=${selfRun.exitCode}`;
      const refCompileDetail = referenceBuild.exitCode === 0
        ? ''
        : ` stderr=${bashQ(referenceBuild.stderr.split(/\r?\n/, 1)[0], 200)}`;
      return `MISMATCH\t${name}\tself(exit=${selfRun.exitCode} out=${bashQ(sout)}) ref(exit=${rexit} out=${bashQ(rout)}${refCompileDetail})`;
    }
    if (selfBuild.exitCode === 124) return `FAIL\t${name}\t<COMPILE-TIMEOUT-180s>`;

    const log = selfBuild.stdout + selfBuild.stderr;
    if (isAbiLoadError(log)) {
      return `FAIL\t${name}\t${HARNESS_TAG}: selfhost ABI/runtime mismatch: ${bashQ(log.split(/\r?\n/).find(Boolean) || '', 120)}`;
    }
    const strong = log.match(/not yet ported[^"\n]*|globalCache miss|unsupported AST type kind[^"\n]*|unsupported construct[^"\n]*|should have result|Out of memory|does not match pointee|IllegalState[A-Za-z]*|IllegalArgument[A-Za-z]*|no Sema target|no resolvedFunction|you should set a return value/i);
    const weak = log.split('\n').find(line => /error|exception/i.test(line));
    if (strong?.[0] || weak) {
      return `FAIL\t${name}\t${strong?.[0] || weak.slice(0, 60)}`;
    }
    // Never collapse empty-log compile failures to bare <unknown>: report
    // exit code, timeout flag, stdout/stderr tails, and whether product exists.
    const productPath = path.join(work, `${name}.self`);
    const productExists = await exists(productPath);
    const tailLines = (text) => (text || '').split(/\r?\n/).filter(Boolean).slice(-2).join(' | ');
    const stdoutTail = bashQ(tailLines(selfBuild.stdout), 80);
    const stderrTail = bashQ(tailLines(selfBuild.stderr), 80);
    return `FAIL\t${name}\trc=${selfBuild.exitCode} timeout=0 product=${productExists ? 1 : 0} stdout=${stdoutTail || "''"} stderr=${stderrTail || "''"}`;
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}

if (argv.one !== undefined) {
  const file = typeof argv.one === 'string' ? argv.one : argv._[0];
  if (!file) process.exit(1);
  console.log(await classify(path.resolve(file)));
  process.exit(0);
}

let corpus = argv._[0] || '';
let jobs = Number(argv.j || argv.jobs || Math.min(16, os.cpus().length));
corpus ||= `${repo}/scripts/difftest_corpus`;

const samples = (await fs.readdir(corpus))
  .filter(name => name.endsWith('.cj'))
  .map(name => path.resolve(corpus, name));
const results = new Array(samples.length);
let next = 0;
async function worker() {
  while (true) {
    const index = next++;
    if (index >= samples.length) return;
    results[index] = await classify(samples[index]);
  }
}
await Promise.all(Array.from({length: Math.min(jobs, samples.length)}, worker));
results.sort();

let pass = 0;
let mismatch = 0;
let fail = 0;
const gaps = new Map();
for (const line of results) {
  const [status, name, ...detailParts] = line.split('\t');
  const detail = detailParts.join('\t');
  if (status === 'PASS') pass++;
  else if (status === 'MISMATCH') mismatch++;
  else {
    fail++;
    gaps.set(detail, (gaps.get(detail) || 0) + 1);
  }
  console.log(`${status.padEnd(8)} ${name.padEnd(22)} ${detail}`);
}
console.log('================================================================');
console.log(`TOTAL=${pass + mismatch + fail}  PASS=${pass}  MISMATCH=${mismatch}  FAIL=${fail}`);
console.log('---- gap tally (selfhost faithful-pipeline failures, ranked) ----');
for (const [detail, count] of [...gaps].sort((a, b) => b[1] - a[1] || b[0].localeCompare(a[0]))) {
  console.log(`${String(count).padStart(7)} ${detail}`);
}
