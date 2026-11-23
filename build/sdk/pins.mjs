// Fixed source and platform-dependency pins, parsed once for the whole production line.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const SOURCE_PIN = path.join(here, 'source_pin.env');
export const WASI_PIN = path.join(here, 'wasi_pin.env');
export const REPOSITORIES = Object.freeze(['COMPILER', 'RUNTIME', 'LLVM', 'STDX', 'TOOLS', 'JAVA_INTEROP', 'BOUNDS', 'PCRE2', 'FLATBUFFERS']);
const SHA = /^[0-9a-f]{40}$/, HEX64 = /^[0-9a-f]{64}$/, VERSION = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/;

export function parseEnv(text, file = '<env>') {
  const values = {};
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
    if (!match) throw new Error(`PIN_SYNTAX ${file}:${index + 1}`);
    if (Object.hasOwn(values, match[1])) throw new Error(`PIN_DUPLICATE ${file}:${index + 1} ${match[1]}`);
    values[match[1]] = match[2];
  }
  return values;
}

export function validatePins(source, wasi) {
  for (const name of REPOSITORIES) {
    const ref = source[`${name}_REF`], url = source[`${name}_SRC_URL`];
    if (!SHA.test(ref ?? '')) throw new Error(`PIN_REF ${name}_REF must be a full 40-hex commit`);
    if (!/^https:\/\/[^\s]+\.git$/.test(url ?? '')) throw new Error(`PIN_URL ${name}_SRC_URL`);
  }
  for (const name of ['CANGJIE_VERSION', 'HOST_SDK_VERSION'])
    if (!VERSION.test(source[name] ?? '')) throw new Error(`PIN_VERSION ${name}`);
  if (!HEX64.test(wasi.WASI_SYSROOT_SHA256 ?? '')) throw new Error('PIN_WASI_SHA256');
  if (!/^https:\/\/\S+\.tar\.gz$/.test(wasi.WASI_SYSROOT_URL ?? '')) throw new Error('PIN_WASI_URL');
  const known = new Set([...REPOSITORIES.flatMap(n => [`${n}_REF`, `${n}_SRC_URL`]), 'CANGJIE_VERSION', 'HOST_SDK_VERSION']);
  for (const key of Object.keys(source)) if (!known.has(key)) throw new Error(`PIN_UNKNOWN ${key}`);
  return true;
}

export function loadPins({sourceFile = SOURCE_PIN, wasiFile = WASI_PIN} = {}) {
  const source = parseEnv(fs.readFileSync(sourceFile, 'utf8'), sourceFile);
  const wasi = parseEnv(fs.readFileSync(wasiFile, 'utf8'), wasiFile);
  validatePins(source, wasi);
  const repos = Object.fromEntries(REPOSITORIES.map(name => [name.toLowerCase().replace('java_interop', 'javaInterop'),
    Object.freeze({url: source[`${name}_SRC_URL`], commit: source[`${name}_REF`]})]));
  return Object.freeze({version: source.CANGJIE_VERSION, hostVersion: source.HOST_SDK_VERSION, repos: Object.freeze(repos),
    wasi: Object.freeze({url: wasi.WASI_SYSROOT_URL, sha256: wasi.WASI_SYSROOT_SHA256, version: wasi.WASI_SYSROOT_VERSION})});
}
