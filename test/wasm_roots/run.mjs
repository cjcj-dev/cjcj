#!/usr/bin/env zx
// Run under the private C6 SDK envsetup, with a fresh private output directory.
import assert from 'node:assert/strict';
import { cp, mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { WASI } from 'node:wasi';

if (process.argv[2] === 'consume') {
  const file = process.argv[3];
  const wasi = new WASI({ version: 'preview1', args: [file], env: process.env, returnOnExit: true });
  const module = await WebAssembly.compile(await readFile(file));
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  process.exitCode = wasi.start(instance);
} else {
  const { $ } = globalThis.$ ? globalThis : await import('zx');
  const out = resolve(process.argv[2]);
  const expected = process.argv[3] ?? 'candidate';
  assert.ok(['candidate', 'baseline', 'without-static', 'without-shadow'].includes(expected));
  const sdk = process.env.CANGJIE_HOME;
  assert.ok(sdk, 'source the private C6 SDK envsetup before running');
  await mkdir(out);
  const cjcTemps = join(out, 'cjc-temps');
  await mkdir(cjcTemps);
  await cp(join(import.meta.dirname, 'src'), join(out, 'src'), { recursive: true });
  await cp(join(import.meta.dirname, 'cjpm.toml'), join(out, 'cjpm.toml'));

  async function run(label, argv, env = process.env) {
    const result = await $({ cwd: out, env, nothrow: true, quiet: true })`${argv}`;
    await writeFile(join(out, label + '.log'), result.stdout + result.stderr);
    await writeFile(join(out, label + '.rc'), String(result.exitCode) + '\n');
    assert.equal(result.exitCode, 0, label);
    return result.stdout + result.stderr;
  }

  async function findWasm(dir) {
    for (const item of await readdir(dir, { withFileTypes: true })) {
      const file = join(dir, item.name);
      if (item.isFile() && item.name.endsWith('.wasm')) return file;
      if (item.isDirectory()) {
        const nested = await findWasm(file);
        if (nested) return nested;
      }
    }
  }

  function calls(text, name) {
    return text.split('\n').filter(line => line.includes(`"${name}" {`)).length;
  }

  const hookFailures = [];
  async function verify(label, file) {
    const trace = await run(label, [process.execPath, '--trace-wasm', '--no-turbo-fast-api-calls',
      import.meta.filename, 'consume', file], { ...process.env, CJ_WASM_GC_STATS: '1' });
    assert.match(trace, /wasm roots canaries reached/, label);
    assert.match(trace, /collections=0 .*precise=0/, label);
    assert.ok(calls(trace, '__wasm_call_ctors') > 0, label);
    assert.ok(calls(trace, 'cjw_heap_alloc') > 0, label);
    const registrations = calls(trace, 'cjw_static_root_table_register');
    const pushes = calls(trace, 'cjw_root_frame_push');
    const pops = calls(trace, 'cjw_root_frame_pop');
    console.log(`${label}: target reached static=${registrations} push=${pushes} pop=${pops}`);
    assert.equal(pushes, pops, 'shadow frame balance');
    // Finish both public entrypoints and check both hooks even when a cut
    // arm, run against candidate expectations, fails one of the hooks.
    for (const [actual, want, invariant] of [
      [registrations > 0, expected !== 'baseline' && expected !== 'without-static', 'static table registration'],
      [pushes > 0, expected !== 'baseline' && expected !== 'without-shadow', 'call-site shadow frames'],
    ]) {
      try {
        assert.equal(actual, want, `${label}: ${invariant}`);
      } catch (error) {
        hookFailures.push(error);
      }
    }
  }

  await run('cjc', [join(sdk, 'bin/cjc'), '--target=wasm32-wasi', '-O0', '-V', `--save-temps=${cjcTemps}`,
    'src/main.cj', '-o', 'standalone.wasm']);
  await verify('cjc-node', join(out, 'standalone.wasm'));
  const cjpm = [join(sdk, 'tools/bin/cjpm'), 'build', '-V', '--target', 'wasm32-wasi'];
  await run('cjpm-fresh', cjpm);
  await run('cjpm-repeat', cjpm);
  const built = await findWasm(join(out, 'target'));
  assert.ok(built, 'cjpm produced a Wasm executable');
  await verify('cjpm-node', built);
  if (hookFailures.length) throw new AggregateError(hookFailures, 'Wasm root hooks');
}
