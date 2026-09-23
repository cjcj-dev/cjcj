#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {acquire} from './bootstrap_store.mjs';
import {prepareCppHeaders} from '../bootstrap/prepare_cpp_headers.mjs';

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function firstExisting(candidates) {
  return candidates.find(candidate => candidate && fs.existsSync(candidate));
}

// Both bootstrap artifacts use the #81 selection and reviewed-digest path.
// A selected artifact that is missing or corrupt must never fall back silently.
function pinnedInput(artifact, fallbacks, relativeFile, expected, label) {
  const selected = artifact || firstExisting(fallbacks);
  if (!selected) throw new Error(`${label} missing`);
  const file = relativeFile ? path.join(selected, relativeFile) : selected;
  if (!/^[0-9a-f]{64}$/.test(expected || '') || sha256File(file) !== expected) {
    throw new Error(`${label} disagrees with reviewed pin: ${selected}`);
  }
  return selected;
}

function findFile(root, predicate) {
  if (!root || !fs.existsSync(root)) return undefined;
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (predicate(full, entry.name)) return full;
    }
  }
  return undefined;
}

const hostSdk = process.env.CJCJ_SRCBUILD_HOST_SDK
  || (process.env.CJCJ_TOOLCHAIN && process.env.HOME
    ? path.join(process.env.HOME, '.cjv', 'toolchains', process.env.CJCJ_TOOLCHAIN)
    : '');
const buildRoot = process.env.CANGJIE_BUILD_ROOT || '';
const runtimeRef = process.env.RUNTIME_REF || '';

const base = firstExisting([hostSdk]);
if (!base) {
  throw new Error(`host SDK missing (CJCJ_SRCBUILD_HOST_SDK / $HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN)`);
}

const hostLlvm = firstExisting([
  process.env.CJCJ_BOOTSTRAP_HOST_LLVM_SO,
  path.join(base, 'third_party', 'llvm', 'lib', 'libLLVM-15.so'),
  findFile(path.join(base, 'third_party', 'llvm', 'lib'), (_full, name) => /^libLLVM.*\.(so|dylib)$/.test(name)),
]);
if (!hostLlvm) throw new Error(`host LLVM SO missing under ${base}`);

const astSupport = pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT, [
  process.env.CJCJ_BOOTSTRAP_AST_SUPPORT,
  path.join(buildRoot, 'lib', 'libcangjie-ast-support.a'),
  findFile(path.join(base, 'lib'), (_full, name) => name === 'libcangjie-ast-support.a'),
], '', process.env.AST_SUPPORT_SHA256, 'ast-support archive SHA256');

