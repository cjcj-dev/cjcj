import fs from 'node:fs';
import path from 'node:path';
import {acquire, digest, validatePin, verify} from './bootstrap_store.mjs';
import {nativeTuplePlatform, selectTuplePin, verifyTuplePlatform, verifyTupleSources} from './tuple_platform.mjs';

export async function prepareColourTuple({pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
platform = nativeTuplePlatform(), work = process.env.CJCJ_BOOTSTRAP_INPUTS_WORK
  || path.join(process.env.RUNNER_TEMP || process.env.CANGJIE_BUILD_ROOT || '.', 'bootstrap-inputs'),
sumsSha = process.env[`LLVM_TUPLE_SUMS_SHA_${platform}`] ?? (platform === 'linux_x86_64' ? process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1] : undefined)} = {}) {
  const pin = selectTuplePin(JSON.parse(fs.readFileSync(pinFile, 'utf8')), platform);
  const directory = await acquire(pin, work, {
    mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',
    reason: process.env.CJCJ_BOOTSTRAP_SOURCE_REASON || '',
    depot: process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE || '',
  });
  try { return verifyColourTuple(directory, {pinFile, sumsSha, platform}); }
  catch (error) { fs.rmSync(path.dirname(directory), {recursive: true, force: true}); throw error; }
}

// Recheck an already selected, pinned tuple without reacquiring a release.
export function verifyColourTuple(directory, {pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
platform = nativeTuplePlatform(), sumsSha = process.env[`LLVM_TUPLE_SUMS_SHA_${platform}`] ?? (platform === 'linux_x86_64' ? process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1] : undefined)} = {}) {
  const pin = selectTuplePin(JSON.parse(fs.readFileSync(pinFile, 'utf8')), platform);
  validatePin(pin);
  for (const file of pin.files) {
    verify(fs.readFileSync(path.join(directory, file.path)), file.artifact_sha256, file.path);
  }
  verifyTuplePlatform(directory, platform);
  verifyTupleSources(directory);
  if (pin.tuple_sums_sha256) verify(fs.readFileSync(path.join(directory, 'SHA256SUMS')), pin.tuple_sums_sha256, 'platform tuple_sums_sha256');
  sumsSha ??= pin.tuple_sums_sha256;
  if (!/^[0-9a-f]{64}$/.test(sumsSha || '')
      || digest(fs.readFileSync(path.join(directory, 'SHA256SUMS'))) !== sumsSha) {
    throw new Error(`colour tuple SHA256SUMS disagrees with ci/llvm_pin.env: ${directory}`);
  }
  const identities = Object.fromEntries(pin.files.map(file =>
    [file.path, digest(fs.readFileSync(path.join(directory, file.path)))]));
  console.log(`BOOTSTRAP_TUPLE_IDENTITIES=${JSON.stringify(identities)}`);
  return {directory, identities};
}
