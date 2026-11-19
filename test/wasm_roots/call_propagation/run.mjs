#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const args = globalThis.argv?._ ?? process.argv.slice(2);
const { $ } = globalThis.$ ? globalThis : await import('zx');
const sdk = process.env.CANGJIE_HOME;
assert.ok(sdk, 'source the private C6 SDK envsetup before running');
assert.ok(args[0], 'pass a fresh output directory');
const out = resolve(args[0]);
const source = join(import.meta.dirname, 'main.cj');
const wasiRunner = join(import.meta.dirname, '..', 'run.mjs');
await mkdir(out);

async function run(dir, name, argv, env = process.env) {
  await writeFile(join(dir, name + '.argv.json'), JSON.stringify(argv) + '\n');
  const result = await $({ cwd: dir, env, nothrow: true, quiet: true })`${argv}`;
  await writeFile(join(dir, name + '.stdout'), result.stdout);
  await writeFile(join(dir, name + '.stderr'), result.stderr);
  await writeFile(join(dir, name + '.rc'), String(result.exitCode) + '\n');
  assert.equal(result.exitCode, 0, name);
  return result.stdout + result.stderr;
}

function verifyFunction(rawIR, name) {
  const lines = rawIR.split('\n');
  const start = lines.findIndex(line => line.startsWith('define ') && new RegExp('\\$\\d+' + name + 'H').test(line));
  assert.ok(start >= 0, name + ' definition');
  const end = lines.indexOf('}', start);
  assert.ok(end > start, name + ' end');
  const body = lines.slice(start, end);
  const site = body.findIndex(line => line.includes(' call ') && /\$\d+allocateNoiseH/.test(line));
  const isCall = line => line.includes(' call ') && !line.includes('@llvm.dbg.');
  const push = body.findLastIndex((line, i) => i < site && isCall(line));
  const pop = body.findIndex((line, i) => i > site && isCall(line));
  const reload = body.findIndex((line, i) => site < i && i < pop && /%wasm\.root\.reload\d* = load volatile /.test(line));
  const use = body.findIndex((line, i) => i > pop && /\$\d+serialOfH/.test(line));
  console.log(name + ' target reached site=' + site + ' push=' + push + ' reload=' + reload +
    ' pop=' + pop + ' use=' + use);
  assert.ok(site >= 0 && push >= 0 && site < reload && reload < pop && pop < use, name + ' frame sequence');
  const pushFrame = body[push].match(/@cjw_root_frame_push\((.*?)\)/)?.[1];
  const popFrame = body[pop].match(/@cjw_root_frame_pop\((.*?)\)/)?.[1];
  assert.ok(pushFrame && pushFrame === popFrame, name + ' same C6 frame');
  const reloadedValue = body[reload].trim().split(' ', 1)[0];
  assert.ok(body.slice(pop + 1, use).some(line => line.includes(reloadedValue)) ||
    body[use].includes(reloadedValue), name + ' uses reloaded root');
}

const errors = [];
for (const split of [1, 8]) {
  const dir = join(out, 'split-' + split);
  const temps = join(dir, 'temps');
  await mkdir(dir);
  await mkdir(temps);
  const wasm = join(dir, 'calls.wasm');
  await run(dir, 'cjc', [join(sdk, 'bin/cjc'), '--target=wasm32-wasi', '-O0', '-V',
    '--apc-split-num', String(split), '--save-temps=' + temps, source, '-o', wasm]);
  const trace = await run(dir, 'node', [process.execPath, '--trace-wasm', '--no-turbo-fast-api-calls',
    wasiRunner, 'consume', wasm], { ...process.env, CJ_WASM_GC_STATS: '1' });
  assert.match(trace, /wasm call roots canaries reached/);
  assert.match(trace, /collections=0 .*precise=0/);
  const calls = name => trace.split('\n').filter(line => line.includes('"' + name + '" {')).length;
  const pushes = calls('cjw_root_frame_push');
  const pops = calls('cjw_root_frame_pop');
  console.log('split=' + split + ' frame events push=' + pushes + ' pop=' + pops);
  assert.equal(pushes, pops, 'shadow frame balance');
  const rawIR = [];
  for (const file of (await readdir(temps)).sort()) {
    if (!file.endsWith('.bc') || file.endsWith('.opt.bc')) continue;
    const ir = join(temps, file + '.ll');
    await run(dir, file + '-dis', [join(sdk, 'third_party/llvm/bin/llvm-dis'), join(temps, file), '-o', ir]);
    rawIR.push(await readFile(ir, 'utf8'));
  }
  assert.equal(rawIR.length, split);
  for (const name of ['keepArgument', 'keepResult']) {
    try {
      verifyFunction(rawIR.join('\n'), name);
    } catch (error) {
      errors.push(new Error('split=' + split + ' ' + error.message, { cause: error }));
    }
  }
  if (pushes === 0) errors.push(new Error('split=' + split + ' Node did not consume a root frame'));
}
if (errors.length) throw new AggregateError(errors, 'Wasm propagation');
