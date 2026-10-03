import fs from 'node:fs';
import path from 'node:path';
import {acquire, digest, validatePin, verify} from './bootstrap_store.mjs';

export async function prepareColourTuple({pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
work = process.env.CJCJ_BOOTSTRAP_INPUTS_WORK
  || path.join(process.env.RUNNER_TEMP || process.env.CANGJIE_BUILD_ROOT || '.', 'bootstrap-inputs'),
sumsSha = process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1]} = {}) {
  const pin = JSON.parse(fs.readFileSync(pinFile, 'utf8'));
  const directory = await acquire(pin, work, {
    mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',
    reason: process.env.CJCJ_BOOTSTRAP_SOURCE_REASON || '',
    depot: process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE || '',
  });
  return verifyColourTuple(directory, {pinFile, sumsSha});
}

// Recheck an already selected, pinned tuple without reacquiring a release.
export function verifyColourTuple(directory, {pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
sumsSha = process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1]} = {}) {
  const pin = JSON.parse(fs.readFileSync(pinFile, 'utf8'));
  validatePin(pin);
  for (const file of pin.files) {
    verify(fs.readFileSync(path.join(directory, file.path)), file.artifact_sha256, file.path);
  }
  if (!/^[0-9a-f]{64}$/.test(sumsSha || '')
      || digest(fs.readFileSync(path.join(directory, 'SHA256SUMS'))) !== sumsSha) {
    throw new Error(`colour tuple SHA256SUMS disagrees with ci/llvm_pin.env: ${directory}`);
  }
  const identities = Object.fromEntries(pin.files.map(file =>
    [file.path, digest(fs.readFileSync(path.join(directory, file.path)))]));
  console.log(`BOOTSTRAP_TUPLE_IDENTITIES=${JSON.stringify(identities)}`);
  return {directory, identities};
}
