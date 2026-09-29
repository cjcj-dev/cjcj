// The smoke samples are compiled by our self-built compiler, so they are our
// own artifact: they must link and load the source-built runtime published
// outside the official SDK. Before the runtime stopped overwriting the SDK, the
// driver's default search path happened to hold the coloured bytes and this was
// invisible; with a pristine SDK it is the whole difference between the sample
// linking and failing on undefined CJ_MCC_* references.
//
// These cases drive the real ci/smoke/run_smoke.mjs with a stub compiler that
// records the arguments it was handed, so the assertions are about the product
// wiring, not about a Cangjie toolchain being present.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '../..');
const driver = path.join(repo, 'ci', 'smoke', 'run_smoke.mjs');

function smoke(t, {runtimeLibDir}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-isolation-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const argv = path.join(root, 'argv.log');
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
    'process.exit(0);',
  ].join('\n'), {mode: 0o755});
  const env = {...process.env, CJCJ_PATCHED_RUNTIME_LIB_DIR: runtimeLibDir};
  const result = spawnSync('npx', ['--yes', 'zx@8', driver, stub, path.join(root, 'work')],
    {env, encoding: 'utf8', timeout: 600_000});
  const invocations = fs.existsSync(argv)
    ? fs.readFileSync(argv, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line))
    : [];
  return {root, result, invocations};
}

const SAMPLES = ['01_hello', '02_generics', '03_closures', '04_iface_enum', '05_ffi'];

test('smoke links every sample against the isolated runtime', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-runtime-dir-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {result, invocations} = smoke(t, {runtimeLibDir: root});
  const compiles = invocations.filter(entry => entry.role === 'compiler');
  console.log(`TARGET_ASSERT_EXECUTED smoke_link_args count=${compiles.length}`);
  assert.ok(compiles.length >= SAMPLES.length,
    `expected at least one compiler invocation per sample, got ${compiles.length}: ${result.stderr}`);
  for (const {args} of compiles) {
    const index = args.indexOf('-L');
    assert.notEqual(index, -1,
      `compiler invocation must carry -L for the isolated runtime: ${JSON.stringify(args)}`);
    assert.equal(args[index + 1], root,
      `-L must name the isolated runtime directory, not a default search path`);
  }
});

test('smoke runs the samples on the isolated runtime, not the compiler', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-runtime-dir-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {result, invocations} = smoke(t, {runtimeLibDir: root});
  // The compiler is a self-built executable that already runs on the official
  // SDK runtime in the Build workspace step; prepending the coloured runtime
  // process-wide made it load the coloured runtime and crash in the GC relocate
  // phase (CI run 36613440994). So the loader path must reach the samples and
  // must NOT reach the compiler. Both halves are asserted on the loader value
  // the driver actually exported, not on a log line.
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
    assert.equal(loader.split(':')[0], root,
      `the sample must load the coloured runtime first: ${JSON.stringify(loader)}`);
  }
  assert.match(result.stdout, /linking against the isolated runtime/);
});
