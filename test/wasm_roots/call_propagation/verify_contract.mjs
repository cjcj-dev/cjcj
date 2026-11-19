#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Both private SDKs here contain the old opt. The new compiler must leave
// inspectable raw IR and stop before producing an object with that opt.
const [output, oldSdkArg, newSdkArg] = globalThis.argv?._ ?? process.argv.slice(2);
assert.ok(output && oldSdkArg && newSdkArg, 'pass a fresh output directory, the old SDK, and the new compiler SDK');
const { $ } = globalThis.$ ? globalThis : await import('zx');
const out = resolve(output);
const oldSdk = resolve(oldSdkArg);
const newSdk = resolve(newSdkArg);
const source = join(import.meta.dirname, 'main.cj');
const request = /--cj-wasm-root-version=1\b/;
const flag = /!(\d+) = !\{i32 1, !"cj\.wasm\.root\.version", i32 1\}/;
const fact = /"cj\.wasm\.base"/;
await mkdir(out);

async function run(dir, label, sdk, args) {
  const command = ['bash', '-c', 'source "$1/envsetup.sh" && shift && exec "$@"', 'bash', sdk, ...args];
  await writeFile(join(dir, label + '.argv.json'), JSON.stringify(command) + '\n');
  const result = await $({ cwd: dir, nothrow: true, quiet: true })`${command}`;
  const log = result.stdout + result.stderr;
  await writeFile(join(dir, label + '.log'), log);
  await writeFile(join(dir, label + '.rc'), String(result.exitCode) + '\n');
  return { rc: result.exitCode, log };
}

function checkOptRejected(result) {
  assert.notEqual(result.rc, 0, 'compiler returned a failure');
  assert.match(result.log, request, 'public compiler passes the v1 request');
  assert.match(result.log, /[Uu]nknown command line argument ['"]--cj-wasm-root-version=1/,
    'old opt reached and rejected the request');
}

async function compile(dir, sdk, split) {
  const temps = join(dir, 'temps');
  await mkdir(dir);
  await mkdir(temps);
  const result = await run(dir, 'cjc', sdk, [join(sdk, 'bin/cjc'), '--target=wasm32-wasi', '-O0', '-V',
    '--output-type=obj', '--apc-split-num', String(split), '--save-temps=' + temps, source, '-o', join(dir, 'calls.o')]);
  const files = (await readdir(temps)).filter(file => file.endsWith('.bc') && !file.endsWith('.opt.bc')).sort();
  assert.equal(files.length, split, 'saved raw partitions');
  return { result, partitions: files.map(file => join(temps, file)) };
}

function headers(ir, name) {
  const symbol = new RegExp('\\$\\d+' + name + 'H');
  return ir.flatMap(text => text.split('\n').filter(line => /^(define|declare) /.test(line) && symbol.test(line)));
}

const old = await compile(join(out, 'old'), oldSdk, 1);
assert.equal(old.result.rc, 0);
assert.doesNotMatch(old.result.log, request);
for (const split of [1, 8]) {
  const dir = join(out, 'new-' + split);
  const { result, partitions } = await compile(dir, newSdk, split);
  checkOptRejected(result);
  assert.ok(!(await readdir(dir)).includes('calls.o'), 'old opt did not produce an object');
  const ir = [];
  for (const [index, path] of partitions.entries()) {
    const ll = join(dir, 'partition-' + index + '.ll');
    const dis = await run(dir, 'dis-' + index, oldSdk, [join(oldSdk, 'third_party/llvm/bin/llvm-dis'), path, '-o', ll]);
    assert.equal(dis.rc, 0);
    const text = await readFile(ll, 'utf8');
    const marker = text.match(flag);
    assert.ok(marker, 'Error module flag with i32 version 1 in every Wasm partition');
    assert.ok(text.match(/^!llvm\.module\.flags = !\{([^}]+)\}/m)?.[1].split(', ').includes('!' + marker[1]),
      'version is actually in llvm.module.flags');
    assert.doesNotMatch(text, /@cjw_root_frame_(push|pop)\(/, 'no frontend transient frames');
    ir.push(text);
  }
  const argument = headers(ir, 'keepArgument');
  assert.equal(argument.filter(line => line.startsWith('define ')).length, 1);
  for (const line of argument) {
    if (line.startsWith('define ')) {
      assert.match(line.split(' @')[1], fact, 'proven AS1 parameter has a definition attribute');
    } else {
      assert.doesNotMatch(line, fact, 'parameter facts are not repeated on declarations');
    }
  }
  const returns = headers(ir, 'newCanary');
  assert.equal(returns.filter(line => line.startsWith('define ')).length, 1);
  if (split === 8) assert.ok(returns.some(line => line.startsWith('declare ')), 'cross-partition return reaches a declaration');
  for (const line of returns) assert.match(line.split(' @')[0], fact, 'proven AS1 return on each reference');
  console.log('WASM_ROOT_PROVENANCE_REACHED split=' + split);
  if (split === 1) {
    for (const [label, path, marked] of [['external-old', old.partitions[0], false],
      ['external-v1', partitions[0], true]]) {
      const external = await run(out, label, newSdk, [join(newSdk, 'bin/cjc'), '--target=wasm32-wasi',
        '--output-type=obj', '-O0', '-V', path, '-o', join(out, label + '.o')]);
      if (marked) {
        checkOptRejected(external);
      } else {
        assert.equal(external.rc, 0, 'unmarked external bitcode still accepts old opt');
        assert.doesNotMatch(external.log, request);
      }
    }
  }
}
console.log('WASM_ROOT_OPT_GUARD_ASSERTIONS_REACHED');
