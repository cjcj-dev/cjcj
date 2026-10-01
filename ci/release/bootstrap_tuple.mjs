import fs from 'node:fs';
import path from 'node:path';
import {acquire, digest, validatePin, verify} from './bootstrap_store.mjs';
import {nativeTuplePin} from './native_tuple_pin.mjs';

// The pin file carries the Linux cell plus a per-platform entry. A Darwin cell
// must select its own entry, so acquisition and re-verification both go through
// this one selector; verifying a Darwin download against the Linux entry is
// exactly the mismatch the re-check exists to catch.
function selectPin(pinFile) {
  const config = JSON.parse(fs.readFileSync(pinFile, 'utf8'));
  const target = process.env.CJCJ_SRCBUILD_TARGET || `${process.platform}-${process.arch}`;
  const nativePlatform = {'darwin-arm64': 'darwin_aarch64', 'darwin-x64': 'darwin_x86_64'}[target];
  return nativePlatform && !process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
    ? nativeTuplePin(config, nativePlatform) : config;
}

export async function prepareColourTuple({pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
work = process.env.CJCJ_BOOTSTRAP_INPUTS_WORK
  || path.join(process.env.RUNNER_TEMP || process.env.CANGJIE_BUILD_ROOT || '.', 'bootstrap-inputs'),
sumsSha = process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1]} = {}) {
  const pin = selectPin(pinFile);
  sumsSha = pin.sums_sha256 || sumsSha;
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
  const pin = selectPin(pinFile);
  validatePin(pin);
  sumsSha = pin.sums_sha256 || sumsSha;
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
