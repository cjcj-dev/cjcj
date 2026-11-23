#!/usr/bin/env zx
// Rebuild libcangjie-std-ast.dll for Windows from one compiler generation.
//
// PE binds the CJ_* macro context callbacks inside libcangjie-std-ast at
// static link time, so the selfhost compiler cannot override them the way ELF
// symbol interposition does on Linux. The fork's ast_api.cpp forwards those
// callbacks through a table registered via CJ_MacroCall_RegisterHostCallbacks.
// The Cangjie object, schema, public headers, generated header and
// libcangjie-ast-support.a must come from the same compiler pin. A swapped
// file is rejected before compile. The DLL is then checked for the official
// export surface plus exactly one extra symbol and a bitwise identical import
// table before it is installed into the runtime artifact.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';
const log = (message) => console.log(`[std-ast] ${message}`);

const env = (name, fallback = '') => process.env[name] || fallback;
const required = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`[std-ast] missing ${name}`);
    process.exit(2);
  }
  return value;
};

const runtimeSource = path.resolve(env('RUNTIME_SOURCE', 'runtime-source'));
const toolchain = path.resolve(required('RUNTIME_TOOLCHAIN'));
const cangjieHome = path.resolve(required('CANGJIE_HOME'));
const compilerSource = path.resolve(required('COMPILER_SOURCE'));
const artifact = path.resolve(required('AST_SUPPORT_ARTIFACT'));
const installRoot = path.resolve(env('RUNTIME_INSTALL', '.platform-ci/runtime-install/windows_release_x86_64'));
const work = path.resolve(env('STDAST_WORKDIR', '.windows-stdast-buildtools/stdast-work'));
const astObject = path.resolve(required('STDLIB_AST_OBJECT'));
const astProvenance = path.resolve(required('STDLIB_AST_PROVENANCE'));

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
async function requireDir(target, hint) {
  if (!(await isDirectory(target))) { console.error(`[std-ast] missing ${hint}: ${target}`); process.exit(2); }
  return target;
}
async function fileDigest(target) {
  return crypto.createHash('sha256').update(await fs.readFile(target)).digest('hex');
}
async function treeDigest(dir) {
  const files = [];
  async function walk(current) {
    const entries = await fs.readdir(current, {withFileTypes: true});
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const child = path.join(current, entry.name);
      if (entry.isDirectory()) await walk(child);
      else if (entry.isFile()) files.push(child);
    }
  }
  await walk(dir);
  const hash = crypto.createHash('sha256');
  for (const file of files) {
    hash.update(path.relative(dir, file).split(path.sep).join('/'));
    hash.update('\0');
    hash.update(await fs.readFile(file));
    hash.update('\0');
  }
  return hash.digest('hex');
}
function reject(kind, code) {
  console.log(`WINDOWS_STDAST_GENERATION_REJECT kind=${kind}`);
  process.exit(code);
}
function pass(kind) {
  console.log(`WINDOWS_STDAST_GENERATION_PASS kind=${kind}`);
}
async function assertBytes(kind, code, consumed, expected) {
  if (await fileDigest(consumed) !== await fileDigest(expected)) reject(kind, code);
  pass(kind);
}

const stdlibNative = path.join(runtimeSource, 'stdlib', 'libs', 'std', 'ast', 'native');
const astApiCpp = await requireFile(path.join(stdlibNative, 'ast_api.cpp'), 'fork ast_api.cpp');
const targetLib = path.join(cangjieHome, 'lib', 'windows_x86_64_cjnative');
const targetRuntime = path.join(cangjieHome, 'runtime', 'lib', 'windows_x86_64_cjnative');
const runtimeLib = path.join(installRoot, 'lib', 'windows_x86_64_cjnative');
const runtimeDllDir = path.join(installRoot, 'runtime', 'lib', 'windows_x86_64_cjnative');
const clangxx = await requireFile(path.join(toolchain, 'bin', 'x86_64-w64-mingw32-clang++'), 'mingw clang++');
const gccDriver = await requireFile(path.join(toolchain, 'bin', 'x86_64-w64-mingw32-gcc'), 'mingw gcc driver');
const llvmReadobj = await requireFile(path.join(toolchain, 'bin', 'llvm-readobj'), 'llvm-readobj');
const schema = await requireFile(path.join(cangjieHome, 'schema', 'StdAstFormat.fbs'), 'installed schema');
const expectedSchema = await requireFile(path.join(compilerSource, 'schema', 'StdAstFormat.fbs'), 'compiler schema');
const generatedHeader = await requireFile(
  path.join(cangjieHome, 'include', 'flatbuffers', 'StdAstFormat_generated.h'),
  'installed generated header');
