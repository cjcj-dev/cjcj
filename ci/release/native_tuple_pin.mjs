#!/usr/bin/env node
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {validatePin} from './bootstrap_store.mjs';

export function nativeTuplePin(config, platform) {
  const pin = config.platforms?.[platform];
  assert.ok(pin, `BOOTSTRAP_TUPLE_PLATFORM_PIN_MISSING: ${platform}`);
  validatePin(pin);
  assert.equal(pin.platform, platform, 'BOOTSTRAP_TUPLE_PLATFORM_MISMATCH');
  assert.match(pin.sums_sha256 || '', /^[a-f0-9]{64}$/, 'BOOTSTRAP_TUPLE_SUMS_PIN_MISSING');
  assert.equal(pin.files.find(file => file.path === 'SHA256SUMS')?.release_sha256,
    pin.sums_sha256, 'BOOTSTRAP_TUPLE_SUMS_IDENTITY');
  return pin;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = JSON.parse(fs.readFileSync(new URL('../bootstrap_inputs_pin.json', import.meta.url)));
  const pin = nativeTuplePin(config, process.env.TUPLE_PLATFORM);
  console.log(`BOOTSTRAP_NATIVE_TUPLE_PIN platform=${pin.platform} run=${pin.run} commit=${pin.commit}`);
}
