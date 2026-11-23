#!/usr/bin/env node
// phase=prepare N/LLVM producer, one entry for all five hosts. It builds the
// pinned cjcj-llvm fork with LLVM_BUILD_LLVM_DYLIB (the b2701d39
// build-llvm-dylib.yml CMake configuration) and the llc/llvm-as/llvm-dis tools
// of the same build tree that the native consumer requires
// (ci/bootstrap/sdk-inputs.mjs shapes.llvm). Windows runs it in the MSYS2
// MINGW64 shell so the same CMake build yields bin/libLLVM-15.dll; the static
// platform_tuples build does not produce an in-process library.
// Output: OUT/<llvmLibrary>, OUT/bin/<tool><exe>, OUT/BUILD-COMMANDS.json.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sdkPlatform} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {nativeLlvmInputs} from '../../../../ci/native-llvm-inputs.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');

export const PREPARE_LLVM_TARGETS = Object.freeze(['LLVM', 'llc', 'llvm-as', 'llvm-dis', 'llvm-nm', 'lldb']);
// cjdb is LLDB of the same tree (upstream compiler third_party/cmake/BuildCJDB.cmake
// enables lldb with CANGJIE_ROOT=<compiler source>); Python/libedit stay off.
export const PREPARE_LLDB_ARGS = Object.freeze(['-DLLVM_ENABLE_PROJECTS=clang;lldb', '-DLLDB_INCLUDE_TESTS=OFF',
  '-DCLANG_INCLUDE_TESTS=OFF', '-DLLDB_ENABLE_PYTHON=OFF', '-DLLDB_ENABLE_LIBEDIT=OFF', '-DLLDB_ENABLE_CURSES=OFF',
  '-DLLDB_ENABLE_LZMA=OFF', '-DLLDB_ENABLE_LIBXML2=OFF', '-DLLVM_ENABLE_TERMINFO=OFF']);
