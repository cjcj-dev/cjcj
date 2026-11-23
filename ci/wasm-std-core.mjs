#!/usr/bin/env zx
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {SYSROOT_DIR} from './wasi-toolchain.mjs';

const target = '--target=wasm32-wasi';
export const WASM_LOCAL_MODE_CJC_ARGS = Object.freeze([
  '--experimental', '--enable-local-mode', '--cfg', 'local_mode_api=off',
]);
const cSources = dir => fs.readdirSync(dir).filter(name => name.endsWith('.c')).sort();

export function wasmStdInputs({stdlibSource, boundscheckSource, clang, llvmAr}) {
  for (const [flag, value] of Object.entries({'--stdlib-source': stdlibSource,
    '--boundscheck-source': boundscheckSource, '--clang': clang, '--llvm-ar': llvmAr})) {
    if (!value) throw new Error(`source std production requires ${flag}`);
  }
  const core = path.resolve(stdlibSource, 'libs/std/core');
  const native = path.join(core, 'native');
  const bounds = path.resolve(boundscheckSource);
  clang = path.resolve(clang);
  llvmAr = path.resolve(llvmAr);
  for (const tool of [clang, llvmAr]) {
    if (!fs.statSync(tool).isFile()) throw new Error(`expected executable file: ${tool}`);
    fs.accessSync(tool, fs.constants.X_OK);
  }
  const nativeSources = cSources(native);
  const boundsSources = cSources(path.join(bounds, 'src'));
  if (!nativeSources.includes('typetemplate.c') || !boundsSources.length || !fs.statSync(path.join(bounds, 'include')).isDirectory()) {
    throw new Error('expected std.core native sources and boundscheck src/*.c and include/');
  }
  // Native CMake renames the type info/template exports on the object. Wasm objcopy cannot
  // rename these symbols, so use the same recipe on Clang's IR before it becomes an object.
  const cmake = fs.readFileSync(path.join(native, 'CMakeLists.txt'), 'utf8');
  const renames = new Map(Array.from(cmake.matchAll(/--redefine-sym\s+\$\{SYM_PREFIX\}(\w+)=\$\{SYM_PREFIX\}([\w.]+)/g),
    ([, from, to]) => [from, to]));
  if (!renames.size) throw new Error(`missing typetemplate symbol renames in ${native}/CMakeLists.txt`);
  return {stdlibSource: path.resolve(stdlibSource), core, native, bounds, clang, llvmAr, nativeSources, boundsSources, renames};
}

export function buildWasmStdCore(sdk, work, inputs, {cjcArgs = []} = {}) {
  const {core, native, bounds, clang, llvmAr, nativeSources, boundsSources, renames} = inputs;
  fs.mkdirSync(work);
  const env = {...process.env, CANGJIE_HOME: sdk};
  function run(cmd, args) {
    const {status, signal, error} = spawnSync(cmd, args, {cwd: work, env, stdio: ['ignore', 2, 2]});
    console.error(JSON.stringify({cmd, args, cwd: work, status, signal, error: error?.message}));
    if (error) throw error;
    if (status !== 0) throw new Error(`${cmd} failed (${signal ?? `exit ${status}`})`);
  }

  const output = path.join(work, 'std.core');
  run(path.join(sdk, 'bin', process.platform === 'win32' ? 'cjc.exe' : 'cjc'), [target, ...WASM_LOCAL_MODE_CJC_ARGS, ...cjcArgs, '--no-prelude', '--no-sub-pkg', '-p', core, '--output-type=staticlib',
    '--disable-reflection', `--output=${output}`, '-V']);
  const module = output + '.cjo';
  if (!fs.statSync(module).size || !fs.statSync(output).size) throw new Error('cjc did not produce both std.core outputs');

  const wasi = [target, `--sysroot=${path.join(sdk, SYSROOT_DIR)}`, '-O2'];
  const irFile = path.join(work, 'typetemplate.ll');
  run(clang, [...wasi, `-I${path.join(sdk, 'include')}`, `-I${native}`, '-S', '-emit-llvm',
    path.join(native, 'typetemplate.c'), '-o', irFile]);
  const ir = fs.readFileSync(irFile, 'utf8');
  const seen = new Set();
  fs.writeFileSync(irFile, ir.replace(/@([\w.$-]+)/g, (symbol, name) => {
    if (!renames.has(name)) return symbol;
    seen.add(name);
    return `@"${renames.get(name)}"`;
  }));
  const missing = [...renames.keys()].filter(name => !seen.has(name));
  if (missing.length) throw new Error(`typetemplate IR lacks symbols from native rename recipe: ${missing.join(', ')}`);
  run(clang, [target, '-O2', '-c', irFile, '-o', 'typetemplate.o']);
  const objects = ['typetemplate.o'];
  const boundsInclude = `-I${path.join(bounds, 'include')}`;
  for (const name of nativeSources.filter(name => name !== 'typetemplate.c')) {
    const obj = path.basename(name, '.c') + '.o';
    run(clang, [...wasi, `-I${native}`, boundsInclude, '-c', path.join(native, name), '-o', obj]);
    objects.push(obj);
  }
  for (const name of boundsSources) {
    const obj = 'bc_' + path.basename(name, '.c') + '.o';
    run(clang, [...wasi, boundsInclude, '-c', path.join(bounds, 'src', name), '-o', obj]);
    objects.push(obj);
  }
  const archive = path.join(work, 'libcangjie-std-core.a');
  fs.renameSync(output, archive);
  // Keep the existing std.core archive member order, including SIMD_support.o.
  // Fold ASCII case explicitly so the build host's collation cannot change it.
  const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  objects.sort((a, b) => compare(a.toLowerCase(), b.toLowerCase()) || compare(a, b));
  run(llvmAr, ['rs', archive, ...objects]);
  return {archive, module};
}
