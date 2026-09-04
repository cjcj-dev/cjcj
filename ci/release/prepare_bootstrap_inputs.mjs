#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function firstExisting(candidates) {
  return candidates.find(candidate => candidate && fs.existsSync(candidate));
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

const astSupport = firstExisting([
  process.env.CJCJ_BOOTSTRAP_AST_SUPPORT,
  path.join(buildRoot, 'lib', 'libcangjie-ast-support.a'),
  findFile(path.join(base, 'lib'), (_full, name) => name === 'libcangjie-ast-support.a'),
]);
if (!astSupport) throw new Error('ast-support archive missing (static-libs or host SDK lib)');

const colourTuple = firstExisting([
  process.env.CJCJ_BOOTSTRAP_COLOUR_TUPLE,
  fixedLlvm,
]);
if (!colourTuple) throw new Error('colour-tuple dir missing (fixed-llvm artifact or CJCJ_BOOTSTRAP_COLOUR_TUPLE)');

const colourRt = firstExisting([
  process.env.CJCJ_BOOTSTRAP_COLOUR_RT,
  runtimeRef ? path.join('/root/sodepot', runtimeRef) : '',
  base,
]);
if (!colourRt) throw new Error('colour-rt dir missing');

const llvmSha = process.env.LLVM_SHA || '';
if (!/^[0-9a-f]{40}$/.test(llvmSha)) throw new Error('LLVM_SHA pin missing');

const exported = {
  CJCJ_BOOTSTRAP_BASE: path.resolve(base),
  CJCJ_BOOTSTRAP_HOST_LLVM_SO: path.resolve(hostLlvm),
  CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: sha256File(hostLlvm),
  CJCJ_BOOTSTRAP_AST_SUPPORT: path.resolve(astSupport),
  CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: sha256File(astSupport),
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
