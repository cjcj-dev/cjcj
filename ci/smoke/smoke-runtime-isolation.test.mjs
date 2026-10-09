// Exercises the real smoke driver; fixtures observe argv, loader and compiler transcript.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '../..');
const driver = path.join(repo, 'ci', 'smoke', 'run_smoke.mjs');

function smoke(t, {runtimeLibDir, transcript = ''}) {
  const evidence = process.env.PRODUCER_EVIDENCE_TEST_ROOT;
  if (evidence) fs.mkdirSync(evidence, {recursive: true});
  const root = fs.mkdtempSync(path.join(evidence || os.tmpdir(), 'smoke-isolation-'));
  if (!evidence) t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const argv = path.join(root, 'argv.log');
  const sdk = path.join(root, 'official-sdk');
  for (const directory of ['modules', 'lib', 'runtime/lib', 'third_party/llvm/lib', 'tools/lib']) {
    fs.mkdirSync(path.join(sdk, directory), {recursive: true});
  }
  transcript = transcript.replaceAll('/official/sdk', sdk);
  // A compiler stub that records argv and then "builds" by copying the expected
  // sample output, so the driver proceeds to the run phase as it would for real.
  const stub = path.join(root, 'cjcj');
  // The stub plays both roles -- the compiler and, once it has "built" a sample,
  // the sample itself -- so it reports which role it was in and the loader path
  // it was handed. The assertion reads those reported values, never a log line.
  const sample = path.join(root, 'sample-runner');
  fs.writeFileSync(sample, [
    '#!/usr/bin/env node',
    'const fs = require("fs");',
    `fs.appendFileSync(${JSON.stringify(argv)}, JSON.stringify({`,
    '  role: "sample",',
    '  ld: process.env.LD_LIBRARY_PATH || "",',
    '  dyl: process.env.DYLD_LIBRARY_PATH || "",',
    '}) + "\\n");',
    'process.exit(0);',
  ].join('\n'), {mode: 0o755});
  fs.writeFileSync(stub, [
    '#!/usr/bin/env node',
    'const fs = require("fs");',
    `fs.appendFileSync(${JSON.stringify(argv)}, JSON.stringify({`,
    '  role: "compiler",',
    '  args: process.argv.slice(2),',
    '  ld: process.env.LD_LIBRARY_PATH || "",',
    '  dyl: process.env.DYLD_LIBRARY_PATH || "",',
    '}) + "\\n");',
    'const out = process.argv[process.argv.indexOf("-o") + 1];',
    // The produced sample is the reporting runner, so the driver then runs it
    // exactly as it would run a real compiled binary. Copied by absolute path:
    // process.argv[1] is the .cj source, not this script, under zx.
    `if (out) fs.writeFileSync(out, fs.readFileSync(${JSON.stringify(sample)}, "utf8"), {mode: 0o755});`,
    `console.error(${JSON.stringify(transcript)});`,
    'process.exit(0);',
  ].join('\n'), {mode: 0o755});
  const env = {...process.env, CJCJ_PATCHED_RUNTIME_LIB_DIR: runtimeLibDir, CANGJIE_HOME: sdk};
  const result = spawnSync('npx', ['--yes', 'zx@8', driver, stub, path.join(root, 'work')],
    {cwd: root, env, encoding: 'utf8', timeout: 600_000});
  fs.writeFileSync(path.join(root, 'invocation-result.json'), JSON.stringify({status: result.status,
    signal: result.signal, stdout: result.stdout, stderr: result.stderr, error: result.error?.message}, null, 2));
  const invocations = fs.existsSync(argv)
    ? fs.readFileSync(argv, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line))
    : [];
  return {root, result, invocations};
}

const SAMPLES = ['01_hello', '02_generics', '03_closures', '04_iface_enum', '05_ffi'];

test('smoke keeps the official SDK link search without a patched runtime override', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-runtime-dir-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {result, invocations} = smoke(t, {runtimeLibDir: root});
  const compiles = invocations.filter(entry => entry.role === 'compiler');
  console.log(`TARGET_ASSERT_EXECUTED smoke_link_args count=${compiles.length}`);
  assert.ok(compiles.length >= SAMPLES.length,
    `expected at least one compiler invocation per sample, got ${compiles.length}: ${result.stderr}`);
  for (const {args} of compiles) {
    assert.ok(!args.includes(root), `unexpected patched runtime argument: ${JSON.stringify(args)}`);
    assert.ok(args.includes('--verbose'), 'real linker transcript must be observable');
  }
});

test('smoke preserves the official loader environment for compiler and samples', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-runtime-dir-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {result, invocations} = smoke(t, {runtimeLibDir: root});
  const loaderOf = entry => entry.ld || entry.dyl || '';
  const compiles = invocations.filter(entry => entry.role === 'compiler');
  const samples = invocations.filter(entry => entry.role === 'sample');
  assert.ok(compiles.length >= SAMPLES.length, 'compiler must be invoked per sample');
  assert.ok(samples.length >= SAMPLES.length,
    `expected the driver to run a sample per compile, got ${samples.length}`);
  for (const entry of compiles) {
    const loader = loaderOf(entry);
    console.log(`TARGET_ASSERT_EXECUTED smoke_compiler_loader ${JSON.stringify(loader)}`);
    assert.ok(!loader.split(':').includes(root),
      `the compiler must not load the coloured runtime: ${JSON.stringify(loader)}`);
  }
  for (const entry of samples) {
    const loader = loaderOf(entry);
    console.log(`TARGET_ASSERT_EXECUTED smoke_sample_loader ${JSON.stringify(loader)}`);
    assert.ok(!loader.split(':').includes(root),
      `sample must retain the official runtime: ${JSON.stringify(loader)}`);
  }
  assert.doesNotMatch(result.stdout, /SMOKE_RUNTIME_MISMATCH/);
});


test('smoke rejects actual link output pairing official std with patched runtime', t => {
  const {result, invocations} = smoke(t, {runtimeLibDir: '/isolated/runtime',
    transcript: '/usr/bin/ld -L/isolated/runtime -L/official/sdk/lib/linux_x86_64_cjnative -l:libcangjie-std-core.a /official/sdk/lib/linux_x86_64_cjnative/cjstart.o'});
  console.log(`TARGET_ASSERT_EXECUTED smoke_mixed_link rc=${result.status}`);
  assert.match(result.stdout, /compile failed:.*rc=86/);
  assert.match(result.stdout, /SMOKE_RUNTIME_MISMATCH/);
  assert.equal(invocations.filter(entry => entry.role === 'sample').length, 0);
});

test('smoke accepts official std and runtime link output', t => {
  const {result, invocations} = smoke(t, {runtimeLibDir: '/isolated/runtime',
    transcript: '/usr/bin/ld -L/official/sdk/runtime/lib/linux_x86_64_cjnative -L/official/sdk/lib/linux_x86_64_cjnative -l:libcangjie-std-core.a'});
  console.log('TARGET_ASSERT_EXECUTED smoke_official_link');
  assert.doesNotMatch(result.stdout, /SMOKE_RUNTIME_MISMATCH/);
  assert.ok(invocations.filter(entry => entry.role === 'sample').length >= SAMPLES.length);
});
