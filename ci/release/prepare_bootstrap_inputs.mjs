#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
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
const fixedLlvm = process.env.CJCJ_FIXED_LLVM_DIR || '';
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

const colourTuple = pinnedInput(process.env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT, [
  process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE,
  process.env.LLVM_SHA && process.env.CANGJIE_COMPILER_SHA
    ? path.join(process.env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot',
      process.env.LLVM_SHA, process.env.CANGJIE_COMPILER_SHA)
    : '',
  fixedLlvm,
], 'SHA256SUMS', process.env.LLVM_TUPLE_SUMS_SHA, 'colour tuple SHA256SUMS');

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

// Explicit external trees remain caller-owned; default fetched sources are
// prepared here before gha_run.sh can enter stage0.
if (!process.env.CJCJ_BOOTSTRAP_CPP_SRC && !process.env.CANGJIE_CPP_SRC) {
  await prepareCppHeaders(cppSrc);
}

const exported = {
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
