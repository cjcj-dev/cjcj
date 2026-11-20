#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Fixture arguments are the frozen closed-program app/src and dep/src. Run
// under a private installed SDK. `fallback` works with the old paired opt;
// `paired` also requires the return-base producer and consumer in opt.
const args = globalThis.argv?._ ?? process.argv.slice(2);
const [mode, output, appArg, depArg] = args;
assert.ok(['fallback', 'paired'].includes(mode) && output && appArg && depArg);
const { $ } = globalThis.$ ? globalThis : await import('zx');
const sdk = process.env.CANGJIE_HOME;
assert.ok(sdk);
const out = resolve(output);
const app = resolve(appArg);
const dep = resolve(depArg);
const cjc = join(sdk, 'bin/cjc');
const llvm = join(sdk, 'third_party/llvm/bin');
const section = '.debug_cj_wasm_return_bases';
const common = ['--target=wasm32-wasi', '--no-sub-pkg', '-V'];
const experimental = ['--experimental', '--wasm-return-bases'];
const issue = '_CN7tickets5issueHl';
const updated = 'same-name replacement selected';
await mkdir(out);

async function run(label, argv) {
  await writeFile(join(out, label + '.argv.json'), JSON.stringify(argv) + '\n');
  const p = await $({ cwd: out, quiet: true, nothrow: true })`${argv}`;
  await writeFile(join(out, label + '.log'), p.stdout + p.stderr);
  await writeFile(join(out, label + '.rc'), String(p.exitCode) + '\n');
  assert.equal(p.exitCode, 0, label);
  return p.stdout + p.stderr;
}

async function buildDependency(label, source, options) {
  const dir = join(out, label, 'tickets');
  const temps = join(dir, 'temps');
  await mkdir(temps, { recursive: true });
  const log = await run(label, [cjc, '-p', source, ...common, ...options, `--output-dir=${dir}/`,
    '--output-type=staticlib', '-o=libtickets.a', `--save-temps=${temps}`]);
  const file = join(dir, 'libtickets.a');
  assert.equal((await run(label + '-members', [join(llvm, 'llvm-ar'), 't', file])).trim(), 'tickets.o');
  return { file, dir, log, bytes: await readFile(file) };
}

async function find(dir, predicate) {
  const hits = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) hits.push(...await find(path, predicate));
    if (entry.isFile() && predicate(entry.name)) hits.push(path);
  }
  return hits.sort();
}

async function buildApp(label, location, decls, archives, optimize, options = [], keepTemps = true) {
  const dir = join(out, location);
  const temps = join(dir, 'temps');
  await mkdir(temps, { recursive: true });
  const log = await run(label, [cjc, '-p', app, ...common, ...experimental, ...optimize, ...options,
    `--import-path=${join(decls.dir, '..')}`, `--output-dir=${dir}/`,
    ...archives.flatMap(a => ['-L', a.dir + '/']), '-ltickets', '--output-type=exe', '-o=main.wasm',
    ...(keepTemps ? [`--save-temps=${temps}`] : [])]);
  const file = join(dir, 'main.wasm');
  const runner = join(import.meta.dirname, '..', 'run.mjs');
  const output = await run(label + '-node', ['env', 'CJ_WASM_GC_STATS=1', join(sdk, 'tools/bin/node'),
    '--no-turbo-fast-api-calls', runner, 'consume', file]);
  assert.match(output, /closed program: local, cross-call and dependency global values survived/);
  assert.match(output, /\bprecise=0\b/);
  return { temps, log, output };
}

