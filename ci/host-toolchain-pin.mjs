import {readFileSync} from 'node:fs';

export function readHostToolchainPin() {
  const text = readFileSync(new URL('./host_sdk_pin.env', import.meta.url), 'utf8');
  const definitions = [...text.matchAll(/^CJCJ_TOOLCHAIN=(\S+)$/gm)];
  if (definitions.length !== 1) throw new Error('ci/host_sdk_pin.env must define exactly one CJCJ_TOOLCHAIN');
  return requireHostToolchain({CJCJ_TOOLCHAIN: definitions[0][1]});
}

export function requireHostToolchain(env = process.env) {
  const toolchain = env.CJCJ_TOOLCHAIN?.trim();
  if (!toolchain) {
    throw new Error('CJCJ_TOOLCHAIN is required; load ci/cjpm_pin.env before invoking this script');
  }
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
