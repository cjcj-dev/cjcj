#!/usr/bin/env zx
// Compile the self-host LLVM FFI C-shim into a relocatable object linked into cjc.
// LLVM headers come from the C++ compiler source tree (LLVM 15.0.4, matching libLLVM-15.so).

import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';

// Forward slashes everywhere: zx C-quotes values containing backslashes with
// $'...', so a raw Windows path like D:\a\... reaches cc with \a as BEL.
const norm = (p) => p.replaceAll('\\', '/');
const here = norm(import.meta.dirname);
const cpp = norm(process.env.CANGJIE_CPP_SRC || '/root/cj_build/cangjie_compiler');
const llvmSrcInc = `${cpp}/third_party/llvm-project/llvm/include`;
const llvmGenInc = `${cpp}/build/build/third_party/llvm/include`;
const flatbuffersInc = `${cpp}/build/build/include`;
const schemaGenInc = `${cpp}/build/build/schema`;
let cxx = process.env.CXX || 'clang++';
const cc = process.env.CC || 'cc';
const sourceBuiltObject = norm(process.env.CJCJ_LLVM_SHIM_O || '');
const shimObject = norm(path.join(here, 'cjselfhost_llvmshim.o'));
const repo = norm(path.resolve(here, '..'));

let cjcjCommit = (process.env.CJCJ_COMMIT || '').trim();
if (!cjcjCommit) {
  const revision = await $({nothrow: true, quiet: true, stdio: 'pipe'})`git -C ${repo} rev-parse HEAD`;
  if (revision.exitCode === 0) cjcjCommit = revision.stdout.trim();
}
if (!cjcjCommit) cjcjCommit = 'unknown';
const status = await $({nothrow: true, quiet: true, stdio: 'pipe'})`git -C ${repo} status --porcelain`;
if (status.exitCode === 0 && status.stdout.trim() && !cjcjCommit.endsWith('-dirty')) {
  cjcjCommit += '-dirty';
}
if (!/^[0-9A-Za-z._-]+$/.test(cjcjCommit)) {
  console.error(`ERR: invalid CJCJ_COMMIT value: ${JSON.stringify(cjcjCommit)}`);
  process.exit(1);
}
const commitDefine = `-DCJCJ_COMMIT="${cjcjCommit}"`;

async function commandExists(command) {
  return (await $({nothrow: true, stdio: 'pipe'})`command -v ${command}`).exitCode === 0;
}

async function isDirectory(target) {
  try { return (await fs.stat(target)).isDirectory(); } catch { return false; }
}

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}

async function mtimeMs(target) {
  try { return (await fs.stat(target)).mtimeMs; } catch { return null; }
}

// An object older than the source it was compiled from links silently: the
// symbols still resolve, so nothing fails and the build looks clean. Treat a
// stale object as absent so it falls through to the rebuild paths below, and
// let the final else report it if none of them can produce one.
async function isUsableObject(object, source) {
  if (!(await isFile(object))) return false;
  const objectAge = await mtimeMs(object);
  const sourceAge = await mtimeMs(source);
  if (objectAge === null || sourceAge === null) return true;
  if (objectAge >= sourceAge) return true;
  console.error(`STALE_SHIM_OBJECT object=${object} is older than source=${source}`);
  console.error(`  object mtime ${new Date(objectAge).toISOString()}`);
  console.error(`  source mtime ${new Date(sourceAge).toISOString()}`);
  return false;
}

if (!(await commandExists(cxx)) && await commandExists('clang++-15')) cxx = 'clang++-15';

await $`${cc} -std=c11 -O2 -fPIC -D_POSIX_C_SOURCE=200809L ${commitDefine} -c ${here}/cjc_runtime_config.c -o ${here}/cjc_runtime_config.o`;
console.log(`CJCJ_COMMIT=${cjcjCommit}`);

// Resolve in the original priority order: existing object, CI source-built
// artifact, then a local source build against a complete patched C++ tree.
let reused = false;
if (await isUsableObject(shimObject, `${here}/cjselfhost_llvmshim.cpp`)) {
  console.log('reusing existing cjselfhost_llvmshim.o');
  reused = true;
} else if (sourceBuiltObject) {
  if (!(await isFile(sourceBuiltObject))) {
    console.error(`ERR: source-built shim artifact missing: ${sourceBuiltObject}`);
    process.exit(1);
  }
  await $`cp ${sourceBuiltObject} ${shimObject}`;
  console.log(`used source-built shim artifact: ${sourceBuiltObject}`);
} else if (await isDirectory(flatbuffersInc) && await isDirectory(`${schemaGenInc}/flatbuffers`)) {
  let llvmIncludeArgs;
  if (await isDirectory(llvmSrcInc) && await isDirectory(llvmGenInc)) {
    llvmIncludeArgs = [`-I${llvmSrcInc}`, `-I${llvmGenInc}`];
  } else if (await commandExists('llvm-config-15')) {
    const includedir = (await $({stdio: 'pipe'})`llvm-config-15 --includedir`).stdout.trim();
    llvmIncludeArgs = [`-I${includedir}`];
  } else {
    console.error('ERR: LLVM 15 headers not found (needed only to compile the shim from source)');
    process.exit(1);
  }
  await $`${cxx} -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions -c ${here}/cjselfhost_llvmshim.cpp -o ${shimObject} ${llvmIncludeArgs} ${`-I${flatbuffersInc}`} ${`-I${schemaGenInc}`}`;
} else {
  console.error('ERR: cannot obtain cjselfhost_llvmshim.o — none of: (1) a pre-existing local .o,');
  console.error('     (2) CJCJ_LLVM_SHIM_O from the source-build artifact, (3) a complete patched');
  console.error('     LLVM/Cangjie C++ build tree for a local source compile is available.');
  process.exit(1);
}

// Say which of the two happened. The previous message said "built:" on the
// reuse path too, so a log showing a fresh build and a log showing a month-old
// object read the same.
console.log(`${reused ? 'reused' : 'built'}: ${shimObject}`);
console.log(`built: ${here}/cjc_runtime_config.o`);
await $({nothrow: true})`set -o pipefail; nm -C ${shimObject} | grep -cE ' T (LLVMGlobalObjectAddStringAttribute|LLVMSelfhost)' | sed 's/^/exported LLVMSelfhost* symbols: /'`;

// Macro runtime layout. The compiler resolves its runtime relative to its binary,
// so the build-tree binary needs a sibling runtime symlink. Installed SDKs already
// have that layout and need no special handling.
if (process.env.CANGJIE_HOME && await isDirectory(`${process.env.CANGJIE_HOME}/runtime`)) {
  await fs.mkdir(`${repo}/target/release`, {recursive: true});
  await $`ln -sfn ${process.env.CANGJIE_HOME}/runtime ${repo}/target/release/runtime`;
  console.log(`linked runtime layout: ${repo}/target/release/runtime -> ${process.env.CANGJIE_HOME}/runtime`);
}
