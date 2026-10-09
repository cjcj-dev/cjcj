#!/usr/bin/env zx
// Observer-only qualification: opaque payloads, no LLVM reader or package run.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileDigest} from '../../ci/bootstrap/sdk-manifest.mjs';
import {capturePackageStdInput, assertPublishedPackageStd} from './fixtures/package-observation.mjs';

const payloads = ['lib/tuple/libcangjie-std-core.a', 'modules/tuple/std.cjo',
  'modules/tuple/std/pkg.bc', 'runtime/lib/tuple/libcangjie-std.so', 'std-producer.json'];

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(process.env.SDK_CONSUMER_TEST_ROOT || os.tmpdir(), 'package-observation-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'package-input');
  const config = {softwareDir: path.join(root, 'software')};
  const published = path.join(config.softwareDir, 'cangjie');
  const files = {};
  for (const relative of payloads) {
    const file = path.join(sdk, relative);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, `observer-only opaque std payload ${relative}`);
    files[relative] = {type: 'file', sha256: await fileDigest(file), component: 'std'};
  }
  const link = 'lib/tuple/std-relative.a';
  await fs.symlink('libcangjie-std-core.a', path.join(sdk, link));
  files[link] = {type: 'symlink', target: 'libcangjie-std-core.a',
    sha256: await fileDigest(path.join(sdk, link)), component: 'std'};
  await fs.mkdir(path.join(sdk, 'tools', 'bin'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'tools', 'bin', 'cjpm'), 'host distribution tool');
  files['tools/bin/cjpm'] = {type: 'file', component: 'official',
    sha256: await fileDigest(path.join(sdk, 'tools', 'bin', 'cjpm'))};
  // This is an observer fixture schema, not a sealed SDK producer receipt.
  await fs.writeFile(path.join(sdk, 'SDK.manifest.json'), JSON.stringify({files,
    components: {
      std: {receiptJson: JSON.stringify({component: {domain: 'target', roles: ['std']}})},
      official: {receiptJson: JSON.stringify({component: {domain: 'host', roles: ['std', 'cjpm']}})},
    }}));
  const input = await capturePackageStdInput(sdk);
  await fs.cp(sdk, published, {recursive: true, dereference: false});
  return {sdk, config, published, input};
}

test('package observer accepts distinct publication with complete std and identity', async t => {
  const f = await fixture(t);
  assert.equal(f.input.files.length, payloads.length + 1);
  await fs.writeFile(path.join(f.published, 'tools', 'bin', 'cjpm'), 'built tool replacing host tool');
  await assertPublishedPackageStd(f);
});

for (const relative of payloads) {
  test(`package observer rejects published std change: ${relative}`, async t => {
    const f = await fixture(t);
    await fs.appendFile(path.join(f.published, relative), ' changed only in publication');
    // The input remains intact: a source-only observation must fail this test.
    await capturePackageStdInput(f.sdk);
    await assert.rejects(assertPublishedPackageStd(f), /published package must preserve the complete input std payload/);
  });
}

test('package observer rejects a different input identity at publication', async t => {
  const f = await fixture(t);
  await fs.appendFile(path.join(f.published, 'SDK.manifest.json'), '\n');
  await assert.rejects(assertPublishedPackageStd(f), /corresponding package input producer identity/);
});

test('package observer rejects source SDK self-comparison', async t => {
  const f = await fixture(t);
  await assert.rejects(assertPublishedPackageStd({...f, config: {softwareDir: path.dirname(f.sdk)}}), {code: 'ENOENT'});
  await fs.rm(f.published, {recursive: true});
  await fs.symlink(f.sdk, f.published);
  await assert.rejects(assertPublishedPackageStd(f), /distinct published SDK/);
});

test('package observer authenticates input std against its producer manifest', async t => {
  const f = await fixture(t);
  await fs.appendFile(path.join(f.sdk, 'modules/tuple/std.cjo'), ' changed input');
  await assert.rejects(capturePackageStdInput(f.sdk), /input std must match its producer manifest/);
});
