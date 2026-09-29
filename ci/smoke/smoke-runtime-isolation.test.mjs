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
  // The stub also reports the loader path it was handed, so the run-time
  // assertion reads what the driver actually exported rather than a log line.
  fs.writeFileSync(stub, [
    '#!/usr/bin/env node',
    'const fs = require("fs");',
    `fs.appendFileSync(${JSON.stringify(argv)}, JSON.stringify({`,
    '  args: process.argv.slice(2),',
    '  ld: process.env.LD_LIBRARY_PATH || "",',
    '  dyl: process.env.DYLD_LIBRARY_PATH || "",',
    '}) + "\\n");',
    'const out = process.argv[process.argv.indexOf("-o") + 1];',
    'if (out) fs.writeFileSync(out, "#!/bin/sh\\necho ok\\n");',
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
  console.log(`TARGET_ASSERT_EXECUTED smoke_link_args count=${invocations.length}`);
  assert.ok(invocations.length >= SAMPLES.length,
    `expected at least one compiler invocation per sample, got ${invocations.length}: ${result.stderr}`);
  for (const {args} of invocations) {
    const index = args.indexOf('-L');
    assert.notEqual(index, -1,
      `compiler invocation must carry -L for the isolated runtime: ${JSON.stringify(args)}`);
    assert.equal(args[index + 1], root,
      `-L must name the isolated runtime directory, not a default search path`);
  }
});

test('smoke exports the isolated runtime ahead of the official one at run time', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-runtime-dir-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const {result, invocations} = smoke(t, {runtimeLibDir: root});
  // Read the loader path the driver actually exported into its children, not a
  // log line: a driver that names the directory but never exports it would
  // otherwise pass this case.
  const loader = invocations[0]?.ld || invocations[0]?.dyl || '';
  console.log(`TARGET_ASSERT_EXECUTED smoke_loader_path ${JSON.stringify(loader)}`);
  assert.notEqual(loader, '', 'driver must export a loader path to its children');
  assert.equal(loader.split(':')[0], root,
    'the isolated runtime must come first on the loader path');
  assert.match(result.stdout, /linking against the isolated runtime/);
});