async function checkIR(label, temps, rooted) {
  const partitions = await find(temps, n => n.endsWith('.opt.bc'));
  const bodies = [];
  for (const [idx, partition] of partitions.entries()) {
    const ll = join(out, label + '-' + idx + '.ll');
    await run(label + '-dis-' + idx, [join(llvm, 'llvm-dis'), partition, '-o', ll]);
    const text = await readFile(ll, 'utf8');
    const body = text.match(/^define .*<main>.*\{\n([\s\S]*?)^}/m)?.[1];
    if (body) bodies.push(body);
  }
  assert.equal(bodies.length, 1, 'one optimized app main reached');
  const body = bodies[0];
  const original = body.search(new RegExp(`%kept = .*@${issue}\\(i64 31\\)`));
  const collect = body.search(/%sum = .*@\w*allocateNoise\w*\(i64 180000\)/);
  assert.ok(original >= 0 && collect > original, 'actual factory return spans actual allocation call');
  const before = body.slice(original, collect);
  const after = body.slice(collect);
  const store = before.match(/store volatile i8 addrspace\(1\)\* %kept, i8 addrspace\(1\)\*\* (%[-.\w]+)/);
  if (!rooted) {
    assert.equal(store, null, 'legacy definition supplies no proof');
    assert.match(after, /@\w*readTicket\w*\(i8 addrspace\(1\)\* %kept\)/);
    return;
  }
  assert.ok(store, 'MISSING_KEPT_SHADOW_STORE');
  assert.ok(before.indexOf('@cjw_root_frame_push', store.index) > store.index);
  const reload = [...after.matchAll(/(%[-.\w]+) = load volatile i8 addrspace\(1\)\*, i8 addrspace\(1\)\*\* (%[-.\w]+)/g)]
    .find(match => match[2] === store[1]);
  assert.ok(reload, 'MISSING_KEPT_SHADOW_RELOAD');
  assert.ok(after.indexOf('@cjw_root_frame_pop', reload.index) > reload.index);
  const caller = after.split('\n').find(line => line.includes('readTicket') && line.includes(`${reload[1]})`));
  assert.ok(caller, 'readTicket actually consumes the reload');
}

const replacementSource = join(out, 'replacement-source');
await mkdir(replacementSource);
const tickets = await readFile(join(dep, 'tickets.cj'), 'utf8');
const replacement = tickets.replace('public func readRetained(): Int64 {',
  `public func readRetained(): Int64 {\n    println("${updated}")`);
assert.notEqual(replacement, tickets);
await writeFile(join(replacementSource, 'tickets.cj'), replacement);
const legacy = await buildDependency('legacy', dep, []);
const alternate = await buildDependency('alternate', replacementSource, []);
assert.ok(!legacy.bytes.includes(section) && !alternate.bytes.includes(section));
assert.notDeepEqual(legacy.bytes, alternate.bytes);
// A single producer module can verify the constructor body or prove the
// actual allocation directly after inlining. A declaration is insufficient.
const known = mode === 'paired' ? await buildDependency('proven', dep, [...experimental, '-O2']) : legacy;
if (mode === 'paired') {
  assert.ok(known.bytes.includes(section), 'actual ar member carries a proof section');
  assert.match(known.log, /--cj-wasm-export-return-bases=/);
  for (const [label, flags] of [['default', []], ['o2', ['-O2', '--apc-split-num=3']]]) {
    const result = await buildApp(label, label, known, [known, alternate], flags);
    assert.match(result.log, /--cj-wasm-import-return-bases=/);
    assert.match(result.log, /PublishWasmReturnBaseLink/);
    assert.ok(!result.output.includes(updated));
    const staged = await find(result.temps, n => n === 'selected-input.a');
    assert.equal(staged.length, 1);
    assert.ok((await readFile(staged[0])).equals(known.bytes), 'link input is exactly the published archive bytes');
    const mapPaths = await find(result.temps, n => n === 'selected-member-map.o');
    assert.equal(mapPaths.length, 1);
    const map = await readFile(mapPaths[0], 'utf8');
    assert.ok(map.includes(`${staged[0]}(tickets.o):(${issue})`));
    await checkIR(label, result.temps, true);
  }
}

const other = await buildApp('replace', 'replace', known, [alternate, known], ['-O2', '--apc-split-num=3']);
assert.ok(other.output.includes(updated));
assert.doesNotMatch(other.log, /--cj-wasm-import-return-bases=|PublishWasmReturnBaseLink/);
await checkIR('replace', other.temps, false);

for (const [label, libraries, alternateWins] of [['cache-first', [known, alternate], false],
  ['cache-reuse', [alternate, known], true]]) {
  const result = await buildApp(label, 'cache', known, libraries, [], ['--incremental-compile'], false);
  assert.equal(result.output.includes(updated), alternateWins);
  assert.doesNotMatch(result.log, /--cj-wasm-import-return-bases=|PublishWasmReturnBaseLink/);
  console.log(`${label}: optExecuted=${result.log.includes('/llvm/bin/opt')}`);
}
console.log(`WASM_SELECTED_MEMBER_ASSERTIONS_REACHED ${mode}`);
