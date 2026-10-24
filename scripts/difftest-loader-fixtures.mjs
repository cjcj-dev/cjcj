#!/usr/bin/env zx
// Real CLI observations. Native fixtures establish ground truth only for the
// test: they do not supply qualification to the product runner.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {parseSummary} from '../ci/release/g8.mjs';
import {buildFullGateFloor} from '../build/lib/full-gate-floor-schema.mjs';

export async function testLoaderContract({root, script, evidence, zx}) {
  const records = [];
  async function execute(label, command, options = {}) {
    const run = spawnSync(command[0], command.slice(1), {
      encoding: 'utf8', timeout: 90_000, maxBuffer: 4 * 1024 * 1024, ...options,
    });
    const record = {label, command, rc: run.status, signal: run.signal,
      error: run.error?.message, stdout: run.stdout, stderr: run.stderr};
    records.push(record);
    await fs.writeFile(path.join(evidence, 'loader-executions.json'), JSON.stringify(records, null, 2) + '\n');
    assert.equal(run.error, undefined, label);
    assert.equal(run.signal, null, label);
    return run;
  }
  async function build(label, source, args) {
    const file = path.join(root, label + '.c');
    await fs.writeFile(file, source);
    const result = await execute('build-' + label, ['cc', file, ...args]);
    assert.equal(result.status, 0, result.stderr);
  }
  const corpus = path.join(root, 'corpus');
  const sdk = path.join(root, 'sdk');
  await fs.mkdir(corpus);
  await fs.mkdir(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'fixture only');
  const missing = path.join(root, 'missing-loader');
  const lazy = path.join(root, 'lazy-loader');
  const dynamic = path.join(root, 'dynamic-loader');
  const handled = path.join(root, 'handled-loader');
  const dependency = path.join(root, 'libdifftest_missing.so');
  const unresolved = path.join(root, 'libdifftest_lazy.so');
  await build('dependency', 'int dependency(void) { return 0; }', ['-shared', '-fPIC', '-o', dependency]);
  await build('missing', 'extern int dependency(void); int main(void) { return dependency(); }',
    ['-L' + root, '-ldifftest_missing', '-Wl,-rpath,' + root, '-o', missing]);
  await fs.rename(dependency, dependency + '.hidden');
  await build('unresolved', 'extern int difftest_unresolved(void); int trigger(void) { return difftest_unresolved(); }',
    ['-shared', '-fPIC', '-Wl,-z,lazy', '-o', unresolved]);
  await build('lazy', 'extern int trigger(void); int main(void) { return trigger(); }',
    ['-L' + root, '-ldifftest_lazy', '-Wl,--allow-shlib-undefined', '-Wl,-z,lazy', '-Wl,-rpath,' + root, '-o', lazy]);
  const unused = path.join(root, 'unused-loader');
  await build('unused', 'extern int trigger(void); int main(int argc, char **argv) { return argc > 1 ? trigger() : 42; }',
    ['-L' + root, '-ldifftest_lazy', '-Wl,--allow-shlib-undefined', '-Wl,-z,lazy', '-Wl,-rpath,' + root, '-o', unused]);
  await build('dynamic', '#include <dlfcn.h>\n#include <stdio.h>\nint main(void) { void *h=dlopen(' + JSON.stringify(unresolved) + ',RTLD_LAZY); if(!h) { fputs(dlerror(),stderr); return 99; } int (*f)(void)=dlsym(h,"trigger"); return f ? f() : 98; }', ['-ldl', '-o', dynamic]);
  await build('handled', '#include <dlfcn.h>\n#include <stdio.h>\nint main(void) { void *h=dlopen(' + JSON.stringify(dependency) + ',RTLD_LAZY); if(!h) { fputs(dlerror(),stderr); return 42; } return 99; }', ['-ldl', '-o', handled]);
  const raw = {};
  for (const [name, file, code, diagnostic] of [
    ['missing', missing, 127, /error while loading shared libraries/],
    ['lazy', lazy, 127, /symbol lookup error.*difftest_unresolved/],
    ['dynamic', dynamic, 127, /symbol lookup error.*difftest_unresolved/],
    ['handled', handled, 42, /cannot open shared object file/],
    ['unused', unused, 42, /^$/],
  ]) {
    raw[name] = await execute('native-' + name, [file]);
    assert.equal(raw[name].status, code, name);
    assert.match(raw[name].stderr, diagnostic, name);
  }
  const cases = {};
  const node = (code, stderr = '', stdout = '') => ({body:
    `process.stdout.write(${JSON.stringify(stdout)});process.stderr.write(${JSON.stringify(stderr)});process.exit(${code});`});
  const native = file => ({file});
  // Same stdout under the established command-substitution semantics, and all
  // old loader-text alternatives, for each normal exit and both/single sides.
  const diagnostic = 'symbol lookup error\nundefined symbol: ordinary diagnostic\nversion `ordinary\' not found\ncannot open shared object file\nerror while loading shared libraries: ordinary.so\n';
  for (const code of [0, 42, 127, 124, 143]) {
    cases['plain-' + code] = {ref: node(code), self: node(code), status: 'MATCH'};
    for (const arm of ['ref', 'self', 'both']) cases[`diagnostic-${arm}-${code}`] = {
      ref: node(code, arm === 'self' ? '' : diagnostic, 'undefined symbol: stdout\n\n'),
      self: node(code, arm === 'ref' ? '' : diagnostic, 'undefined symbol: stdout\n'), status: 'MATCH',
    };
  }
  for (const kind of ['missing', 'lazy', 'dynamic', 'handled', 'unused']) {
    for (const arm of ['ref', 'self', 'both']) {
      const product = native({missing, lazy, dynamic, handled, unused}[kind]);
      const ordinary = node(raw[kind].status);
      cases[`${kind}-${arm}`] = {ref: arm === 'self' ? ordinary : product,
        self: arm === 'ref' ? ordinary : product, status: 'MATCH'};
    }
  }
  // Legal programs can reproduce the exact raw loader bytes and normal rc.
  for (const kind of ['missing', 'lazy', 'dynamic']) for (const arm of ['ref', 'self', 'both']) {
    cases[`same-bytes-${kind}-${arm}`] = {
      ref: node(127, arm === 'self' ? '' : raw[kind].stderr),
      self: node(127, arm === 'ref' ? '' : raw[kind].stderr), status: 'MATCH',
    };
  }
  cases['different-output'] = {ref: node(0, '', 'reference'), self: node(0, '', 'self'), status: 'MISMATCH'};
  cases['different-exit'] = {ref: node(42), self: node(127), status: 'MISMATCH'};
  cases['compile-fail'] = {compileFail: true, status: 'FAIL'};
  await fs.writeFile(path.join(root, 'cases.json'), JSON.stringify(cases));
  for (const name of Object.keys(cases)) await fs.writeFile(path.join(corpus, name + '.cj'), '// controlled compiler boundary\n');
  const compiler = path.join(root, 'compiler.mjs');
  await fs.writeFile(compiler, `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
if (process.argv.includes('--version')) process.exit(0);
const cases=JSON.parse(fs.readFileSync(${JSON.stringify(path.join(root, 'cases.json'))}));
const item=cases[path.basename(process.argv[2],'.cj')];
if (item.compileFail) process.exit(1);
const out=process.argv[process.argv.indexOf('-o')+1];
const product=item[out.endsWith('.ref')?'ref':'self'];
if (product.file) fs.copyFileSync(product.file,out);
else fs.writeFileSync(out,${JSON.stringify(`#!${process.execPath}\n`)}+product.body+'\\n');
fs.chmodSync(out,0o755);
`, {mode: 0o755});
  const env = {...process.env, DIFFTEST_SELF: compiler, DIFFTEST_REF: compiler, DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: sdk};
  delete env.CJ_HOST_RTLIB;
  const run = await execute('cli-corpus', [process.execPath, zx, script, '--jobs', '2', corpus], {env});
  assert.equal(run.status, 0, run.stderr);
  const checks = [];
  function check(name, fn) {
    try { fn(); checks.push({name, pass: true}); }
    catch (error) { checks.push({name, pass: false, error: error.message}); }
  }
  for (const [name, item] of Object.entries(cases)) check(name, () => {
    assert.match(run.stdout, new RegExp(`^${item.status} +${name} +.*qualification=UNKNOWN$`, 'm'));
  });
  check('no-false-loader-cause-or-pass', () => {
    assert.doesNotMatch(run.stdout, /^PASS |HARNESS:.*(?:product|reference).*mismatch/m);
  });
  const counts = parseSummary('difftest', run.stdout);
  const total = Object.keys(cases).length;
  check('g8-preserves-match-and-unknown', () => assert.deepEqual(counts,
    {total, pass: 0, match: total - 3, mismatch: 2, fail: 1, unknown: total}));
  const sha = '08148651dc2aeee42eae161eca98d83a5cdb4935';
  const floor = difftest => buildFullGateFloor({campaign_id: `${sha}-20261024T000000Z-1`,
    cjcj_head_sha: sha, measured_utc: '2026-10-24T00:00:00Z', baseline: {difftest,
      smoke: {pass: 1, fail: 0}, bcgate: {shared: 1, byte_identical: 1, differing: 0, compile_errors: 0}, verify_exit: 0}});
  check('mixed-floor-refuses-mismatch', () => assert.throws(() => floor(counts), /difftest.mismatch=2/));
  // Each actual CLI summary, including all-legal and true-loader-only corpora,
  // passes through the production parser and the production floor consumer.
  for (const [label, names] of [
    ['legal', Object.keys(cases).filter(n => /^(plain|diagnostic|same-bytes|handled|unused)-/.test(n))],
    ['loader', Object.keys(cases).filter(n => /^(missing|lazy|dynamic)-/.test(n))],
  ]) {
    const selected = path.join(root, label);
    await fs.mkdir(selected);
    for (const name of names) await fs.copyFile(path.join(corpus, name + '.cj'), path.join(selected, name + '.cj'));
    const result = await execute('cli-' + label, [process.execPath, zx, script, '--jobs', '2', selected], {env});
    assert.equal(result.status, 0, result.stderr);
    const parsed = parseSummary('difftest', result.stdout);
    check(label + '-summary', () => assert.deepEqual(parsed, {total: names.length, pass: 0,
      match: names.length, mismatch: 0, fail: 0, unknown: names.length}));
    check(label + '-floor-refuses-unknown', () => assert.throws(() => floor(parsed), /difftest.unknown=/));
  }
  const one = await execute('cli-one', [process.execPath, zx, script, '--one', path.join(corpus, 'diagnostic-ref-127.cj')], {env});
  check('one-preserves-two-layers', () => {
    assert.equal(one.status, 0);
    assert.match(one.stdout, /^MATCH\tdiagnostic-ref-127\texit=127\tqualification=UNKNOWN$/m);
  });
  await fs.writeFile(path.join(evidence, 'loader-checks.json'), JSON.stringify(checks, null, 2) + '\n');
  for (const item of checks) console.log(`${item.pass ? 'PASS' : 'FAIL'} ${item.name}`);
  assert.ok(checks.every(item => item.pass), JSON.stringify(checks.filter(item => !item.pass)));
}
