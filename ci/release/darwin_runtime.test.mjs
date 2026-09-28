import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {digest} from './colour_runtime.mjs';
import {verifyRuntimeExports} from './darwin_runtime.mjs';

const platform = process.env.PLATFORM || 'darwin_aarch64';
const tuple = `${platform}_cjnative`;
const files = [`runtime/lib/${tuple}/libcangjie-runtime.dylib`,
  `runtime/lib/${tuple}/libboundscheck.dylib`, `lib/${tuple}/libcangjie-runtime.a`];
const originalProduct = fileURLToPath(new URL('./darwin_runtime.mjs', import.meta.url));
const product = process.env.DARWIN_RT_PRODUCT || originalProduct;
const pinnedExports = fileURLToPath(new URL('./fixtures/darwin_mcc_exports_pinned.txt', import.meta.url));
// The listing a runtime carrying cangjie-runtime#1225 produces: the real pinned
// CJ_MCC_* table plus the four PackageInit entries the Darwin stub now exports
// (cangjie-runtime runtime/src/arch/aarch64_macos/CalleeSavedStub.S:175-195).
const repairedExports = fileURLToPath(new URL('./fixtures/darwin_mcc_exports_repaired.txt', import.meta.url));
function nmShim(dir, name, listing) {
  const shim = path.join(dir, name);
  fs.writeFileSync(shim, `#!/bin/sh\ncat ${JSON.stringify(listing)}\n`);
  fs.chmodSync(shim, 0o755);
  return shim;
}
function fixture(body, listing = repairedExports) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-runtime-'));
  const source = path.join(root, 'source');
  const output = path.join(root, 'output');
  const env = {...process.env, RUNTIME_REF: process.env.RUNTIME_REF || 'a'.repeat(40),
    GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1', COLOUR_RT_RUN_ID: '123', COLOUR_RT_RUN_ATTEMPT: '1',
    DARWIN_RT_NM: nmShim(root, 'nm.sh', listing), DARWIN_RT_NM_FLAGS: ''};
  for (const relative of files) {
    const dest = path.join(source, relative);
    fs.mkdirSync(path.dirname(dest), {recursive: true});
    if (process.env.DARWIN_RT_NATIVE_SOURCE) fs.copyFileSync(path.join(process.env.DARWIN_RT_NATIVE_SOURCE, relative), dest);
    else fs.writeFileSync(dest, `fixture for device test: ${relative}`);
  }
  fs.writeFileSync(path.join(source, 'SOURCE_SHA'), env.RUNTIME_REF);
  const run = (mode, dir = output, reference) => spawnSync(process.execPath,
    [product, mode, dir, platform, ...(reference ? [reference] : [])], {env, encoding: 'utf8'});
  try {
    // Consumer controls start with a manifest emitted by the actual producer.
    // Keep the producer intact when cutting only the consumer bearing point.
    const prepared = spawnSync(process.execPath, [originalProduct, 'prepare', output, platform, source], {env, encoding: 'utf8'});
    assert.equal(prepared.status, 0, prepared.stderr);
    env.COLOUR_RT_MANIFEST_SHA256 = digest(path.join(output, 'manifest.json'));
    // The shim names the Mach-O nm for spawned runs and for in-process calls,
    // which read the same variables from process.env.
    const saved = {nm: process.env.DARWIN_RT_NM, flags: process.env.DARWIN_RT_NM_FLAGS};
    process.env.DARWIN_RT_NM = env.DARWIN_RT_NM;
    process.env.DARWIN_RT_NM_FLAGS = env.DARWIN_RT_NM_FLAGS;
    try { body({root, source, output, env, run}); }
    finally {
      if (saved.nm === undefined) delete process.env.DARWIN_RT_NM; else process.env.DARWIN_RT_NM = saved.nm;
      if (saved.flags === undefined) delete process.env.DARWIN_RT_NM_FLAGS; else process.env.DARWIN_RT_NM_FLAGS = saved.flags;
      fs.rmSync(root, {recursive: true, force: true});
    }
  }
  finally { if (fs.existsSync(root)) fs.rmSync(root, {recursive: true, force: true}); }
}

test('producer copies exactly the three native source libraries', () => fixture(({source, output, run}) => {
  const result = run('prepare', output, source);
  assert.equal(result.status, 0, result.stderr);
  for (const relative of files) {
    assert.equal(digest(path.join(output, relative)), digest(path.join(source, relative)), `PRODUCER_BYTES: ${relative}`);
  }
  console.log(`ASSERT PRODUCER_BYTES ${platform}`);
}));

