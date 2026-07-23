#!/usr/bin/env zx
// Corpus differential gate: compare self-host and reference compile/run results with deterministic parallel aggregation.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const tc = process.env.DIFFTEST_TC || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458';
process.env.CANGJIE_HOME = tc;
process.env.LD_LIBRARY_PATH = `${tc}/third_party/llvm/lib:${tc}/runtime/lib/linux_x86_64_cjnative:${tc}/tools/lib:${process.env.LD_LIBRARY_PATH || ''}`;
const repo = path.resolve(import.meta.dirname, '..');
const self = process.env.DIFFTEST_SELF || `${repo}/target/release/bin/cjcj::cjc`;
const ref = process.env.DIFFTEST_REF || '/root/.cjv/bin/cjc';

function commandSubstitution(text) {
  return text.replace(/\n+$/, '');
}

function bashQ(text, limit = 30) {
  const value = text.slice(0, limit);
  if (value === '') return "''";
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(value)) return value;
  return `$'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t')}'`;
}

async function classify(file) {
  const name = path.basename(file, '.cj');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-difftest-'));
  try {
    const referenceBuild = await $({cwd: work, nothrow: true, quiet: true})`timeout 180 ${ref} ${file} -o ${path.join(work, `${name}.ref`)}`;
    await fs.writeFile(path.join(work, `${name}.rlog`), referenceBuild.stdout + referenceBuild.stderr);
    let rout = '<REF-COMPILE-FAIL>';
    let rexit = -1;
    if (referenceBuild.exitCode === 0) {
      const referenceRun = await $({cwd: work, nothrow: true, quiet: true})`timeout 30 ${path.join(work, `${name}.ref`)}`;
      rout = commandSubstitution(referenceRun.stdout);
      rexit = referenceRun.exitCode;
    }

    const selfBuild = await $({cwd: work, nothrow: true, quiet: true})`timeout 180 ${self} ${file} -o ${path.join(work, `${name}.self`)} --set-runtime-rpath`;
    await fs.writeFile(path.join(work, `${name}.slog`), selfBuild.stdout + selfBuild.stderr);
    if (selfBuild.exitCode === 0) {
      const selfRun = await $({cwd: work, nothrow: true, quiet: true})`timeout 30 ${path.join(work, `${name}.self`)}`;
      const sout = commandSubstitution(selfRun.stdout);
      if (sout === rout && selfRun.exitCode === rexit) return `PASS\t${name}\texit=${selfRun.exitCode}`;
      const refCompileDetail = referenceBuild.exitCode === 0
        ? ''
        : ` stderr=${bashQ(referenceBuild.stderr.split(/\r?\n/, 1)[0], 200)}`;
      return `MISMATCH\t${name}\tself(exit=${selfRun.exitCode} out=${bashQ(sout)}) ref(exit=${rexit} out=${bashQ(rout)}${refCompileDetail})`;
    }
    if (selfBuild.exitCode === 124) return `FAIL\t${name}\t<COMPILE-TIMEOUT-180s>`;

    const log = selfBuild.stdout + selfBuild.stderr;
    const strong = log.match(/not yet ported[^"\n]*|globalCache miss|unsupported AST type kind[^"\n]*|unsupported construct[^"\n]*|should have result|Out of memory|does not match pointee|IllegalState[A-Za-z]*|IllegalArgument[A-Za-z]*|no Sema target|no resolvedFunction|you should set a return value/i);
    const weak = log.split('\n').find(line => /error|exception/i.test(line));
    const reason = strong?.[0] || weak?.slice(0, 60) || '<unknown>';
    return `FAIL\t${name}\t${reason}`;
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
