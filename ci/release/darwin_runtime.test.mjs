import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {digest} from './colour_runtime.mjs';

const platform = process.env.PLATFORM || 'darwin_aarch64';
const tuple = `${platform}_cjnative`;
const extension = platform.startsWith('linux_') ? 'so' : 'dylib';
const files = [`runtime/lib/${tuple}/libcangjie-runtime.${extension}`,
  `runtime/lib/${tuple}/libboundscheck.${extension}`, `lib/${tuple}/libcangjie-runtime.a`];
const originalProduct = fileURLToPath(new URL('./darwin_runtime.mjs', import.meta.url));
const product = process.env.DARWIN_RT_PRODUCT || originalProduct;
function fixture(body) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-runtime-'));
  const source = path.join(root, 'source');
  const output = path.join(root, 'output');
  const env = {...process.env, RUNTIME_REF: process.env.RUNTIME_REF || 'a'.repeat(40),
    GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1', COLOUR_RT_RUN_ID: '123', COLOUR_RT_RUN_ATTEMPT: '1'};
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
    body({root, source, output, env, run});
  }
  finally { fs.rmSync(root, {recursive: true, force: true}); }
}

test('producer copies exactly the three native source libraries', () => fixture(({source, output, run}) => {
  const result = run('prepare', output, source);
  assert.equal(result.status, 0, result.stderr);
  const manifest = JSON.parse(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'));
  assert.equal(manifest.role, 'colour-runtime-libraries');
  assert.equal(manifest.platform, platform);
  if (platform === 'linux_aarch64') assert.equal(manifest.std_status, 'pending-cjcj-768');
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

test('source classifies missing std only after verifying all native libraries', () => fixture(({source, output, env, run}) => {
  const result = run('source');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, new RegExp(`COLOUR_RT_STD_MISSING: ${platform}`));
  assert.equal(result.stdout.split('COLOUR_RT_LIBRARY_VERIFIED').length - 1, 3);
  console.log(`ASSERT SOURCE_STD_CLASSIFIED ${platform}`);
}));