test('consumer rejects changed library bytes after authentic manifest verification', () => fixture(({source, output, env, run}) => {
  assert.equal(run('verify').status, 0);
  fs.appendFileSync(path.join(output, files[0]), 'changed payload');
  const rejected = run('verify');
  assert.notEqual(rejected.status, 0, 'CONSUMER_REJECTS_CHANGED_BYTES');
  assert.match(rejected.stderr, /COLOUR_RT_FILE_SHA256_MISMATCH/);
  console.log(`ASSERT CONSUMER_REJECTS_CHANGED_BYTES ${platform}`);
}));

test('consumer rejection names expected and actual manifest digests', () => fixture(({env, run}) => {
  assert.equal(run('verify').status, 0);
  const actual = env.COLOUR_RT_MANIFEST_SHA256;
  const wrong = (actual[0] === '0' ? '1' : '0') + actual.slice(1);
  env.COLOUR_RT_MANIFEST_SHA256 = wrong;
  const rejected = run('verify');
  assert.notEqual(rejected.status, 0, 'CONSUMER_REJECTS_WRONG_PIN');
  assert.ok(rejected.stderr.includes(`COLOUR_RT_SHA256_MISMATCH expected=${wrong} actual=${actual}`),
    `WORKFLOW_GREP_FORMAT: ${rejected.stderr}`);
  console.log(`ASSERT CONSUMER_WRONG_PIN_MESSAGE ${platform}`);
}));

test('source classifies missing std only after verifying all native libraries', () => fixture(({source, output, env, run}) => {
  const result = run('source');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, new RegExp(`COLOUR_RT_STD_MISSING: ${platform}`));
  assert.equal(result.stdout.split('COLOUR_RT_LIBRARY_VERIFIED').length - 1, 3);
  console.log(`ASSERT SOURCE_STD_CLASSIFIED ${platform}`);
}));

test('producer gate accepts a runtime that defines every export the std link binds', () => fixture(({root, env}) => {
  const lines = [];
  const saved = console.log;
  console.log = line => lines.push(String(line));
  try { verifyRuntimeExports(root, platform); }
  finally { console.log = saved; }
  assert.equal(lines.filter(l => l.startsWith('COLOUR_RT_EXPORT_VERIFIED')).length, 4,
    `EXPORT_VERIFIED_COUNT: ${lines.join('|')}`);
  assert.equal(env.DARWIN_RT_NM, path.join(root, 'nm.sh'), 'NM_SHIM_IN_USE');
  console.log(`ASSERT EXPORTS_ACCEPTED ${platform}`);
}));

// Real data, not a model copy: this is the CJ_MCC_* table of the pinned
// darwin_aarch64 dylib (see the fixture header) from before #1225. Byte
// verification passes for it, so only this check refuses the library.
test('the pinned pre-1225 runtime is refused on the exports the std link binds', () => fixture(({root}) => {
  let thrown;
  try { verifyRuntimeExports(root, platform); }
  catch (error) { thrown = error; }
  assert.ok(thrown, 'PINNED_PRE1225_ACCEPTED');
  for (const name of ['_CJ_MCC_PackageInitBegin', '_CJ_MCC_PackageInitComplete',
    '_CJ_MCC_PackageInitFail', '_CJ_MCC_PackageInitAbort']) {
    assert.ok(thrown.message.includes(name), `STALE_PIN_HID_A_MISSING_EXPORT: ${name}`);
  }
  console.log(`ASSERT PINNED_PRE1225_REFUSED ${platform} ${thrown.message.split('\n')[0]}`);
}, pinnedExports));

test('source classifies a stale pin on the exports, not as a missing std', () => fixture(({output, run}) => {
  const result = run('source');
  assert.notEqual(result.status, 0);
  // Byte verification still accepts the pinned pair; the export verdict is what
  // this run can reach on a non-Darwin host, so the std classification is not.
  assert.equal(result.stdout.split('COLOUR_RT_LIBRARY_VERIFIED').length - 1, 3);
  assert.match(result.stdout, /COLOUR_RT_EXPORT_(SKIPPED|VERIFIED)/);
  console.log(`ASSERT SOURCE_STD_CLASSIFIED ${platform}`);
}));