const expectedHeader = await requireFile(
  path.join(artifact, 'include', 'flatbuffers', 'StdAstFormat_generated.h'),
  'artifact generated header');
const publicHeaders = await requireDir(path.join(cangjieHome, 'include', 'cangjie'), 'installed public headers');
const expectedPublicHeaders = await requireDir(path.join(artifact, 'include', 'cangjie'), 'artifact public headers');
const archive = await requireFile(path.join(targetLib, 'libcangjie-ast-support.a'), 'installed ast-support archive');
const expectedArchive = await requireFile(path.join(artifact, 'libcangjie-ast-support.a'), 'artifact ast-support archive');
await requireFile(astObject, 'stdlib ast object');
await requireFile(astProvenance, 'stdlib ast provenance');
await requireDir(path.join(cangjieHome, 'third_party', 'flatbuffers', 'include'), 'flatbuffers headers');
for (const object of ['section.o', 'cjstart.o']) await requireFile(path.join(runtimeLib, object), 'runtime start object');
await requireFile(path.join(runtimeDllDir, 'libcangjie-runtime.dll'), 'runtime DLL');
for (const dll of ['libcangjie-std-core.dll', 'libcangjie-std-collection.dll', 'libcangjie-std-sort.dll', 'libcangjie-std-math.dll', 'libboundscheck.dll']) {
  await requireFile(path.join(targetRuntime, dll), 'stdlib DLL');
}
const officialDll = await requireFile(path.join(targetRuntime, 'libcangjie-std-ast.dll'), 'official std-ast DLL');

await assertBytes('schema', 4, schema, expectedSchema);
await assertBytes('header', 5, generatedHeader, expectedHeader);
if (await treeDigest(publicHeaders) !== await treeDigest(expectedPublicHeaders)) reject('public_headers', 6);
pass('public_headers');
await assertBytes('archive', 7, archive, expectedArchive);
const officialLibPrefix = path.join(cangjieHome, 'lib') + path.sep;
if (path.resolve(astObject).startsWith(officialLibPrefix)) reject('ast_object', 8);
const provenanceText = await fs.readFile(astProvenance, 'utf8');
const provenanceDigest = provenanceText.match(/^schema_sha256=([0-9a-f]{64})$/m)?.[1];
if (!provenanceDigest) {
  console.error(`[std-ast] missing schema_sha256 in ${astProvenance}`);
  process.exit(2);
}
if (provenanceDigest !== await fileDigest(schema)) reject('ast_object', 8);
pass('ast_object');

await fs.mkdir(work, {recursive: true});

const astApiObj = path.join(work, 'ast_api.cpp.obj');
const cxxLauncher = process.env.CMAKE_CXX_COMPILER_LAUNCHER ? [process.env.CMAKE_CXX_COMPILER_LAUNCHER] : [];
await $`${cxxLauncher} ${clangxx} -c ${astApiCpp} -o ${astApiObj} -DCANGJIE_CODEGEN_CJNATIVE_BACKEND -DNDEBUG -DRELEASE -D__windows__ -w -Wdate-time -Wno-int-conversion -fno-omit-frame-pointer -pipe -fno-common -fno-strict-aliasing -m64 -Wa,-mbig-obj -fstack-protector-all -D_FORTIFY_SOURCE=2 -O2 -fPIC -std=c++17 -I${path.join(cangjieHome, 'include')} -I${path.join(cangjieHome, 'third_party', 'flatbuffers', 'include')}`;

const rebuilt = path.join(work, 'libcangjie-std-ast.dll');
await $`${gccDriver} ${astObject} ${astApiObj} ${archive} -lstdc++ -lpthread -L${runtimeDllDir} -L${targetRuntime} -l:libcangjie-std-core.dll -l:libcangjie-std-collection.dll -l:libcangjie-std-sort.dll -l:libcangjie-std-math.dll -Wl,--no-insert-timestamp -Wl,--export-all-symbols ${path.join(runtimeLib, 'section.o')} ${path.join(runtimeLib, 'cjstart.o')} -l:libcangjie-runtime.dll -static -fstack-protector-all -lclang_rt-builtins -l:libboundscheck.dll -lm -Wl,--no-undefined -s -shared --target=x86_64-w64-mingw32 -B${path.join(toolchain, 'bin')} --sysroot=${toolchain} -o ${rebuilt}`;

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

const destination = path.join(installRoot, 'runtime', 'lib', 'windows_x86_64_cjnative');
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(rebuilt, path.join(destination, 'libcangjie-std-ast.dll'));
const digest = (await $({stdio: 'pipe'})`sha256sum ${path.join(destination, 'libcangjie-std-ast.dll')}`).stdout.trim();
log(`installed host-dispatch std-ast DLL: ${digest}`);
