#!/usr/bin/env zx
// TypeDef/TypeAlias semantic differential gate: official cjc vs cjcj.
// Covers compile-success (run output) and compile-fail (normalized diagnostics).
// LD / runtime discipline mirrors scripts/difftest.mjs (self tree runtime first).

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
const corpus = argv._[0] || `${repo}/scripts/typedefgate_corpus`;
const metaPath = path.join(import.meta.dirname, 'typedefgate_meta', 'coverage.tsv');
const jobs = Number(argv.j || argv.jobs || Math.min(8, os.cpus().length));

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
  if (process.env.DIFFTEST_SELF_TC) return path.resolve(process.env.DIFFTEST_SELF_TC);
  const nextToSelf = path.resolve(path.dirname(path.resolve(selfBin)), '..');
  if (await exists(path.join(nextToSelf, RUNTIME_SUB, 'libcangjie-runtime.so'))) return nextToSelf;
  return path.resolve(bootstrapTc);
}
function withEnv(base, extra) {
  return {...base, ...extra};
}
function isAbiLoadError(text) {
  return /symbol lookup error|undefined symbol|version `[^']+' not found|cannot open shared object file|error while loading shared libraries/i.test(text);
}

const selfHome = await resolveSelfHome(self, tc);
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

if (!(await exists(self))) {
  console.error(`${HARNESS_TAG}: missing DIFFTEST_SELF: ${self}`);
  process.exit(2);
}
{
  const probe = await $({nothrow: true, quiet: true, env: selfEnv})`timeout 15 ${self} --version`;
  const out = `${probe.stdout}${probe.stderr}`;
  if (probe.exitCode !== 0) {
    console.error(`${HARNESS_TAG}: selfhost --version failed: ${out.split(/\r?\n/).find(Boolean) || ''}`);
    process.exit(2);
  }
}

/** Normalize diagnostics for cross-compiler comparison. */
function normalizeDiag(text) {
  return text
    .replace(/\x1b\[[0-9;]*m/g, '')
    .replace(/\/tmp\/[A-Za-z0-9._/-]+/g, '<TMP>')
    .replace(/\/root\/[A-Za-z0-9._/-]+/g, '<PATH>')
    .split(/\r?\n/)
    .map(l => l.replace(/\s+$/, ''))
    // drop absolute path prefixes in " ==> file:line"
    .map(l => l.replace(/==>\s+\S+\.cj:/, '==> <FILE>:'))
    .filter(l => l.length > 0)
    // keep error/warning kind lines + summary counts
    .filter(l =>
      /^(error|warning|note):/i.test(l) ||
      /^\d+ (error|warning)/i.test(l) ||
      /error generated|warning generated/i.test(l) ||
      /type cycle detected|type argument|not used|invalid binary|duplicate interface|unable to infer|not a type|external refer|generic/i.test(l)
    )
    .join('\n');
}

function extractErrorKeys(text) {
  const keys = [];
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^(error|warning):\s*(.+)$/i);
    if (m) keys.push(`${m[1].toLowerCase()}:${m[2].trim().slice(0, 120)}`);
  }
  // also count summary
  const em = text.match(/(\d+)\s+errors?\s+generated/i);
  const wm = text.match(/(\d+)\s+warnings?\s+generated/i);
  if (em) keys.push(`summary:errors=${em[1]}`);
  if (wm) keys.push(`summary:warnings=${wm[1]}`);
  return keys.sort();
}

function keysEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

async function classify(file) {
  const name = path.basename(file, '.cj');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'typedefgate-'));
  try {
    const refBuild = await $({cwd: work, nothrow: true, quiet: true, env: refEnv})`timeout 180 ${ref} ${file} -o ${path.join(work, `${name}.ref`)}`;
    const refLog = refBuild.stdout + refBuild.stderr;
    let refOut = '';
    let refRunExit = -1;
    if (refBuild.exitCode === 0) {
      const rr = await $({cwd: work, nothrow: true, quiet: true, env: refEnv})`timeout 30 ${path.join(work, `${name}.ref`)}`;
      refOut = rr.stdout.replace(/\n+$/, '');
      refRunExit = rr.exitCode;
    }

    const selfBuild = await $({cwd: work, nothrow: true, quiet: true, env: selfEnv})`timeout 180 ${self} ${file} -o ${path.join(work, `${name}.self`)} --set-runtime-rpath`;
    const selfLog = selfBuild.stdout + selfBuild.stderr;
    if (isAbiLoadError(selfLog)) {
      return {status: 'FAIL', name, detail: `${HARNESS_TAG}: self ABI: ${selfLog.split(/\r?\n/).find(Boolean) || ''}`};
    }
    let selfOut = '';
    let selfRunExit = -1;
    if (selfBuild.exitCode === 0) {
      const sr = await $({cwd: work, nothrow: true, quiet: true, env: selfEnv})`timeout 30 ${path.join(work, `${name}.self`)}`;
      const combined = `${sr.stdout}${sr.stderr}`;
      if (isAbiLoadError(combined)) {
        return {status: 'FAIL', name, detail: `${HARNESS_TAG}: product ABI: ${combined.split(/\r?\n/).find(Boolean) || ''}`};
      }
      selfOut = sr.stdout.replace(/\n+$/, '');
      selfRunExit = sr.exitCode;
    }

    const refOk = refBuild.exitCode === 0;
    const selfOk = selfBuild.exitCode === 0;

    if (refOk && selfOk) {
      if (selfOut === refOut && selfRunExit === refRunExit) {
        return {status: 'PASS', name, detail: `run exit=${selfRunExit} out=${JSON.stringify(selfOut).slice(0, 80)}`};
      }
      return {
        status: 'MISMATCH',
        name,
        detail: `run self(exit=${selfRunExit} out=${JSON.stringify(selfOut).slice(0, 60)}) ref(exit=${refRunExit} out=${JSON.stringify(refOut).slice(0, 60)})`,
        refLog, selfLog, kind: 'run',
      };
    }

    if (!refOk && !selfOk) {
      const rk = extractErrorKeys(refLog);
      const sk = extractErrorKeys(selfLog);
      if (keysEqual(rk, sk)) {
        return {status: 'PASS', name, detail: `diag keys=${rk.length} both_fail rc_ref=${refBuild.exitCode} rc_self=${selfBuild.exitCode}`};
      }
      // softer: same error count and shared first error prefix
      const rErr = rk.filter(k => k.startsWith('error:')).length;
      const sErr = sk.filter(k => k.startsWith('error:')).length;
      const rSum = rk.find(k => k.startsWith('summary:errors='));
      const sSum = sk.find(k => k.startsWith('summary:errors='));
      if (rErr === sErr && rErr > 0 && rSum && rSum === sSum) {
        // check if first error message bodies overlap substantially
        const rBodies = rk.filter(k => k.startsWith('error:')).map(k => k.slice(6, 40));
        const sBodies = sk.filter(k => k.startsWith('error:')).map(k => k.slice(6, 40));
        const overlap = rBodies.filter(b => sBodies.some(s => s.includes(b.slice(0, 20)) || b.includes(s.slice(0, 20))));
        if (overlap.length === rBodies.length) {
          return {status: 'PASS', name, detail: `diag soft-match errors=${rErr} both_fail`};
        }
      }
      return {
        status: 'MISMATCH',
        name,
        detail: `diag ref_keys=[${rk.slice(0, 4).join(' | ')}] self_keys=[${sk.slice(0, 4).join(' | ')}]`,
        refLog, selfLog, kind: 'diag',
        refKeys: rk, selfKeys: sk,
      };
    }

    // one side compiles, other doesn't
    return {
      status: 'MISMATCH',
      name,
      detail: `compile_asymmetry ref_ok=${refOk} self_ok=${selfOk} ref_rc=${refBuild.exitCode} self_rc=${selfBuild.exitCode}`,
      refLog, selfLog, kind: 'compile_asymmetry',
    };
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}

const samples = (await fs.readdir(corpus))
  .filter(n => n.endsWith('.cj'))
  .map(n => path.resolve(corpus, n))
  .sort();

if (samples.length === 0) {
  console.error(`${HARNESS_TAG}: empty corpus ${corpus}`);
  process.exit(2);
}

// load coverage meta if present
let coverage = new Map();
try {
  const meta = await fs.readFile(metaPath, 'utf8');
  for (const line of meta.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const [file, points, ...rest] = line.split('\t');
    if (file) coverage.set(file.replace(/\.cj$/, ''), {points, note: rest.join('\t')});
  }
} catch { /* optional */ }

const results = new Array(samples.length);
let next = 0;
async function worker() {
  while (true) {
    const i = next++;
    if (i >= samples.length) return;
    results[i] = await classify(samples[i]);
  }
}
await Promise.all(Array.from({length: Math.min(jobs, samples.length)}, worker));

let pass = 0, mismatch = 0, fail = 0;
const mismatchDetails = [];
for (const r of results) {
  const cov = coverage.get(r.name);
  const covTag = cov ? ` [T1:${cov.points}]` : ' [T1:UNMAPPED]';
  console.log(`${r.status.padEnd(10)} ${r.name.padEnd(28)} ${r.detail}${covTag}`);
  if (r.status === 'PASS') pass++;
  else if (r.status === 'MISMATCH') {
    mismatch++;
    mismatchDetails.push(r);
  } else fail++;
}
console.log('================================================================');
console.log(`TOTAL=${pass + mismatch + fail}  PASS=${pass}  MISMATCH=${mismatch}  FAIL=${fail}`);
console.log(`DIFFTEST_SELF=${self}`);
console.log(`DIFFTEST_REF=${ref}`);
console.log(`selfHome=${selfHome}`);

// write machine-readable result
const outDir = process.env.TYPEDEFGATE_OUT || '/tmp/audit/logs';
await fs.mkdir(outDir, {recursive: true});
const reportJson = {
  total: pass + mismatch + fail,
  pass, mismatch, fail,
  self, ref, selfHome,
  results: results.map(r => ({
    status: r.status, name: r.name, detail: r.detail,
    coverage: coverage.get(r.name) || null,
    refKeys: r.refKeys, selfKeys: r.selfKeys, kind: r.kind,
  })),
};
await fs.writeFile(path.join(outDir, 'typedefgate_results.json'), JSON.stringify(reportJson, null, 2));
for (const r of mismatchDetails) {
  if (r.refLog) await fs.writeFile(path.join(outDir, `typedefgate_${r.name}.ref.log`), r.refLog);
  if (r.selfLog) await fs.writeFile(path.join(outDir, `typedefgate_${r.name}.self.log`), r.selfLog);
}
process.exitCode = (mismatch + fail) === 0 ? 0 : 1;