export function llvmConfigureArgs({source, build, runtime, sha, jobs, os, compiler}) {
  if (!compiler) throw new Error('PREPARE_LLVM_COMPILER_SOURCE');
  return ['-G', 'Ninja', '-S', source, '-B', build,
    `-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`, `-DCJ_LLVM_COMMIT=${sha}`,
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++',
    '-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG', '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG',
    '-DLLVM_ENABLE_ASSERTIONS=OFF', '-DLLVM_ENABLE_RTTI=OFF',
    `-DLLVM_PARALLEL_COMPILE_JOBS=${jobs}`, '-DLLVM_PARALLEL_LINK_JOBS=1',
    '-DBUILD_SHARED_LIBS=OFF', '-DLLVM_BUILD_LLVM_DYLIB=ON', '-DLLVM_LINK_LLVM_DYLIB=OFF',
    '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64', ...PREPARE_LLDB_ARGS, `-DCANGJIE_ROOT=${compiler}`,
    ...(os === 'win32' ? ['-DLLVM_ENABLE_ZLIB=OFF', '-DLLVM_ENABLE_LIBXML2=OFF'] : []),
    '-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string'];
}
export function buildPrepareLlvm({platform, sha, out, compiler, work = process.cwd(), env = process.env, run = spawnSync}) {
  const native = sdkPlatform(platform);
  if (!/^[0-9a-f]{40}$/.test(sha || '')) throw new Error('PREPARE_LLVM_SHA');
  if (!compiler || !fs.existsSync(path.join(compiler, 'schema/CjoFormat.fbs'))) throw new Error('PREPARE_LLVM_COMPILER_SOURCE');
  const url = nativeLlvmInputs(env).LLVM_URL;
  const records = [];
  const command = (argv, options = {}) => {
    // npx is a .cmd shim on Windows; Node only starts it through the shell.
    const shell = native.os === 'win32' && argv[0] === 'npx';
    const result = run(shell ? argv.join(' ') : argv[0], shell ? [] : argv.slice(1), {cwd: work, env, shell,
      stdio: options.capture ? 'pipe' : 'inherit', encoding: options.capture ? 'utf8' : undefined, maxBuffer: 512 * 1024 * 1024});
    records.push({argv, rc: result.status, signal: result.signal || null, error: result.error?.message || null});
    if (result.error) throw result.error;
    if (result.status !== 0) throw Object.assign(new Error(`PREPARE_LLVM_COMMAND_RC ${result.status} ${argv.join(' ')}`), {rc: result.status || 1});
    return result.stdout;
  };
  fs.mkdirSync(out, {recursive: true});
  try {
    // CMake -D values keep forward slashes on Windows.
    const slash = value => native.os === 'win32' ? value.replace(/\\/g, '/') : value;
    const source = slash(path.join(work, 'llvm-fork')), build = slash(path.join(work, 'dylib-build'));
    const runtime = slash(path.join(work, 'paired-runtime'));
    if (fs.existsSync(source) || fs.existsSync(build)) throw new Error('PREPARE_LLVM_FRESH_TREE_REQUIRED');
    command(['git', 'init', source]);
    command(['git', '-C', source, 'remote', 'add', 'origin', url]);
    command(['git', '-C', source, 'fetch', '--depth=1', 'origin', sha]);
    command(['git', '-C', source, 'checkout', '--detach', 'FETCH_HEAD']);
    if (command(['git', '-C', source, 'rev-parse', 'HEAD'], {capture: true}).trim() !== sha) throw new Error('PREPARE_LLVM_SOURCE_MISMATCH');
    command(['npx', '--yes', 'zx@8', 'ci/fetch-llvm-runtime.mjs', runtime]);
    const jobs = command([process.execPath, 'ci/build-resources.mjs', '--jobs-only'], {capture: true}).trim();
    if (!/^[1-9][0-9]*$/.test(jobs)) throw new Error('PREPARE_LLVM_JOBS');
    command(['cmake', ...llvmConfigureArgs({source: path.join(source, 'llvm'), build, runtime, sha, jobs, os: native.os, compiler: slash(path.resolve(compiler))})]);
    command(['cmake', '--build', build, '--target', ...PREPARE_LLVM_TARGETS, '--parallel', jobs]);
    const library = path.join(build, native.llvmDirectory, native.llvmLibrary);
    const symbols = command([path.join(build, 'bin', 'llvm-nm' + native.exe), '--defined-only', library], {capture: true});
    if (!/\bLLVMInitializeX86TargetInfo\b/.test(symbols)) throw new Error('PREPARE_LLVM_LIBRARY_SYMBOLS');
    fs.copyFileSync(library, path.join(out, native.llvmLibrary)); // copyFile follows the versioned symlink
    fs.mkdirSync(path.join(out, 'bin'), {recursive: true});
    for (const tool of ['llc', 'llvm-as', 'llvm-dis']) {
      const file = path.join(out, 'bin', tool + native.exe);
      fs.copyFileSync(path.join(build, 'bin', tool + native.exe), file);
      if (native.os !== 'win32') fs.chmodSync(file, 0o755);
    }
    fs.copyFileSync(path.join(build, 'bin', 'lldb' + native.exe), path.join(out, 'bin', 'lldb' + native.exe));
    if (native.os !== 'win32') fs.chmodSync(path.join(out, 'bin', 'lldb' + native.exe), 0o755);
    const libDir = path.join(build, native.os === 'win32' ? 'bin' : 'lib');
    const lldbLibraries = fs.readdirSync(libDir).filter(name => /^liblldb(\.[0-9]+)*\.(so(\.[0-9]+)*|dylib|dll)$/.test(name));
    if (!lldbLibraries.length) throw new Error('PREPARE_LLDB_LIBRARY_MISSING');
    fs.mkdirSync(path.join(out, 'lldb-lib'), {recursive: true});
    for (const name of lldbLibraries) fs.copyFileSync(path.join(libDir, name), path.join(out, 'lldb-lib', name));
    return {platform, sha, library: native.llvmLibrary, tools: ['llc', 'llvm-as', 'llvm-dis'], cjdb: 'bin/lldb' + native.exe, lldbLibraries};
  } finally {
    fs.writeFileSync(path.join(out, 'BUILD-COMMANDS.json'), JSON.stringify(records, null, 2) + '\n');
  }
}

