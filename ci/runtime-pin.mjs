import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const PIN_FILE = new URL('./runtime_pin.env', import.meta.url);

function parsePins(text) {
  return Object.fromEntries(text.split(/\r?\n/).filter(Boolean).map((line) => {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid runtime pin line: ${line}`);
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
}

export async function resolveRuntimeSource(env = process.env, pinFile = env.CJCJ_BOOTSTRAP_RUNTIME_PIN) {
  const pins = parsePins(await fs.readFile(PIN_FILE, 'utf8'));
  const overrideRef = env.CJCJ_RUNTIME_REF_OVERRIDE || '';
  const allowOverride = ['1', 'true'].includes((env.CJCJ_ALLOW_RUNTIME_OVERRIDE || '').toLowerCase());
  if (overrideRef && !allowOverride) {
    throw new Error('CJCJ_RUNTIME_REF_OVERRIDE is allowed only by an explicit dry-run/test authorization');
  }
  const runtimeRef = overrideRef || pins.RUNTIME_REF;
  if (!/^[0-9a-f]{40}$/i.test(runtimeRef)) {
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
  // An external pin transports a selection; it never authorizes an override.
  // Resolve against the formal pin and explicit authorization first, then
  // require the transported source identity to agree exactly.
  if (pinFile) {
    const selected = parsePins(await fs.readFile(pinFile, 'utf8'));
    if (selected.RUNTIME_REF !== runtimeRef || selected.RUNTIME_SRC_URL !== pins.RUNTIME_SRC_URL) {
      throw new Error(`runtime selection pin mismatch: ${pinFile}`);
    }
  }
  return {
    ...pins,
    runtimeRef,
    sourceUrl: pins.RUNTIME_SRC_URL,
    pinRef: pins.RUNTIME_REF,
    overrideRef,
  };
}

export async function writeRuntimeSelection(file, env = process.env) {
  const selected = await resolveRuntimeSource(env);
  await fs.mkdir(path.dirname(path.resolve(file)), {recursive: true});
  await fs.writeFile(file, `RUNTIME_REF=${selected.runtimeRef}\nRUNTIME_SRC_URL=${selected.sourceUrl}\n`);
  return selected;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, file] = process.argv.slice(2);
  const selected = mode === '--write' ? await writeRuntimeSelection(file)
    : await resolveRuntimeSource(process.env, file);
  if (mode !== '--write' && mode !== '--shell') throw new Error('usage: runtime-pin.mjs --write|--shell FILE');
  if (mode === '--shell') {
    const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
    console.log(`RUNTIME_REF=${quote(selected.runtimeRef)}\nRUNTIME_SRC_URL=${quote(selected.sourceUrl)}`);
  }
}
