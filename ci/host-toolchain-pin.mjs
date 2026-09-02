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
