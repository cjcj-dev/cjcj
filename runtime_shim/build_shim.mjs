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
const cpp = norm(process.env.CANGJIE_CPP_SRC || '');
const llvmSrcInc = `${cpp}/third_party/llvm-project/llvm/include`;
const llvmGenInc = `${cpp}/build/build/third_party/llvm/include`;
const flatbuffersInc = `${cpp}/build/build/include`;
const schemaGenInc = `${cpp}/build/build/schema`;
const schemaHeader = `${schemaGenInc}/flatbuffers/CjoFormat_generated.h`;
let cxx = process.env.CXX || 'clang++';
const cc = process.env.CC || 'cc';
// The same launcher cmake-driven builds use (sccache on GitHub Actions), so the
// two shim objects are cached alongside the runtime. Empty when unset.
const ccLauncher = process.env.CMAKE_C_COMPILER_LAUNCHER ? [process.env.CMAKE_C_COMPILER_LAUNCHER] : [];
const cxxLauncher = process.env.CMAKE_CXX_COMPILER_LAUNCHER ? [process.env.CMAKE_CXX_COMPILER_LAUNCHER] : [];
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

await $`${ccLauncher} ${cc} -std=c11 -O2 -fPIC -D_POSIX_C_SOURCE=200809L ${commitDefine} -c ${here}/cjc_runtime_config.c -o ${here}/cjc_runtime_config.o`;
console.log(`CJCJ_COMMIT=${cjcjCommit}`);

// The caller validates an explicitly selected installed object. Without one,
// always compile the current translation unit against the selected header tree.
// A local .o can belong to a previous tuple even when it has a newer mtime;
// content caching belongs to the compiler launcher, not to this selection.
if (sourceBuiltObject) {
  if (!(await isFile(sourceBuiltObject))) {
    console.error(`ERR: source-built shim artifact missing: ${sourceBuiltObject}`);
    process.exit(1);
  }
  if (path.resolve(sourceBuiltObject) !== path.resolve(shimObject)) {
    await fs.copyFile(sourceBuiltObject, shimObject);
  }
  console.log(`used source-built shim artifact: ${sourceBuiltObject}`);
  console.log(`selected: ${shimObject}`);
} else {
  if (!cpp) {
    throw new Error('ERR: CANGJIE_CPP_SRC is required to compile the shim from selected headers');
  }
  for (const includeRoot of [llvmSrcInc, llvmGenInc, flatbuffersInc]) {
    if (!(await isDirectory(includeRoot))) {
      throw new Error(`ERR: selected shim header directory missing: ${includeRoot}`);
    }
  }
  for (const header of [schemaHeader, `${llvmSrcInc}/llvm/IR/Module.h`,
    `${llvmGenInc}/llvm/Config/llvm-config.h`]) {
    if (!(await isFile(header))) {
      throw new Error(`ERR: selected shim header missing: ${header}`);
    }
  }
  // Respect an explicitly selected compiler. A default compiler may use its
  // versioned executable name; LLVM headers never fall back to llvm-config.
  if (!process.env.CXX && !(await commandExists(cxx)) && await commandExists('clang++-15')) {
    cxx = 'clang++-15';
  }
  const compileEnv = {...process.env};
  for (const key of ['CPATH', 'CPLUS_INCLUDE_PATH', 'C_INCLUDE_PATH', 'OBJC_INCLUDE_PATH']) {
    compileEnv[key] = '';
  }
  await $({env: compileEnv})`${cxxLauncher} ${cxx} -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions -c ${here}/cjselfhost_llvmshim.cpp -o ${shimObject} ${`-I${llvmSrcInc}`} ${`-I${llvmGenInc}`} ${`-I${flatbuffersInc}`} ${`-I${schemaGenInc}`}`;
  console.log(`built: ${shimObject}`);
}

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
