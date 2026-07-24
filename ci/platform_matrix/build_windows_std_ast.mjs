#!/usr/bin/env zx
// Rebuild libcangjie-std-ast.dll for Windows as the official library plus the
// fork's host-dispatch entry point.
//
// PE binds the CJ_* macro context callbacks inside libcangjie-std-ast at
// static link time, so the selfhost compiler cannot override them the way ELF
// symbol interposition does on Linux. The fork's ast_api.cpp forwards those
// callbacks through a table registered via CJ_MacroCall_RegisterHostCallbacks.
// Everything else in the DLL is consumed as-is from the official toolchain:
// the Cangjie half (ast.o out of libcangjie-std-ast.a) and the C++ frontend
// support archive (libcangjie-ast-support.a). Only ast_api.cpp is recompiled,
// with the same flags the stdlib build uses. The result is verified to carry
// the official export surface plus exactly one extra symbol and a bitwise
// identical import table before it is installed into the runtime artifact.

import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';
const log = (message) => console.log(`[std-ast] ${message}`);

const env = (name, fallback = '') => process.env[name] || fallback;
const runtimeSource = path.resolve(env('RUNTIME_SOURCE', 'runtime-source'));
const toolchain = path.resolve(env('RUNTIME_TOOLCHAIN'));
const cangjieHome = path.resolve(env('CANGJIE_HOME'));
const installRoot = path.resolve(env('RUNTIME_INSTALL', '.platform-ci/runtime-install/windows_release_x86_64'));
const flatcDir = path.resolve(env('FLATC_DIR', '.windows-stdast-buildtools/flatc'));
const work = path.resolve(env('STDAST_WORKDIR', '.windows-stdast-buildtools/stdast-work'));

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}
async function isDirectory(target) {
  try { return (await fs.stat(target)).isDirectory(); } catch { return false; }
}
async function requireFile(target, hint) {
  if (!(await isFile(target))) { console.error(`[std-ast] missing ${hint}: ${target}`); process.exit(2); }
  return target;
}

const stdlibNative = path.join(runtimeSource, 'stdlib', 'libs', 'std', 'ast', 'native');
const astApiCpp = await requireFile(path.join(stdlibNative, 'ast_api.cpp'), 'fork ast_api.cpp');
const schema = await requireFile(path.join(runtimeSource, 'stdlib', 'schema', 'NodeFormat.fbs'), 'flatbuffers schema');
// stdlib/third_party/flatbuffers is a build-time download (gitignored), so a CI
// checkout does not carry it; provision it with the stdlib build's own pin
// (stdlib/third_party/cmake/Flatbuffer.cmake).
const FLATBUFFERS_REPOSITORY = 'https://gitcode.com/openharmony/third_party_flatbuffers.git';
const FLATBUFFERS_PIN = 'c3e4d69cbd5950e43f775ba76eadb30750d6e0b7';
const targetLib = path.join(cangjieHome, 'lib', 'windows_x86_64_cjnative');
const targetRuntime = path.join(cangjieHome, 'runtime', 'lib', 'windows_x86_64_cjnative');
const clangxx = await requireFile(path.join(toolchain, 'bin', 'x86_64-w64-mingw32-clang++'), 'mingw clang++');
const gccDriver = await requireFile(path.join(toolchain, 'bin', 'x86_64-w64-mingw32-gcc'), 'mingw gcc driver');
const llvmAr = await requireFile(path.join(toolchain, 'bin', 'llvm-ar'), 'llvm-ar');
const llvmReadobj = await requireFile(path.join(toolchain, 'bin', 'llvm-readobj'), 'llvm-readobj');
await requireFile(path.join(targetLib, 'libcangjie-std-ast.a'), 'official Cangjie half archive');
await requireFile(path.join(targetLib, 'libcangjie-ast-support.a'), 'official ast-support archive');
for (const object of ['section.o', 'cjstart.o']) await requireFile(path.join(targetLib, object), 'runtime start object');
const officialDll = await requireFile(path.join(targetRuntime, 'libcangjie-std-ast.dll'), 'official std-ast DLL');
if (!(await isDirectory(path.join(cangjieHome, 'include', 'cangjie')))) {
  console.error(`[std-ast] missing compiler headers under ${cangjieHome}/include`); process.exit(2);
}

await fs.mkdir(work, {recursive: true});

let flatbuffersSrc = path.join(runtimeSource, 'stdlib', 'third_party', 'flatbuffers');
if (!(await isFile(path.join(flatbuffersSrc, 'CMakeLists.txt')))) {
  flatbuffersSrc = path.join(work, 'flatbuffers-src');
  if (!(await isFile(path.join(flatbuffersSrc, 'CMakeLists.txt')))) {
    log(`fetching flatbuffers ${FLATBUFFERS_PIN}`);
    await fs.rm(flatbuffersSrc, {recursive: true, force: true});
    await $`git clone --filter=blob:none ${FLATBUFFERS_REPOSITORY} ${flatbuffersSrc}`;
    await $({cwd: flatbuffersSrc})`git checkout --detach ${FLATBUFFERS_PIN}`;
  }
}

