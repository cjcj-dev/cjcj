#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {acquire} from './bootstrap_store.mjs';
import {verifyRuntime} from './colour_runtime.mjs';
import {prepareCppHeaders} from '../bootstrap/prepare_cpp_headers.mjs';
import {hostIdentity, prepareHostLlvm} from './host_llvm.mjs';
import {bootstrapArtifact} from './bootstrap_artifact.mjs';
import {prepareHostSdk} from './bootstrap_host_sdk.mjs';

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

const target = process.env.CJCJ_SRCBUILD_TARGET || `${process.platform}-${process.arch}`;
const platform = {'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64',
  'darwin-arm64': 'darwin_aarch64', 'darwin-x64': 'darwin_x86_64'}[target];
if (!platform) throw new Error(`BOOTSTRAP_TARGET_UNSUPPORTED: ${target}`);
for (const pin of ['host_sdk_pin.env', 'llvm_pin.env', 'runtime_pin.env',
  `ast_support/${platform}.env`, `colour-runtime/${platform}.env`, `llvm-dylib/${platform}.env`]) {
  const pinFile = new URL(`../${pin}`, import.meta.url);
  if (!fs.existsSync(pinFile)) continue;
  for (const line of fs.readFileSync(pinFile, 'utf8').split('\n')) {
    const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
    if (match && process.env[match[1]] === undefined) process.env[match[1]] = match[2];
  }
}
const inputsWork = process.env.CJCJ_BOOTSTRAP_INPUTS_WORK
  || path.join(process.env.RUNNER_TEMP || process.env.CANGJIE_BUILD_ROOT || '.', 'bootstrap-inputs');
const buildRoot = process.env.CANGJIE_BUILD_ROOT || '';
const hostSdk = await prepareHostSdk(platform, inputsWork);
const base = hostSdk.path;

// Every source cell consumes its independently pinned repaired host artifact.
const hostPin = hostIdentity();
process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT = bootstrapArtifact(
  process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, hostPin.repository, hostPin.artifact_id, inputsWork, 'HOST_LLVM');
const hostLlvm = prepareHostLlvm();

if (!process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT && !process.env.CJCJ_BOOTSTRAP_AST_SUPPORT && !firstExisting([
  path.join(buildRoot, 'lib', 'libcangjie-ast-support.a'),
  findFile(path.join(base, 'lib'), (_full, name) => name === 'libcangjie-ast-support.a'),
])) {
  process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT = path.join(bootstrapArtifact(undefined, 'cjcj-dev/cjcj',
    process.env.AST_SUPPORT_ARTIFACT_ID, inputsWork, 'AST_SUPPORT'), 'libcangjie-ast-support.a');
}

const astSupport = pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || process.env.CJCJ_BOOTSTRAP_AST_SUPPORT, [
  path.join(buildRoot, 'lib', 'libcangjie-ast-support.a'),
  findFile(path.join(base, 'lib'), (_full, name) => name === 'libcangjie-ast-support.a'),
], '', process.env.AST_SUPPORT_SHA256, 'ast-support archive SHA256');

const pinPath = process.env.CJCJ_BOOTSTRAP_INPUTS_PIN
  || new URL('../bootstrap_inputs_pin.json', import.meta.url);
const inputPin = JSON.parse(fs.readFileSync(pinPath, 'utf8'));
const colourTuple = await acquire(inputPin,
  inputsWork, {
    mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',
    reason: process.env.CJCJ_BOOTSTRAP_SOURCE_REASON || '',
    depot: process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE || '',
  });
// The pin is reviewed source, never a digest learned from this run's download.
const tupleSums = path.join(colourTuple, 'SHA256SUMS');
if (!/^[0-9a-f]{64}$/.test(process.env.LLVM_TUPLE_SUMS_SHA || '')
    || sha256File(tupleSums) !== process.env.LLVM_TUPLE_SUMS_SHA) {
  throw new Error(`colour tuple SHA256SUMS disagrees with ci/llvm_pin.env: ${colourTuple}`);
}

process.env.CJCJ_BOOTSTRAP_COLOUR_RT = bootstrapArtifact(process.env.CJCJ_BOOTSTRAP_COLOUR_RT,
  'cjcj-dev/cjcj', process.env.COLOUR_RT_ARTIFACT_ID, inputsWork, 'COLOUR_RT');
const colourRt = verifyRuntime();

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
// Select the library for the source cell, as for the independent host LLVM.
const darwin = (process.env.CJCJ_SRCBUILD_TARGET || process.platform).startsWith('darwin');
if (process.platform === 'linux' || darwin || process.env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT
    || process.env.CJCJ_BOOTSTRAP_COLOUR_DYLIB) {
  if (process.env.LLVM_DYLIB_SOURCE_SHA !== llvmSha) throw new Error('LLVM_DYLIB_SOURCE_MISMATCH');
  const dylibRoot = bootstrapArtifact(process.env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT
    || process.env.CJCJ_BOOTSTRAP_COLOUR_DYLIB, 'cjcj-dev/cjcj',
  process.env.LLVM_DYLIB_ARTIFACT_ID, inputsWork, 'LLVM_DYLIB');
  const colourLlvm = path.join(dylibRoot, darwin ? 'libLLVM.dylib' : 'libLLVM-15.so');
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
  CJCJ_BOOTSTRAP_HOST_LLVM_SO: hostLlvm.file,
  CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: hostLlvm.sha256,
  CJCJ_BOOTSTRAP_AST_SUPPORT: path.resolve(astSupport),
  CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: process.env.AST_SUPPORT_SHA256,
  CJCJ_BOOTSTRAP_COLOUR_TUPLE: path.resolve(colourTuple),
  CJCJ_BOOTSTRAP_COLOUR_RT: path.resolve(colourRt),
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA: llvmSha,
  CJCJ_BOOTSTRAP_HOST_RT: path.resolve(base),
};

const lines = Object.entries(exported).map(([k, v]) => `${k}=${v}`);
const identities = {
  host_sdk: hostSdk.sha256,
  host_llvm: hostLlvm.sha256,
  ast_support: sha256File(astSupport),
  colour_tuple: Object.fromEntries(inputPin.files.map(file => [file.path, sha256File(path.join(colourTuple, file.path))])),
  colour_runtime: sha256File(path.join(colourRt, 'manifest.json')),
  colour_llvm: colourInputs.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256,
};
console.log(`BOOTSTRAP_INPUT_IDENTITIES=${JSON.stringify(identities)}`);
if (process.env.GITHUB_ENV) {
  fs.appendFileSync(process.env.GITHUB_ENV, `${lines.join('\n')}\n`);
}
for (const line of lines) console.log(line);
if (process.argv[2] === '--shell-output') {
  const quote = value => `'${String(value).replaceAll("'", "'\\''")}'`;
  fs.writeFileSync(process.argv[3], Object.entries(exported)
    .map(([key, value]) => `export ${key}=${quote(value)}`).join('\n') + '\n');
}