// Compile the compiler-owned LLVM FFI shim (runtime_shim/cjselfhost_llvmshim.cpp,
// as platform_tuples/build_tuple.mjs and ci/bootstrap/native-cjdb.mjs do) against
// the headers of the LLVM tree built above and the CjoFormat schema of the
// checked-out compiler source; the object must define the C entry points.
export const SHIM_CXX_FLAGS = Object.freeze(['-std=c++17', '-O2', '-fno-rtti', '-fno-exceptions', '-DNDEBUG']);
export function shimRequiredSymbols(sourceText) {
  return [...(sourceText.includes('LLVMGlobalObjectAddStringAttribute') ? ['LLVMGlobalObjectAddStringAttribute'] : []),
    'LLVMSelfhost', 'CJOF'];
}
export function shimSymbolProblems(nm, required) {
  const names = String(nm).split(/\r?\n/).map(line => line.trim().split(/\s+/).pop()).filter(Boolean).map(name => name.replace(/^_/, ''));
  return required.filter(want => !names.some(name => want.endsWith('Attribute') ? name === want : name.startsWith(want)));
}
export function buildPrepareShim({platform, compiler, flatc, flatbuffers, out, work = process.cwd(), env = process.env, run = spawnSync}) {
  const native = sdkPlatform(platform);
  const source = path.join(work, 'llvm-fork'), build = path.join(work, 'dylib-build');
  const schema = path.join(compiler || '', 'schema/CjoFormat.fbs');
  if (!compiler || !fs.existsSync(schema)) throw new Error('PREPARE_SHIM_COMPILER_SOURCE');
  if (!fs.existsSync(path.join(build, 'include/llvm/Config/llvm-config.h'))) throw new Error('PREPARE_SHIM_LLVM_BUILD');
  if (!flatc || !fs.existsSync(flatc)) throw new Error('PREPARE_SHIM_FLATC');
  const generated = path.join(work, 'shim-generated'), objectDir = path.join(out, 'fixed-llc');
  const object = path.join(objectDir, 'cjselfhost_llvmshim.o');
  fs.mkdirSync(path.join(generated, 'flatbuffers'), {recursive: true});
  fs.mkdirSync(objectDir, {recursive: true});
  const records = [];
  const command = (argv, capture = false) => {
    const result = run(argv[0], argv.slice(1), {cwd: work, env: {...env, CPATH: '', CPLUS_INCLUDE_PATH: '', C_INCLUDE_PATH: ''},
      stdio: capture ? 'pipe' : 'inherit', encoding: capture ? 'utf8' : undefined, maxBuffer: 256 * 1024 * 1024});
    records.push({argv, rc: result.status});
    if (result.error) throw result.error;
    if (result.status !== 0) throw Object.assign(new Error(`PREPARE_SHIM_COMMAND_RC ${result.status} ${argv[0]}`), {rc: result.status || 1});
    return result.stdout;
  };
  command([flatc, '--no-warnings', '-c', '-o', path.join(generated, 'flatbuffers'), schema]);
  const cpp = path.resolve(repoRoot, 'runtime_shim/cjselfhost_llvmshim.cpp');
  const argv = ['clang++', ...SHIM_CXX_FLAGS, ...(native.os === 'win32' ? [] : ['-fPIC']),
    `-I${path.join(source, 'llvm/include')}`, `-I${path.join(build, 'include')}`,
    `-I${path.join(flatbuffers || path.join(compiler, 'third_party/flatbuffers'), 'include')}`, `-I${generated}`, '-c', cpp, '-o', object];
  command(argv);
  const nm = command([path.join(build, 'bin', 'llvm-nm' + native.exe), '--defined-only', '--extern-only', object], true);
  const required = shimRequiredSymbols(fs.readFileSync(cpp, 'utf8'));
  const missing = shimSymbolProblems(nm, required);
  if (missing.length) throw new Error(`PREPARE_SHIM_SYMBOLS ${missing.join(',')}`);
  const bytes = fs.readFileSync(object);
  const record = {schema: 'cjcj-prepare-shim-v1', platform, object: 'fixed-llc/cjselfhost_llvmshim.o', bytes: bytes.length,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'), symbols: required, argv, commands: records};
  fs.writeFileSync(path.join(objectDir, 'SHIM-BUILD.json'), JSON.stringify(record, null, 2) + '\n');
  return record;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const rest = process.argv.slice(2);
    const option = name => { const i = rest.indexOf(`--${name}`); return i >= 0 ? rest[i + 1] : undefined; };
    if (rest[0] === 'shim') console.log(JSON.stringify(buildPrepareShim({platform: option('platform'),
      compiler: path.resolve(option('compiler') || ''), flatc: option('flatc') && path.resolve(option('flatc')),
      out: path.resolve(option('out') || '')})));
    else console.log(JSON.stringify(buildPrepareLlvm({platform: option('platform'), sha: option('sha'),
      compiler: option('compiler') && path.resolve(option('compiler')), out: path.resolve(option('out') || '')})));
  } catch (error) { console.error(error.message); process.exitCode = error.rc || 1; }
}
