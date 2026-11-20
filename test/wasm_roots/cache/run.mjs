#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { copyFile, mkdir, readdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const [output, oldSdkArg, newSdkArg] = globalThis.argv?._ ?? process.argv.slice(2);
assert.ok(output && oldSdkArg && newSdkArg, 'pass a fresh output directory, old SDK and new SDK');
const { $ } = globalThis.$ ? globalThis : await import('zx');
const dir = resolve(output);
const oldSdk = resolve(oldSdkArg);
const newSdk = resolve(newSdkArg);
const fixture = join(import.meta.dirname, '..', 'src/main.cj');
const runner = join(import.meta.dirname, '..', 'run.mjs');
const source = join(dir, 'src');
const temps = join(dir, 'temps');
const wasi = join(dir, 'program.wasm');
await mkdir(dir);
await mkdir(source);
await mkdir(temps);
await copyFile(fixture, join(source, 'main.cj'));

async function digest(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

async function run(label, sdk, argv) {
  const args = ['bash', '-c', 'source "$1/envsetup.sh" && shift && exec "$@"', 'bash', sdk, ...argv];
  await writeFile(join(dir, label + '.argv.json'), JSON.stringify(args) + '\n');
  const result = await $({ cwd: dir, env: { ...process.env, CJ_WASM_GC_STATS: '1' },
    nothrow: true, quiet: true })`${args}`;
  await writeFile(join(dir, label + '.stdout'), result.stdout);
  await writeFile(join(dir, label + '.stderr'), result.stderr);
  await writeFile(join(dir, label + '.rc'), String(result.exitCode) + '\n');
  assert.equal(result.exitCode, 0, label);
  return result.stdout + '\n' + result.stderr;
}

const compilerA = await digest(join(oldSdk, 'libexec/compiler/cjcj-stage1'));
const compilerB = await digest(join(newSdk, 'libexec/compiler/cjcj-stage1'));
assert.notEqual(compilerA, compilerB, 'two actual compiler images');
await writeFile(join(dir, 'compiler-sha256.json'), JSON.stringify({ compilerA, compilerB }) + '\n');
assert.equal(await run('old-version', oldSdk, [join(oldSdk, 'bin/cjc'), '--version']),
  await run('new-version', newSdk, [join(newSdk, 'bin/cjc'), '--version']), 'same public language version');

const vars = {};
for (const [name, sdk] of [['seed', oldSdk], ['switch', newSdk], ['repeat', newSdk]]) {
  const compile = await run(name, sdk, [join(sdk, 'bin/cjc'), '--target=wasm32-wasi',
    '--experimental', '--incremental-compile', '-O0', '-V', '--save-temps=' + temps,
    '-p', source, '-o', wasi]);
  const archive = join(dir, name + '.wasm');
  await copyFile(wasi, archive);
  const node = await run(name + '-node', sdk, [join(sdk, 'tools/bin/node'), '--trace-wasm',
    '--no-turbo-fast-api-calls', runner, 'consume', archive]);
  const events = hook => node.split('"' + hook + '" {').length - 1;
  const frames = events('cjw_root_frame_push');
  assert.equal(frames, events('cjw_root_frame_pop'), name + ' balance');
  assert.match(node, /wasm roots canaries reached/);
  assert.match(node, /collections=0 .*precise=0/);
  const wasm = await digest(archive);
  const dirs = (await readdir(dir)).filter(file => /^\.cached(?:-wasm-[0-9a-f]+)?$/.test(file)).sort();
  vars[name] = { compile, frames, wasm, dirs };
  await writeFile(join(dir, name + '.evidence.json'), JSON.stringify({ frames, wasm, dirs }) + '\n');
  console.log(name + ' reached C6, frames=' + frames + ', cache=' + dirs.join(','));
}

const fresh = arm => /bin\/opt/.test(arm.compile) && /bin\/llc/.test(arm.compile) && /CacheCopy/.test(arm.compile);
assert.ok(fresh(vars.seed), 'older compiler produced its cache and executable');
assert.equal(vars.seed.frames, 0, 'older producer lacks app frames in the frozen C6 install');
assert.ok(fresh(vars.switch), 'new compiler must regenerate on identity change');
assert.ok(vars.switch.frames > 0, 'new compiler generated app frames');
assert.notEqual(vars.seed.wasm, vars.switch.wasm, 'old cached app was not linked');
const newDirs = vars.switch.dirs.filter(d => !vars.seed.dirs.includes(d));
assert.equal(newDirs.length, 1, 'different executable gets a separate artifact namespace');
assert.match(newDirs[0], /^\.cached-wasm-[0-9A-Za-z._-]+$/);
assert.deepEqual(vars.repeat.dirs, vars.switch.dirs);
assert.doesNotMatch(vars.repeat.compile, /bin\/opt|bin\/llc|CacheCopy/, 'same image really reuses objects');
assert.match(vars.repeat.compile, new RegExp(newDirs[0].replace('.', '\\.') + '/[^\\s]+\\.o'),
  'the actual linker input comes from the new namespace');
assert.equal(vars.switch.wasm, vars.repeat.wasm, 'same compiler hit reproduces the rebuilt Wasm');
assert.equal(vars.switch.frames, vars.repeat.frames);
console.log('WASM_CROSS_COMPILER_CACHE_ASSERTIONS_REACHED');
