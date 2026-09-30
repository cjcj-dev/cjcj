import fs from 'node:fs';
import path from 'node:path';
import {acquire, digest} from './bootstrap_store.mjs';
import {nativeTuplePin} from './native_tuple_pin.mjs';

export async function prepareColourTuple({pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url),
work = process.env.CJCJ_BOOTSTRAP_INPUTS_WORK
  || path.join(process.env.RUNNER_TEMP || process.env.CANGJIE_BUILD_ROOT || '.', 'bootstrap-inputs'),
sumsSha = process.env.LLVM_TUPLE_SUMS_SHA ?? fs.readFileSync(new URL('../llvm_pin.env', import.meta.url), 'utf8')
  .match(/^LLVM_TUPLE_SUMS_SHA=(.*)$/m)?.[1]} = {}) {
  const config = JSON.parse(fs.readFileSync(pinFile, 'utf8'));
  const target = process.env.CJCJ_SRCBUILD_TARGET || `${process.platform}-${process.arch}`;
  const nativePlatform = {'darwin-arm64': 'darwin_aarch64', 'darwin-x64': 'darwin_x86_64'}[target];
  const pin = nativePlatform && !process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
    ? nativeTuplePin(config, nativePlatform) : config;
  sumsSha = pin.sums_sha256 || sumsSha;
  const directory = await acquire(pin, work, {
    mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',
    reason: process.env.CJCJ_BOOTSTRAP_SOURCE_REASON || '',
    depot: process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE || '',
  });
  if (!/^[0-9a-f]{64}$/.test(sumsSha || '')
      || digest(fs.readFileSync(path.join(directory, 'SHA256SUMS'))) !== sumsSha) {
    throw new Error(`colour tuple SHA256SUMS disagrees with ci/llvm_pin.env: ${directory}`);
  }
  const identities = Object.fromEntries(pin.files.map(file =>
    [file.path, digest(fs.readFileSync(path.join(directory, file.path)))]));
  console.log(`BOOTSTRAP_TUPLE_IDENTITIES=${JSON.stringify(identities)}`);
  return {directory, identities};
}
