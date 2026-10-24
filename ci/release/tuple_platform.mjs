import fs from 'node:fs';
import path from 'node:path';

export const tuplePlatforms = ['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64'];
export function nativeTuplePlatform(env = process.env) {
  const target = env.CJCJ_SRCBUILD_TARGET;
  const platforms = {'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64',
    'darwin-x64': 'darwin_x86_64', 'darwin-arm64': 'darwin_aarch64'};
  const platform = target ? platforms[target] : `${process.platform}_${process.arch === 'arm64' ? 'aarch64' : process.arch === 'x64' ? 'x86_64' : process.arch}`;
  if (!tuplePlatforms.includes(platform)) throw new Error(`BOOTSTRAP_TARGET_UNSUPPORTED: ${target || platform}`);
  return platform;
}

function platformFailure(code, platform, actual) {
  console.error(`${code} expected=${platform} actual=${actual}`);
  process.exit(65);
}

export function selectTuplePin(pins, platform) {
  // The current official single-tuple pin predates the platform registry. Its
  // untagged payload is x86 Linux only; never use it as another host's input.
  const pin = pins.version === 2 ? pins.platforms?.[platform]
    : pins.version === 1 && (pins.platform || 'linux_x86_64') === platform ? pins : null;
  if (!pin) platformFailure('BOOTSTRAP_TUPLE_PLATFORM_PIN_MISSING', platform, platform);
  if ((pin.platform || 'linux_x86_64') !== platform) platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, pin.platform);
  return pin;
}

export function verifyTuplePlatform(tuple, platform) {
  const platforms = fs.readFileSync(path.join(tuple, 'MANIFEST'), 'utf8')
    .split('\n').filter(line => line.startsWith('PLATFORM=')).map(line => line.slice(9));
  if (platforms.length !== 1 || platforms[0] !== platform) {
    platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, platforms.join(','));
  }
}

export function verifyTupleSources(tuple, env = process.env) {
  const text = fs.readFileSync(path.join(tuple, 'MANIFEST'), 'utf8');
  const values = key => text.split('\n').filter(line => line.startsWith(key+'=')).map(line => line.slice(key.length+1));
  const llvm = values('LLVM_SHA'), runtime = values('RUNTIME_REF');
  // Historical pinned tuples have no paired-runtime record. Keep that path for
  // the historical default only; an explicit new pair must never inherit it.
  if (!env.CJCJ_NATIVE_RUNTIME_REF && !env.CJCJ_RUNTIME_REF_OVERRIDE && !runtime.some(Boolean)) return;
  const pin = (file,key) => fs.readFileSync(new URL('../'+file, import.meta.url),'utf8')
    .match(new RegExp('^'+key+'=([a-f0-9]{40})$','m'))?.[1];
  const wantedLlvm = env.LLVM_SHA || pin('llvm_pin.env','LLVM_SHA');
  const wantedRuntime = env.CJCJ_NATIVE_RUNTIME_REF || env.RUNTIME_REF || pin('runtime_pin.env','RUNTIME_REF');
  if (![wantedLlvm,wantedRuntime].every(value => /^[a-f0-9]{40}$/.test(value || ''))
      || llvm.length !== 1 || runtime.length !== 1
      || llvm[0] !== wantedLlvm || runtime[0] !== wantedRuntime) {
    throw new Error('BOOTSTRAP_TUPLE_SOURCE_PAIR_MISMATCH');
  }
}
