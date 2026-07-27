import fs from 'node:fs/promises';

const PIN_FILE = new URL('./runtime_pin.env', import.meta.url);

function parsePins(text) {
  return Object.fromEntries(text.split(/\r?\n/).filter(Boolean).map((line) => {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid runtime pin line: ${line}`);
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
}

export async function resolveRuntimeSource(env = process.env) {
  const pins = parsePins(await fs.readFile(PIN_FILE, 'utf8'));
  const overrideRef = env.CJCJ_RUNTIME_REF_OVERRIDE || '';
  const allowOverride = ['1', 'true'].includes((env.CJCJ_ALLOW_RUNTIME_OVERRIDE || '').toLowerCase());
  if (overrideRef && !allowOverride) {
    throw new Error('CJCJ_RUNTIME_REF_OVERRIDE is allowed only by an explicit dry-run/test authorization');
  }
  const runtimeRef = overrideRef || pins.RUNTIME_REF;
  if (!/^[0-9a-f]{40}$/.test(runtimeRef)) {
    throw new Error(`runtime ref must be a full 40-character commit SHA: ${runtimeRef}`);
  }
  const requestedRef = env.RUNTIME_REF || '';
  if (requestedRef && requestedRef !== runtimeRef) {
    throw new Error(`runtime ref mismatch: environment=${requestedRef}, resolved=${runtimeRef}`);
  }
  const requestedUrl = env.RUNTIME_SRC_URL || '';
  if (requestedUrl && requestedUrl !== pins.RUNTIME_SRC_URL) {
    throw new Error(`runtime source URL mismatch: environment=${requestedUrl}, pin=${pins.RUNTIME_SRC_URL}`);
  }
  return {
    ...pins,
    runtimeRef,
    sourceUrl: pins.RUNTIME_SRC_URL,
    pinRef: pins.RUNTIME_REF,
    overrideRef,
  };
}