// 1. flatc for the generated serialization header (host tool, cached across runs).
let flatc = path.join(flatcDir, 'flatc');
if (!(await isFile(flatc))) {
  log('building flatc from vendored flatbuffers');
  const flatcBuild = path.join(work, 'flatbuffers-build');
  await $`cmake -S ${flatbuffersSrc} -B ${flatcBuild} -DCMAKE_BUILD_TYPE=Release -DFLATBUFFERS_BUILD_TESTS=OFF -DFLATBUFFERS_INSTALL=OFF`;
  await $`cmake --build ${flatcBuild} --target flatc -j`;
  await fs.mkdir(flatcDir, {recursive: true});
  await fs.copyFile(path.join(flatcBuild, 'flatc'), flatc);
  await fs.chmod(flatc, 0o755);
}

const generatedInclude = path.join(work, 'include');
await fs.mkdir(path.join(generatedInclude, 'flatbuffers'), {recursive: true});
await $`${flatc} --no-warnings -c -o ${path.join(generatedInclude, 'flatbuffers')} ${schema}`;

// 2. Compile the fork ast_api.cpp with the stdlib build's flag set
// (stdlib libs/std/ast/native + windows toolchain flags).
const astApiObj = path.join(work, 'ast_api.cpp.obj');
await $`${clangxx} -c ${astApiCpp} -o ${astApiObj} -DCANGJIE_CODEGEN_CJNATIVE_BACKEND -DNDEBUG -DRELEASE -D__windows__ -w -Wdate-time -Wno-int-conversion -fno-omit-frame-pointer -pipe -fno-common -fno-strict-aliasing -m64 -Wa,-mbig-obj -fstack-protector-all -D_FORTIFY_SOURCE=2 -O2 -fPIC -std=c++17 -I${path.join(cangjieHome, 'include')} -I${generatedInclude} -I${path.join(flatbuffersSrc, 'include')}`;

// 3. The official Cangjie half: single-member archive holding ast.o.
await $({cwd: work})`${llvmAr} x ${path.join(targetLib, 'libcangjie-std-ast.a')} ast.o`;
const astO = await requireFile(path.join(work, 'ast.o'), 'extracted ast.o');

// 4. Link with the stdlib build's DLL recipe.
const rebuilt = path.join(work, 'libcangjie-std-ast.dll');
await $`${gccDriver} ${astO} ${astApiObj} -L${targetLib} -lcangjie-ast-support -lstdc++ -lpthread -L${targetRuntime} -l:libcangjie-std-core.dll -l:libcangjie-std-collection.dll -l:libcangjie-std-sort.dll -l:libcangjie-std-math.dll -Wl,--no-insert-timestamp -Wl,--export-all-symbols ${path.join(targetLib, 'section.o')} ${path.join(targetLib, 'cjstart.o')} -l:libcangjie-runtime.dll -static -fstack-protector-all -lclang_rt-builtins -l:libboundscheck.dll -lm -Wl,--no-undefined -s -shared --target=x86_64-w64-mingw32 -B${path.join(toolchain, 'bin')} --sysroot=${toolchain} -o ${rebuilt}`;

// 5. Fail-closed verification against the official DLL: export surface must be
// official + exactly CJ_MacroCall_RegisterHostCallbacks, import table identical.
async function readobj(kind, dll) {
  const result = await $({stdio: 'pipe'})`${llvmReadobj} ${kind} ${dll}`;
  return result.stdout.split('\n');
}
async function exportNames(dll) {
  return (await readobj('--coff-exports', dll))
    .map((line) => line.match(/^\s*Name: (\S+)\s*$/)?.[1])
    .filter(Boolean).sort();
}
async function importSymbols(dll) {
  const lines = await readobj('--coff-imports', dll);
  const dlls = lines.map((line) => line.match(/^\s*Name: (\S+)\s*$/)?.[1]).filter(Boolean).sort();
  const symbols = lines.map((line) => line.match(/^\s*Symbol: (\S+)/)?.[1]).filter(Boolean).sort();
  return {dlls, symbols};
}
const HOST_DISPATCH_EXPORT = 'CJ_MacroCall_RegisterHostCallbacks';
const oursExports = await exportNames(rebuilt);
const officialExports = await exportNames(officialDll);
const officialSet = new Set(officialExports);
const oursSet = new Set(oursExports);
const added = oursExports.filter((name) => !officialSet.has(name));
const removed = officialExports.filter((name) => !oursSet.has(name));
const oursImports = await importSymbols(rebuilt);
const officialImports = await importSymbols(officialDll);
const importsIdentical = oursImports.dlls.join(',') === officialImports.dlls.join(',')
  && oursImports.symbols.join('\n') === officialImports.symbols.join('\n');
console.log(`WINDOWS_STDAST_GUARD exports_official=${officialExports.length} exports_ours=${oursExports.length} added=${added.join(',') || 'NONE'} removed=${removed.join(',') || 'NONE'} import_dlls=${oursImports.dlls.join(',')} import_symbols=${oursImports.symbols.length} imports_identical=${importsIdentical}`);
if (added.length !== 1 || added[0] !== HOST_DISPATCH_EXPORT || removed.length !== 0 || !importsIdentical) {
  console.error('[std-ast] rebuilt DLL diverges from the official surface; refusing to install');
  process.exit(3);
}

// 6. Install into the runtime artifact consumed by package_sdk.mjs, which
// copies runtime/lib/windows_x86_64_cjnative over the staged official SDK.
const destination = path.join(installRoot, 'runtime', 'lib', 'windows_x86_64_cjnative');
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(rebuilt, path.join(destination, 'libcangjie-std-ast.dll'));
const digest = (await $({stdio: 'pipe'})`sha256sum ${path.join(destination, 'libcangjie-std-ast.dll')}`).stdout.trim();
log(`installed host-dispatch std-ast DLL: ${digest}`);
