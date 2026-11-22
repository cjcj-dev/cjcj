import fs from 'node:fs/promises';
import {nativeLlvmInputs,readSourcePins} from './native-llvm-inputs.mjs';
import {readHostToolchainPin} from './host-toolchain-pin.mjs';
import {nativeSourceSelection} from './bootstrap/native-source-selection.mjs';
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

export function nativePair(env = process.env, {requireHost=true} = {}) {
  const llvm = env.CJCJ_NATIVE_LLVM_REF, runtime = env.CJCJ_NATIVE_RUNTIME_REF;
  if (!llvm && !runtime) {
    if (!env.CJCJ_NATIVE_RUNTIME_ARTIFACT) return null;
    // A named native runtime still has to match the selected pair at receipt.
    const pins = nativeLlvmInputs(env);
    return nativePair({...env, ...pins, CJCJ_NATIVE_HOST_VERSION:
      env.CJCJ_NATIVE_HOST_VERSION || readHostToolchainPin().replace(/^nightly-/, '')}, {requireHost});
  }
  if (![llvm, runtime].every(value => /^[0-9a-f]{40}$/.test(value || '')))
    throw new Error('NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED');
  const hostVersion = env.CJCJ_NATIVE_HOST_VERSION;
  if (requireHost && !/^\d+\.\d+\.\d+-alpha\.\d+$/.test(hostVersion || ''))
    throw new Error('NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED');
  return {llvm, runtime, hostVersion};
}

// A development SDK chooses target components independently of the fixed
// native LLVM tools and the legacy bootstrap/runtime matrix.
export function developmentSdkPair(target) {
  if (target !== 'linux-x64') return null;
  const {runtime, llvm} = readSourcePins();
  const pair = {runtime: runtime.LINUX_X64_SDK_RUNTIME_REF, llvm: llvm.LINUX_X64_SDK_LLVM_SHA,
    hostVersion: readHostToolchainPin('linux_x86_64').replace(/^nightly-/, '')};
  if (![pair.runtime, pair.llvm].every(ref => /^[0-9a-f]{40}$/.test(ref || '')))
    throw new Error('LINUX_X64_SDK_PAIR_PIN');
  return pair;
}

export async function resolveRuntimeSource(env = process.env, pinFile = env.CJCJ_BOOTSTRAP_RUNTIME_PIN) {
  const pins = parsePins(await fs.readFile(PIN_FILE, 'utf8'));
  const pair = nativePair(env,{requireHost:Boolean(env.CJCJ_NATIVE_RUNTIME_ARTIFACT)});
  if (env.CJCJ_NATIVE_RUNTIME_ARTIFACT && !pair)
    throw new Error('NATIVE_RUNTIME_COMPONENT_SELECTION_REQUIRED');
  const requestedOverride = env.CJCJ_RUNTIME_REF_OVERRIDE || '';
  if (pair && requestedOverride && requestedOverride !== pair.runtime) throw new Error('NATIVE_RUNTIME_OVERRIDE_CONFLICT');
  const overrideRef = pair ? '' : requestedOverride;
  const allowOverride = ['1', 'true'].includes((env.CJCJ_ALLOW_RUNTIME_OVERRIDE || '').toLowerCase());
  if (overrideRef && !allowOverride) {
    throw new Error('CJCJ_RUNTIME_REF_OVERRIDE is allowed only by an explicit dry-run/test authorization');
  }
  const runtimeRef = pair?.runtime || overrideRef || pins.RUNTIME_REF;
  if (!/^[0-9a-f]{40}$/i.test(runtimeRef)) {
    throw new Error(`runtime ref must be a full 40-character commit SHA: ${runtimeRef}`);
  }
  const sourceUrl=pair?nativeSourceSelection(env,pair).selection.runtime.repository:pins.RUNTIME_SRC_URL;
  const requestedUrl = env.RUNTIME_SRC_URL || '';
  if (requestedUrl && requestedUrl !== sourceUrl) {
    throw new Error(`runtime source URL mismatch: environment=${requestedUrl}, pin=${sourceUrl}`);
  }
  // An external pin transports a selection; it never authorizes an override.
  // Resolve against the formal pin and explicit authorization first, then
  // require the transported source identity to agree exactly.
  if (pinFile) {
    const selected = parsePins(await fs.readFile(pinFile, 'utf8'));
    if (selected.RUNTIME_REF !== runtimeRef || selected.RUNTIME_SRC_URL !== sourceUrl) {
      throw new Error(`runtime selection pin mismatch: ${pinFile}`);
    }
  }
  return {
    ...pins,
    runtimeRef,
    sourceUrl,
    pinRef: pins.RUNTIME_REF,
    overrideRef,
    nativePair: pair,
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
    console.log(`CJCJ_NATIVE_RUNTIME_REF=${quote(selected.runtimeRef)}\nRUNTIME_SRC_URL=${quote(selected.sourceUrl)}`);
  }
}
