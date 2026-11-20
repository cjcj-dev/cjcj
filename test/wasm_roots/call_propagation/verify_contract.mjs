#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Check producer facts in current, freshly compiled partitions.
const [output, sdkArg] = globalThis.argv?._ ?? process.argv.slice(2);
assert.ok(output && sdkArg, 'pass a fresh output directory and the current SDK');
const { $ } = globalThis.$ ? globalThis : await import('zx');
const out = resolve(output);
const sdk = resolve(sdkArg);
const source = join(import.meta.dirname, 'main.cj');
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

async function compile(dir, sdk, split) {
  const temps = join(dir, 'temps');
  await mkdir(dir);
  await mkdir(temps);
  const result = await run(dir, 'cjc', sdk, [join(sdk, 'bin/cjc'), '--target=wasm32-wasi', '--experimental', '-O0', '-V',
    '--output-type=obj', '--apc-split-num', String(split), '--save-temps=' + temps, source, '-o', join(dir, 'calls.o')]);
  const files = (await readdir(temps)).filter(file => file.endsWith('.bc') && !file.endsWith('.opt.bc')).sort();
  assert.equal(files.length, split, 'saved raw partitions');
  return { result, partitions: files.map(file => join(temps, file)) };
}

function headers(ir, name) {
  const symbol = new RegExp('\\$\\d+' + name + 'H');
  return ir.flatMap(text => text.split('\n').filter(line => /^(define|declare) /.test(line) && symbol.test(line)));
}

for (const split of [1, 8]) {
  const dir = join(out, 'new-' + split);
  const { result, partitions } = await compile(dir, sdk, split);
  assert.equal(result.rc, 0);
  assert.ok((await readdir(dir)).includes('calls.o'));
  const ir = [];
  for (const [index, path] of partitions.entries()) {
    const ll = join(dir, 'partition-' + index + '.ll');
    const dis = await run(dir, 'dis-' + index, sdk, [join(sdk, 'third_party/llvm/bin/llvm-dis'), path, '-o', ll]);
    assert.equal(dis.rc, 0);
    const text = await readFile(ll, 'utf8');
    assert.doesNotMatch(text, /@cjw_root_frame_(push|pop)_complete\(/, 'no frontend transient frames');
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
    const std = join(sdk, 'lib/wasi_wasm32_cjnative/libcangjie-std-core.a');
    const linked = await run(out, 'external-current', sdk, [join(sdk, 'bin/cjc'), '--target=wasm32-wasi',
      '--experimental', '-O0', '-V', partitions[0], std, '-o', join(out, 'external-current.wasm')]);
    assert.equal(linked.rc, 0, linked.log);
  }
}
