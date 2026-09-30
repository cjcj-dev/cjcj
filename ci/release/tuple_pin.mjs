import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validatePin} from './bootstrap_store.mjs';

export function tuplePin(target = process.env.CJCJ_SRCBUILD_TARGET
    || `${process.platform}-${process.platform === 'linux' && process.arch === 'arm64' ? 'aarch64' : process.arch}`,
  pinFile = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN) {
  const platform = {
    'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64',
    'darwin-x64': 'darwin_x86_64', 'darwin-arm64': 'darwin_aarch64',
  }[target];
  if (!platform) throw new Error(`LLVM_TUPLE_TARGET_UNSUPPORTED target=${target}`);
  const file = pinFile || new URL(`../llvm-tuple/${platform}.json`, import.meta.url);
  if (!fs.existsSync(file)) throw new Error(`LLVM_TUPLE_PIN_MISSING platform=${platform}`);
  const pin = JSON.parse(fs.readFileSync(file, 'utf8'));
  validatePin(pin);
  if (pin.platform !== platform) throw new Error(`LLVM_TUPLE_PIN_PLATFORM_MISMATCH expected=${platform} actual=${pin.platform}`);
  if (!/^[a-f0-9]{64}$/.test(pin.tuple_sums_sha256 || '')) {
    throw new Error(`LLVM_TUPLE_SUMS_PIN_MISSING platform=${platform}`);
  }
  return pin;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const pin = tuplePin(process.argv[2]);
  console.log(`LLVM_TUPLE_RUN_ID=${pin.run}\nLLVM_TUPLE_RUN_ATTEMPT=${pin.attempt}\nLLVM_TUPLE_ARTIFACT_ID=${pin.artifact}\nLLVM_TUPLE_SUMS_SHA=${pin.tuple_sums_sha256}`);
}
