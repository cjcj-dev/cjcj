import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const platforms = Object.freeze({
  'linux-x64': 'LINUX_X86_64', 'linux-aarch64': 'LINUX_AARCH64',
  'darwin-x64': 'DARWIN_X86_64', 'darwin-arm64': 'DARWIN_AARCH64', 'windows-x64': 'WINDOWS_X86_64',
  linux_x86_64: 'LINUX_X86_64', linux_aarch64: 'LINUX_AARCH64',
  darwin_x86_64: 'DARWIN_X86_64', darwin_aarch64: 'DARWIN_AARCH64', windows_x86_64: 'WINDOWS_X86_64',
});
export function hostPlatform() {
  const arch = process.arch === 'arm64' ? 'aarch64' : process.arch === 'x64' ? 'x86_64' : process.arch;
  return `${process.platform === 'win32' ? 'windows' : process.platform}_${arch}`;
}
export function parseHostToolchainPin(text, platform = hostPlatform()) {
  const env = {};
  for (const line of text.trim().split(/\r?\n/)) {
    const match = line.match(/^(CJCJ_TOOLCHAIN(?:_[A-Z0-9_]+)?)=(\S+)$/);
    if (!match) throw new Error(`unsupported host toolchain pin record: ${line}`);
    if (match[1] in env) throw new Error(`${match[1]} is duplicated in ci/host_sdk_pin.env`);
    if (match[1] !== 'CJCJ_TOOLCHAIN' && !Object.values(platforms).some(key => match[1] === `CJCJ_TOOLCHAIN_${key}`)) throw new Error(`unsupported host platform pin: ${match[1]}`);
    env[match[1]] = match[2];
  }
  if (!env.CJCJ_TOOLCHAIN) throw new Error('ci/host_sdk_pin.env must define exactly one CJCJ_TOOLCHAIN');
  return requireHostToolchain(env, platform);
}
export function readHostToolchainPin(platform = hostPlatform(), pinFile = new URL('./host_sdk_pin.env', import.meta.url)) {
  return parseHostToolchainPin(readFileSync(pinFile, 'utf8'), platform);
}
export function requireHostToolchain(env = process.env, platform = hostPlatform()) {
  const selected = platforms[platform];
  if (!selected) throw new Error(`unsupported host platform: ${platform}`);
  const toolchain = (env[`CJCJ_TOOLCHAIN_${selected}`] || env.CJCJ_TOOLCHAIN)?.trim();
  if (!toolchain) throw new Error('CJCJ_TOOLCHAIN is required; load ci/host_sdk_pin.env before invoking this script');
  return toolchain;
}

export function hostToolchainFromCjcVersion(output) {
  const match = output.match(/^Cangjie Compiler:\s+(\S+)\s+\(cjnative\)$/m);
  if (!match) throw new Error('cjc --version did not report a cjnative compiler version');
  return `nightly-${match[1]}`;
}

export function requireMatchingBaseSdkToolchain({hostToolchain, baseSdkToolchain}) {
  const host = hostToolchain?.trim();
  const base = baseSdkToolchain?.trim();
  if (!host || !base) throw new Error('host and base SDK toolchain identities are required before linking');
  if (host !== base) {
    throw new Error(`refusing to link base SDK ${base} into host toolchain directory ${host}`);
  }
  return base;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const value = name => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
  const pin = readHostToolchainPin(value('--platform') || hostPlatform(), value('--file'));
  console.log(args.includes('--github-env') ? `CJCJ_TOOLCHAIN=${pin}` : pin);
}
