// Fixed source and platform-dependency pins, parsed once for the whole production line.
import fs from 'node:fs';
import {readHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ci = path.resolve(here, '../../ci');
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

export function loadPins({sourceFile = path.join(ci, 'source_pin.env'), llvmFile = path.join(ci, 'llvm_pin.env'),
  runtimeFile = path.join(ci, 'runtime_pin.env'), wasiFile = path.join(ci, 'wasi_pin.env'),
  hostFile = path.join(ci, 'host_sdk_pin.env')} = {}) {
  const read = file => parseEnv(fs.readFileSync(file, 'utf8'), file);
  const source = read(sourceFile), runtime = read(runtimeFile), llvm = read(llvmFile), wasi = read(wasiFile);
  const known = new Set();
  const repos = {};
  for (const name of REPOSITORIES) {
    const fromLlvm = name === 'LLVM' || name === 'FLATBUFFERS';
    const values = fromLlvm ? llvm : name === 'RUNTIME' ? runtime : source;
    const ref = name + (fromLlvm ? '_SHA' : '_REF'), url = name + (fromLlvm ? '_URL' : '_SRC_URL');
    if (values === source) for (const key of [ref, url, ref + '_AUTHORITY', ref + '_MAINLINE']) known.add(key);
    if (!SHA.test(values[ref] ?? '')) throw new Error('PIN_REF ' + ref + ' must be a full 40-hex commit');
    if (!/^https:\/\/[^\s]+\.git$/.test(values[url] ?? '')) throw new Error('PIN_URL ' + url);
    repos[name === 'JAVA_INTEROP' ? 'javaInterop' : name.toLowerCase()] = Object.freeze({url: values[url], commit: values[ref]});
  }
  for (const key of Object.keys(source)) if (!known.has(key)) throw new Error(`PIN_UNKNOWN ${key}`);
  const version = runtime.RUNTIME_VERSION, hostVersion = readHostToolchainPin(undefined, hostFile).replace(/^nightly-/, '');
  if (!VERSION.test(version ?? '')) throw new Error('PIN_VERSION RUNTIME_VERSION');
  if (!VERSION.test(hostVersion)) throw new Error('PIN_VERSION CJCJ_TOOLCHAIN');
  if (!HEX64.test(wasi.WASI_SYSROOT_SHA256 ?? '')) throw new Error('PIN_WASI_SHA256');
  if (!/^https:\/\/\S+\.tar\.gz$/.test(wasi.WASI_SYSROOT_URL ?? '')) throw new Error('PIN_WASI_URL');
  return Object.freeze({version, hostVersion, repos: Object.freeze(repos),
    wasi: Object.freeze({url: wasi.WASI_SYSROOT_URL, sha256: wasi.WASI_SYSROOT_SHA256, version: wasi.WASI_SYSROOT_VERSION})});
}
