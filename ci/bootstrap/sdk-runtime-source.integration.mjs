#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL, fileURLToPath} from 'node:url';
import crypto from 'node:crypto';
import test from 'node:test';

const product = process.env.SDK_RUNTIME_SOURCE_PRODUCT || path.join(path.dirname(fileURLToPath(import.meta.url)), 'runtime_sdk.mjs');
const {verifyBootstrapRuntimeSdk} = await import(pathToFileURL(product));
const sdk = process.env.SDK_RUNTIME_SOURCE_SDK, source = process.env.SDK_RUNTIME_SOURCE_ROOT,
  wrongSource = process.env.SDK_RUNTIME_WRONG_SOURCE;
if (!sdk || !source || !wrongSource) throw new Error('retained genuine SDK, fixed runtime source and independent wrong Git source are required');
const manifest = JSON.parse(await fs.readFile(path.join(sdk, 'SDK.manifest.json'), 'utf8'));
const lock = crypto.createHash('sha256').update(await fs.readFile(path.join(sdk, 'SDK.lock.json'))).digest('hex');
const tuple = `${manifest.platform}_cjnative`;
test('genuine manifest runtime retains the fixed source admission control', async () => {
  await verifyBootstrapRuntimeSdk(sdk, tuple, {}, source, lock, manifest);
  console.log(`TARGET_ASSERTION_EXECUTED runtime-source-normal runtime=${manifest.components.runtime.source.commit}`);
});
test('genuine manifest consumer rejects an independent wrong runtime source', async () => {
  let result;
  try { await verifyBootstrapRuntimeSdk(sdk, tuple, {}, wrongSource, lock, manifest); result = 'accepted'; }
  catch (error) { result = error.message; }
  console.log(`TARGET_ASSERTION_EXECUTED runtime-source-result actual=${result}`);
  assert.equal(result, 'BOOTSTRAP_RUNTIME_SOURCE_MISMATCH', 'manifest consumer must bind the actual std runtime source');
});