const pinPath = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url);
const inputPin = JSON.parse(fs.readFileSync(pinPath, 'utf8'));
const colourTuple = await acquire(inputPin,
  process.env.CJCJ_BOOTSTRAP_INPUTS_WORK || path.join(process.env.RUNNER_TEMP || buildRoot || '.', 'bootstrap-inputs'), {
    mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',
    reason: process.env.CJCJ_BOOTSTRAP_SOURCE_REASON || '',
    depot: process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE || (process.env.LLVM_SHA && process.env.CANGJIE_COMPILER_SHA
      ? path.join(process.env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot', process.env.LLVM_SHA, process.env.CANGJIE_COMPILER_SHA) : ''),
  });
// The pin is reviewed source, never a digest learned from this run's download.
const tupleSums = path.join(colourTuple, 'SHA256SUMS');
if (!/^[0-9a-f]{64}$/.test(process.env.LLVM_TUPLE_SUMS_SHA || '')
    || sha256File(tupleSums) !== process.env.LLVM_TUPLE_SUMS_SHA) {
  throw new Error(`colour tuple SHA256SUMS disagrees with ci/llvm_pin.env: ${colourTuple}`);
}

const colourRt = firstExisting([
  process.env.CJCJ_BOOTSTRAP_COLOUR_RT,
  runtimeRef ? path.join('/root/sodepot', runtimeRef) : '',
  base,
]);
if (!colourRt) throw new Error('colour-rt dir missing');

const llvmSha = process.env.LLVM_SHA || '';
if (!/^[0-9a-f]{40}$/.test(llvmSha)) throw new Error('LLVM_SHA pin missing');

const cppSrc = firstExisting([
  process.env.CJCJ_BOOTSTRAP_CPP_SRC,
  process.env.CANGJIE_CPP_SRC,
  process.env.CANGJIE_WORKSPACE
    ? path.join(process.env.CANGJIE_WORKSPACE, 'cangjie_compiler')
    : '',
]);
if (!cppSrc) throw new Error('cpp-src dir missing (CANGJIE_WORKSPACE/cangjie_compiler after fetch)');

const cjcjSha = process.env.CJCJ_BOOTSTRAP_CJCJ_SHA
  || process.env.GITHUB_SHA
  || '';
if (!/^[0-9a-f]{40}$/.test(cjcjSha)) throw new Error('cjcj sha missing (GITHUB_SHA / CJCJ_BOOTSTRAP_CJCJ_SHA)');

// This is the cjcj process library, separate from the official compiler's host
// LLVM and from the static tuple's eight payloads. An explicitly selected input
// never falls back after a missing file or identity mismatch.
const colourInputs = {};
// The pinned .so producer supports the Linux bootstrap hosts.
if (process.platform === 'linux' || process.env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT
    || process.env.CJCJ_BOOTSTRAP_COLOUR_DYLIB) {
  const dylibRoot = process.env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT
    || process.env.CJCJ_BOOTSTRAP_COLOUR_DYLIB
    || path.join(process.env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot',
      llvmSha, process.env.CANGJIE_COMPILER_SHA || '', 'dylib');
  const colourLlvm = path.join(dylibRoot, 'libLLVM-15.so');
  const dylibPin = process.env.LLVM_DYLIB_SHA256 || '';
  if (!/^[0-9a-f]{64}$/.test(dylibPin)) throw new Error('LLVM_DYLIB_PIN_MISSING');
  if (!fs.existsSync(colourLlvm)) throw new Error(`LLVM_DYLIB_MISSING: ${colourLlvm}`);
  const colourDigest = sha256File(colourLlvm);
  if (colourDigest !== dylibPin) {
    throw new Error(`LLVM_DYLIB_SHA256_MISMATCH expected=${dylibPin} actual=${colourDigest} file=${colourLlvm}`);
  }
  const dylibManifest = JSON.parse(fs.readFileSync(path.join(dylibRoot, 'manifest.json'), 'utf8'));
  if (dylibManifest.llvm_sha !== llvmSha || dylibManifest.sha256 !== dylibPin
      || JSON.stringify(dylibManifest.targets) !== JSON.stringify(['X86', 'ARM', 'AArch64'])) {
    throw new Error(`LLVM_DYLIB_MANIFEST_MISMATCH: ${dylibRoot}`);
  }
  colourInputs.CJCJ_BOOTSTRAP_COLOUR_LLVM_SO = path.resolve(colourLlvm);
  colourInputs.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256 = dylibPin;
}

// Explicit external trees remain caller-owned; default fetched sources are
// prepared here before gha_run.sh can enter stage0.
if (!process.env.CJCJ_BOOTSTRAP_CPP_SRC && !process.env.CANGJIE_CPP_SRC) {
  await prepareCppHeaders(cppSrc);
}

const exported = {
  ...colourInputs,
  CJCJ_BOOTSTRAP_BASE: path.resolve(base),
  CJCJ_BOOTSTRAP_CPP_SRC: path.resolve(cppSrc),
  CJCJ_BOOTSTRAP_CJCJ_SHA: cjcjSha,
  CJCJ_BOOTSTRAP_HOST_LLVM_SO: path.resolve(hostLlvm),
  CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: sha256File(hostLlvm),
  CJCJ_BOOTSTRAP_AST_SUPPORT: path.resolve(astSupport),
  CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: process.env.AST_SUPPORT_SHA256,
  CJCJ_BOOTSTRAP_COLOUR_TUPLE: path.resolve(colourTuple),
  CJCJ_BOOTSTRAP_COLOUR_RT: path.resolve(colourRt),
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA: llvmSha,
  CJCJ_BOOTSTRAP_HOST_RT: path.resolve(base),
};

const lines = Object.entries(exported).map(([k, v]) => `${k}=${v}`);
if (process.env.GITHUB_ENV) {
  fs.appendFileSync(process.env.GITHUB_ENV, `${lines.join('\n')}\n`);
}
for (const line of lines) console.log(line);
