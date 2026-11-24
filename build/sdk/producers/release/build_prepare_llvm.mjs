#!/usr/bin/env node
// phase=prepare N/LLVM producer, one entry for all five hosts. It builds the
// pinned cjcj-llvm fork with LLVM_BUILD_LLVM_DYLIB (the b2701d39
// build-llvm-dylib.yml CMake configuration) and the llc/llvm-as/llvm-dis tools
// of the same build tree that the native consumer requires
// (ci/bootstrap/sdk-inputs.mjs shapes.llvm). Windows runs it in the MSYS2
// MINGW64 shell so the same CMake build yields bin/libLLVM-15.dll; the static
// platform_tuples build does not produce an in-process library.
// Output: OUT/<llvmLibrary>, OUT/bin/<tool><exe>, OUT/compiler-rt/<library>,
// OUT/BUILD-COMMANDS.json.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sdkPlatform} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {nativeLlvmInputs} from '../../../../ci/native-llvm-inputs.mjs';
import {pythonConfiguration} from '../../../../ci/bootstrap/sdk-cjdb-python.mjs';
import {execute} from '../../../../ci/bootstrap/sdk-io.mjs';
import {verifyNativeSource} from '../../../../ci/bootstrap/sdk-source.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');

// clang-resource-headers populates <build>/lib/clang/<version>/include, the
// resource tree N carries at third_party/llvm/lib/clang for its native clang
// (ci/bootstrap/sdk-targets.mjs installation copies 'N clang resources').
export const PREPARE_LLVM_TARGETS = Object.freeze(['LLVM', 'llc', 'llvm-as', 'llvm-dis', 'llvm-nm', 'lldb',
  'clang-resource-headers']);
export const PREPARE_CLANG_RESOURCES = 'clang-resources';
// The resource tree is lib/clang/<version>/include with the compiler builtin headers.
export function clangResourceProblems(root) {
  const versions = fs.existsSync(root) ? fs.readdirSync(root).filter(name => /^\d+(\.\d+)*$/.test(name)) : [];
  if (versions.length !== 1) return ['lib/clang must hold exactly one version directory: ' + versions.join(',')];
  return ['stddef.h', 'stdint.h', 'stdarg.h'].filter(name => !fs.existsSync(path.join(root, versions[0], 'include', name)))
    .map(name => `lib/clang/${versions[0]}/include/${name} missing`);
}
// N's lib/<tuple> holds the compiler-rt static libraries of the same tree. The
// set and the installed names are cangjie_compiler third_party/CMakeLists.txt
// CLANG_RT_LIBS (build/test/fixtures/compiler-174db8f/third_party/CMakeLists.txt
// 123-147, 379-387, 525): builtins only on x86_64 or Darwin (Darwin: the lipo'd
// libclang_rt.osx.a), profile everywhere, fuzzer_no_main except on Windows.
// cmake/ExtractRtlib.cmake moves each out of lib/clang/<version>/lib/<os>/;
// LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF fixes that <os> layout on every host.
export const PREPARE_COMPILER_RT = 'compiler-rt';
const rtlib = (name, source) => Object.freeze({name, source});
const DARWIN_COMPILER_RT = Object.freeze([rtlib('libclang_rt.osx.a', 'darwin/libclang_rt.osx.a'),
  rtlib('libclang_rt-profile.a', 'darwin/libclang_rt.profile_osx.a'),
  rtlib('libclang_rt.fuzzer_no_main.a', 'darwin/libclang_rt.fuzzer_no_main_osx.a')]);
export const PREPARE_COMPILER_RT_LIBRARIES = Object.freeze({
  linux_x86_64: Object.freeze([rtlib('libclang_rt-builtins.a', 'linux/libclang_rt.builtins-x86_64.a'),
    rtlib('libclang_rt-profile.a', 'linux/libclang_rt.profile-x86_64.a'),
    rtlib('libclang_rt.fuzzer_no_main.a', 'linux/libclang_rt.fuzzer_no_main-x86_64.a')]),
  linux_aarch64: Object.freeze([rtlib('libclang_rt-profile.a', 'linux/libclang_rt.profile-aarch64.a'),
    rtlib('libclang_rt.fuzzer_no_main.a', 'linux/libclang_rt.fuzzer_no_main-aarch64.a')]),
  darwin_aarch64: DARWIN_COMPILER_RT,
  darwin_x86_64: DARWIN_COMPILER_RT,
  windows_x86_64: Object.freeze([rtlib('libclang_rt-builtins.a', 'windows/libclang_rt.builtins-x86_64.a'),
    rtlib('libclang_rt-profile.a', 'windows/libclang_rt.profile-x86_64.a')]),
});
export function compilerRtLibraries(platform) {
  const rows = PREPARE_COMPILER_RT_LIBRARIES[platform];
  if (!rows) throw new Error('PREPARE_COMPILER_RT_PLATFORM ' + platform);
  return rows;
}
// The compiler-rt components those libraries come from; the rest stay off.
export const compilerRtTargets = os => ['builtins', 'profile', ...(os === 'win32' ? [] : ['fuzzer'])];
// Off Darwin, COMPILER_RT_DEFAULT_TARGET_ONLY makes the pinned compiler-rt take
// its one triple from CMAKE_C_COMPILER_TARGET (eb7ad012 compiler-rt/CMakeLists.txt:107
// -> cmake/Modules/CompilerRTUtils.cmake:423-434); left unset, that macro's
// string(REPLACE) fails at configure. Each value is the host triple the pinned
// llvm/cmake/modules/GetHostTriple.cmake selects on that runner (config.guess on
// Linux, MINGW64 clang on Windows), so compiler-rt and LLVM_TARGET_TRIPLE agree,
// and its architecture is the suffix PREPARE_COMPILER_RT_LIBRARIES installs.
export const PREPARE_COMPILER_RT_TRIPLES = Object.freeze({
  linux_x86_64: 'x86_64-unknown-linux-gnu', linux_aarch64: 'aarch64-unknown-linux-gnu',
  windows_x86_64: 'x86_64-w64-windows-gnu'});
export function compilerRtArgs(platform) {
  const {os} = sdkPlatform(platform), triple = PREPARE_COMPILER_RT_TRIPLES[platform];
  if (os !== 'darwin' && !triple) throw new Error('PREPARE_COMPILER_RT_TRIPLE ' + platform);
  return ['-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF', '-DCOMPILER_RT_ENABLE_IOS=OFF',
    '-DCOMPILER_RT_BUILD_BUILTINS=ON', '-DCOMPILER_RT_BUILD_PROFILE=ON', `-DCOMPILER_RT_BUILD_LIBFUZZER=${os === 'win32' ? 'OFF' : 'ON'}`,
    '-DCOMPILER_RT_BUILD_SANITIZERS=OFF', '-DCOMPILER_RT_BUILD_XRAY=OFF', '-DCOMPILER_RT_BUILD_MEMPROF=OFF',
    '-DCOMPILER_RT_BUILD_ORC=OFF', '-DCOMPILER_RT_BUILD_GWP_ASAN=OFF', '-DCOMPILER_RT_BUILD_CRT=OFF',
    // Darwin builds its fat osx libraries for the SDK's architectures.
    ...(os === 'darwin' ? [] : ['-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON', '-DCMAKE_C_COMPILER_TARGET=' + triple])];
}
// A static library is an ar archive, or on Darwin a fat (lipo) file of archives.
export function isStaticLibrary(file) {
  let head;
  try { head = Buffer.alloc(8); const fd = fs.openSync(file, 'r'); fs.readSync(fd, head, 0, 8, 0); fs.closeSync(fd); }
  catch { return false; }
  return head.toString('latin1') === '!<arch>\n' || head.readUInt32BE(0) === 0xcafebabe;
}
// Move the libraries out of the build's resource tree under their installed
// names (as ExtractRtlib.cmake renames them); any missing one stops the export.
export function extractCompilerRt({platform, resources, out}) {
  const version = fs.readdirSync(resources).find(name => /^\d+(\.\d+)*$/.test(name));
  const rows = compilerRtLibraries(platform), source = row => path.join(resources, version, 'lib', row.source);
  const missing = rows.filter(row => !isStaticLibrary(source(row)));
  if (missing.length) throw new Error('PREPARE_COMPILER_RT_MISSING ' + missing.map(row => `lib/clang/${version}/lib/${row.source}`).join(', '));
  fs.mkdirSync(path.join(out, PREPARE_COMPILER_RT), {recursive: true});
  for (const row of rows) {
    fs.copyFileSync(source(row), path.join(out, PREPARE_COMPILER_RT, row.name));
    fs.rmSync(source(row));
  }
  return rows.map(row => row.name);
}
// cjdb is LLDB of the same tree (upstream compiler third_party/cmake/BuildCJDB.cmake
// enables lldb with CANGJIE_ROOT=<compiler source>); libedit/curses stay off.
export const PREPARE_LLVM_PROJECTS = 'clang;lldb;compiler-rt';
export const PREPARE_LLDB_ARGS = Object.freeze(['-DLLVM_ENABLE_PROJECTS=' + PREPARE_LLVM_PROJECTS, '-DLLDB_INCLUDE_TESTS=OFF',
  '-DCLANG_INCLUDE_TESTS=OFF', '-DLLDB_ENABLE_LIBEDIT=OFF', '-DLLDB_ENABLE_CURSES=OFF',
  '-DLLDB_ENABLE_LZMA=OFF', '-DLLDB_ENABLE_LIBXML2=OFF', '-DLLVM_ENABLE_TERMINFO=OFF']);
// The formal nativeN check (ci/bootstrap/sdk-native-input-check.mjs) requires
// cjdb's Python input: the relocated CPython 3.11 its LLDB was configured with
// (sdk-cjdb-python.mjs verifyRelocatedCjdbPython). It is a fixed archive whose
// prefix is relocatable (bin/python3.11, include/python3.11, lib/libpython3.11.so).
// The darwin/windows python-versions archives are .pkg/.exe installers, not a
// prefix. Those hosts use the relocatable install_only CPython 3.11.9 prefix
// archives of python-build-standalone 20240726 (top directory python/): the
// Darwin prefix has the Unix layout above; the Windows prefix has python.exe,
// python311.dll, include/ and libs/python311.lib, which sdk-cjdb-python.mjs
// pythonConfiguration selects on Windows.
const PBS = 'https://github.com/astral-sh/python-build-standalone/releases/download/20240726/cpython-3.11.9+20240726-';
export const PREPARE_PYTHON_WINDOWS_MEMBERS = Object.freeze(['python.exe', 'pythonw.exe', 'python3.dll', 'python311.dll',
  'vcruntime140.dll', 'vcruntime140_1.dll', 'DLLs', 'Lib', 'include', 'libs', 'LICENSE.txt']);
export const PREPARE_PYTHON = Object.freeze({
  linux_x86_64: Object.freeze({version: '3.11.9', size: 118991790,
    url: 'https://github.com/actions/python-versions/releases/download/3.11.9-9947079978/python-3.11.9-linux-22.04-x64.tar.gz',
    sha256: '6f32bd7be4a7ec53a419afc41e14237c42bcdf654a4397fde5bd66290ba92718'}),
  linux_aarch64: Object.freeze({version: '3.11.9', size: 117137740,
    url: 'https://github.com/actions/python-versions/releases/download/3.11.9-9947079978/python-3.11.9-linux-24.04-arm64.tar.gz',
    sha256: '3681d081b289bc53eecacb306442b530c25456dc6268d37ac60c201fa67073be'}),
  darwin_x86_64: Object.freeze({version: '3.11.9', size: 18164076, url: PBS + 'x86_64-apple-darwin-install_only.tar.gz',
    sha256: 'dc3174666a30f4c38d04e79a80c3159b4b3aa69597c4676701c8386696811611', prefix: 'python'}),
  darwin_aarch64: Object.freeze({version: '3.11.9', size: 17789090, url: PBS + 'aarch64-apple-darwin-install_only.tar.gz',
    sha256: 'cbdac9462bab9671c8e84650e425d3f43b775752a930a2ef954a0d457d5c00c3', prefix: 'python'}),
  windows_x86_64: Object.freeze({version: '3.11.9', size: 40891838, url: PBS + 'x86_64-pc-windows-msvc-install_only.tar.gz',
    sha256: 'f694be48bdfec1dace6d69a19906b6083f4dd7c7c61f1138ba520e433e5598f8', prefix: 'python',
    members: PREPARE_PYTHON_WINDOWS_MEMBERS}),
});
export const PREPARE_PYTHON_MEMBERS = Object.freeze(['bin', 'lib', 'include', 'share']);
export const preparePythonMembers = platform => PREPARE_PYTHON[platform]?.members ?? PREPARE_PYTHON_MEMBERS;
// With Python on, the same build tree's lldb Python package (target lldb-python,
// lib/python3.11/site-packages/lldb with its _lldb binding) is what cjdb imports.
export const PREPARE_LLDB_PYTHON_TARGET = 'lldb-python';
export const PREPARE_LLDB_PYTHON_PACKAGE = 'lib/python3.11/site-packages/lldb';
// In the build tree LLDB places the package at the selected Python's platlib
// relative path: Lib/site-packages on Windows. Installed N keeps one location.
export const lldbPythonBuildPackage = os => os === 'win32' ? 'Lib/site-packages/lldb' : PREPARE_LLDB_PYTHON_PACKAGE;
// The pinned binding imports six unconditionally (eb7ad012 lldb/bindings/python/
// python.swig:88). With LLDB_USE_SYSTEM_SIX off (lldb/cmake/modules/LLDBConfig.cmake:67)
// LLDB copies its own six.py beside the package (bindings/python/CMakeLists.txt:63-67)
// and installs that parent directory (:174); none of the pinned Python prefixes has a
// top-level six, so the sibling crosses with the package.
export const PREPARE_LLDB_PYTHON_SIX = 'six.py';
// Unix LLDB's Python package links lldb/lldb-argdumper to ../../../../bin/lldb-argdumper
// (lldb/bindings/python/CMakeLists.txt finish_swig_python, create_relative_symlink); the
// same build's helper is exported at bin/ so the installed link resolves to it.
export const PREPARE_LLDB_ARGDUMPER = 'lldb-argdumper';
export function lldbPythonArgs(python, os) {
  if (!python) return ['-DLLDB_ENABLE_PYTHON=OFF'];
  for (const key of ['executable', 'include', 'library'])
    if (!python[key]) throw new Error('PREPARE_LLDB_PYTHON_SELECTION ' + key);
  // CMake -D values keep forward slashes on Windows.
  const value = key => os === 'win32' ? python[key].replace(/\\/g, '/') : python[key];
  return ['-DLLDB_ENABLE_PYTHON=ON', `-DPython3_EXECUTABLE=${value('executable')}`, `-DPython3_INCLUDE_DIR=${value('include')}`,
    `-DPython3_LIBRARY=${value('library')}`, '-DLLDB_EMBED_PYTHON_HOME=OFF'];
}
export function llvmConfigureArgs({source, build, runtime, sha, jobs, platform, compiler, python}) {
  if (!compiler) throw new Error('PREPARE_LLVM_COMPILER_SOURCE');
  const {os} = sdkPlatform(platform);
  return ['-G', 'Ninja', '-S', source, '-B', build,
    `-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`, `-DCJ_LLVM_COMMIT=${sha}`,
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++',
    '-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG', '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG',
    '-DLLVM_ENABLE_ASSERTIONS=OFF', '-DLLVM_ENABLE_RTTI=OFF',
    `-DLLVM_PARALLEL_COMPILE_JOBS=${jobs}`, '-DLLVM_PARALLEL_LINK_JOBS=1',
    // On Unix llc/llvm-as/llvm-dis link the in-process library itself, so the
    // installed readers load the installed N (sdk-native-input-check.mjs ldd domain).
    '-DBUILD_SHARED_LIBS=OFF', '-DLLVM_BUILD_LLVM_DYLIB=ON', `-DLLVM_LINK_LLVM_DYLIB=${os === 'win32' ? 'OFF' : 'ON'}`,
    '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64', ...PREPARE_LLDB_ARGS, ...compilerRtArgs(platform), ...lldbPythonArgs(python, os), `-DCANGJIE_ROOT=${compiler}`,
    ...(os === 'win32' ? ['-DLLVM_ENABLE_ZLIB=OFF', '-DLLVM_ENABLE_LIBXML2=OFF'] : []),
    '-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string'];
}
// llvm-nm --defined-only prints a Mach-O C symbol with its leading '_' and an ELF
// dynamic symbol with its version (LLVMInitializeX86TargetInfo@@LLVM_15); compare
// the C name, as ci/bootstrap/std-runtime-colour.mjs nativeSymbol does.
export const PREPARE_LLVM_LIBRARY_SYMBOLS = Object.freeze(['LLVMInitializeX86TargetInfo']);
export function llvmLibrarySymbolProblems(nm, required = PREPARE_LLVM_LIBRARY_SYMBOLS) {
  const names = new Set(String(nm).split(/\r?\n/).map(line => line.trim().split(/\s+/).pop()).filter(Boolean)
    .map(name => name.split('@', 1)[0].replace(/^_/, '')));
  return required.filter(want => !names.has(want));
}
export function buildPrepareLlvm({platform, sha, out, compiler, python, work = process.cwd(), env = process.env, run = spawnSync}) {
  const native = sdkPlatform(platform);
  if (!/^[0-9a-f]{40}$/.test(sha || '')) throw new Error('PREPARE_LLVM_SHA');
  if (!compiler || !fs.existsSync(path.join(compiler, 'schema/CjoFormat.fbs'))) throw new Error('PREPARE_LLVM_COMPILER_SOURCE');
  if (PREPARE_PYTHON[platform] && !python) throw new Error('PREPARE_LLDB_PYTHON_REQUIRED ' + platform);
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
    command(['cmake', ...llvmConfigureArgs({source: path.join(source, 'llvm'), build, runtime, sha, jobs, platform, compiler: slash(path.resolve(compiler)), python})]);
    command(['cmake', '--build', build, '--target', ...compilerRtTargets(native.os), ...PREPARE_LLVM_TARGETS,
      ...(native.os !== 'win32' ? [PREPARE_LLDB_ARGDUMPER] : []), ...(python ? [PREPARE_LLDB_PYTHON_TARGET] : []), '--parallel', jobs]);
    const library = path.join(build, native.llvmDirectory, native.llvmLibrary);
    const symbols = command([path.join(build, 'bin', 'llvm-nm' + native.exe), '--defined-only', library], {capture: true});
    if (llvmLibrarySymbolProblems(symbols).length) throw new Error('PREPARE_LLVM_LIBRARY_SYMBOLS');
    fs.copyFileSync(library, path.join(out, native.llvmLibrary)); // copyFile follows the versioned symlink
    fs.mkdirSync(path.join(out, 'bin'), {recursive: true});
    for (const tool of ['llc', 'llvm-as', 'llvm-dis']) {
      const file = path.join(out, 'bin', tool + native.exe);
      fs.copyFileSync(path.join(build, 'bin', tool + native.exe), file);
      if (native.os !== 'win32') fs.chmodSync(file, 0o755);
    }
    fs.copyFileSync(path.join(build, 'bin', 'lldb' + native.exe), path.join(out, 'bin', 'lldb' + native.exe));
    if (native.os !== 'win32') fs.chmodSync(path.join(out, 'bin', 'lldb' + native.exe), 0o755);
    if (native.os !== 'win32') {
      const argdumper = path.join(build, 'bin', PREPARE_LLDB_ARGDUMPER);
      if (!fs.existsSync(argdumper) || !fs.statSync(argdumper).isFile()) throw new Error('PREPARE_LLDB_ARGDUMPER_MISSING bin/' + PREPARE_LLDB_ARGDUMPER);
      fs.copyFileSync(argdumper, path.join(out, 'bin', PREPARE_LLDB_ARGDUMPER));
      fs.chmodSync(path.join(out, 'bin', PREPARE_LLDB_ARGDUMPER), 0o755);
    }
    const libDir = path.join(build, native.os === 'win32' ? 'bin' : 'lib');
    const lldbLibraries = fs.readdirSync(libDir).filter(name => /^liblldb(\.[0-9]+)*\.(so(\.[0-9]+)*|dylib|dll)$/.test(name));
    if (!lldbLibraries.length) throw new Error('PREPARE_LLDB_LIBRARY_MISSING');
    fs.mkdirSync(path.join(out, 'lldb-lib'), {recursive: true});
    for (const name of lldbLibraries) fs.copyFileSync(path.join(libDir, name), path.join(out, 'lldb-lib', name));
    const resources = path.join(build, 'lib', 'clang'), resourceProblems = clangResourceProblems(resources);
    if (resourceProblems.length) throw new Error('PREPARE_CLANG_RESOURCES ' + resourceProblems.join('; '));
    const compilerRt = extractCompilerRt({platform, resources, out});
    fs.cpSync(resources, path.join(out, PREPARE_CLANG_RESOURCES), {recursive: true, verbatimSymlinks: true});
    if (python) {
      const pkg = path.join(build, lldbPythonBuildPackage(native.os));
      if (!fs.existsSync(pkg) || !fs.readdirSync(pkg).some(name => name.startsWith('_lldb')))
        throw new Error('PREPARE_LLDB_PYTHON_PACKAGE_MISSING ' + lldbPythonBuildPackage(native.os));
      const six = path.join(path.dirname(pkg), PREPARE_LLDB_PYTHON_SIX);
      if (!fs.existsSync(six) || !fs.lstatSync(six).isFile())
        throw new Error('PREPARE_LLDB_PYTHON_SIX_MISSING ' + path.posix.join(path.posix.dirname(lldbPythonBuildPackage(native.os)), PREPARE_LLDB_PYTHON_SIX));
      fs.cpSync(pkg, path.join(out, 'lldb-python/lldb'), {recursive: true, verbatimSymlinks: true});
      fs.copyFileSync(six, path.join(out, 'lldb-python', PREPARE_LLDB_PYTHON_SIX));
    }
    return {platform, sha, library: native.llvmLibrary, tools: ['llc', 'llvm-as', 'llvm-dis'], cjdb: 'bin/lldb' + native.exe, lldbLibraries,
      clangResources: PREPARE_CLANG_RESOURCES, compilerRt, build};
  } finally {
    fs.writeFileSync(path.join(out, 'BUILD-COMMANDS.json'), JSON.stringify(records, null, 2) + '\n');
  }
}

// Fetch the fixed Python archive into OUT/python and record its source and the
// three products the consumer re-checks (pythonSourceInputs: interpreter, header,
// library), with the selection the LLDB configure step uses.
const sha256File = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
export async function preparePython({platform, out, download = async (url, file) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`PREPARE_PYTHON_DOWNLOAD ${response.status}`);
  fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
}, run = spawnSync, configure = pythonConfiguration}, pins = PREPARE_PYTHON) {
  const pin = pins[platform];
  if (!pin) throw new Error('PREPARE_PYTHON_UNAVAILABLE ' + platform);
  const root = path.join(out, 'python'), archive = path.join(out, path.basename(new URL(pin.url).pathname));
  if (fs.existsSync(root)) throw new Error('PREPARE_PYTHON_FRESH_PREFIX_REQUIRED');
  const commit = await verifyNativeSource({source: repoRoot});
  if (commit === 'unknown') throw new Error('PYTHON_PRODUCER_SOURCE');
  const producer = {repository: repoRoot, commit, scriptSha256: sha256File(fileURLToPath(import.meta.url))};
  fs.mkdirSync(root, {recursive: true});
  await download(pin.url, archive);
  if (fs.statSync(archive).size !== pin.size || sha256File(archive) !== pin.sha256) throw new Error('PREPARE_PYTHON_ARCHIVE_IDENTITY');
  const members = preparePythonMembers(platform), top = pin.prefix ?? '.';
  // The archive and prefix are siblings, so tar sees no drive-letter path; on
  // Windows the system bsdtar extracts (as prepare_native_inputs.mjs SYSTEM_TAR).
  const tar = process.platform === 'win32'
    ? path.join(process.env.SystemRoot || process.env.SYSTEMROOT || 'C:\\Windows', 'System32', 'tar.exe') : 'tar';
  const extracted = run(tar, ['-xzf', path.join('..', path.basename(archive)), ...(pin.prefix ? ['--strip-components=1'] : []),
    ...members.map(name => top + '/' + name)], {stdio: 'inherit', cwd: root});
  if (extracted.error || extracted.status !== 0) throw new Error('PREPARE_PYTHON_EXTRACT');
  fs.rmSync(archive);
  // The archive's sysconfig LIBDIR names its build prefix; select by the
  // running prefix, as the relocated consumer does (installed=true).
  const selected = await configure(root, platform, execute, undefined, true);
  if (selected.version.split(/\s/)[0] !== pin.version) throw new Error('PREPARE_PYTHON_VERSION');
  const files = {};
  for (const file of [selected.executable, path.join(selected.include, 'Python.h'), selected.library]) {
    const real = fs.realpathSync(file), rel = path.relative(fs.realpathSync(root), real).split(path.sep).join('/');
    if (rel.startsWith('../') || path.isAbsolute(rel)) throw new Error('PREPARE_PYTHON_PRODUCT_OUTSIDE ' + file);
    files[rel] = {sha256: sha256File(real)};
  }
  const record = {schema: 'cjcj-prepare-python-v1', rc: 0, target: platform, host: platform,
    producer,
    source: {url: pin.url, version: pin.version, sha256: pin.sha256}, files};
  fs.writeFileSync(path.join(out, 'PYTHON-BUILD-INPUTS.json'), JSON.stringify(record, null, 2) + '\n');
  fs.writeFileSync(path.join(out, 'PYTHON-SELECTED.json'), JSON.stringify(selected, null, 2) + '\n');
  return {root, selected, record};
}
// After the LLDB configure+build: the actual CMakeCache Python identity must be
// the selected prefix (the relationship verifyRelocatedCjdbPython re-reads).
export function pythonCacheConfiguration({selected, build}) {
  const cacheFile = path.join(build, 'CMakeCache.txt'), cache = fs.readFileSync(cacheFile, 'utf8');
  const value = name => cache.match(new RegExp(`^${name}:[^=]+=([^\\n]*)$`, 'm'))?.[1];
  const actual = {executable: value('_Python3_EXECUTABLE') || value('Python3_EXECUTABLE'),
    include: value('_Python3_INCLUDE_DIR') || value('Python3_INCLUDE_DIR'),
    library: value('_Python3_LIBRARY_RELEASE') || value('Python3_LIBRARY'), suffix: value('LLDB_PYTHON_EXT_SUFFIX')};
  for (const name of ['executable', 'include', 'library'])
    if (!actual[name] || !fs.existsSync(actual[name]) || fs.realpathSync(actual[name]) !== fs.realpathSync(selected[name]))
      throw new Error(`PREPARE_LLDB_PYTHON_IDENTITY ${name}: ${actual[name]} != ${selected[name]}`);
  if (actual.suffix !== selected.suffix) throw new Error(`PREPARE_LLDB_PYTHON_IDENTITY suffix: ${actual.suffix} != ${selected.suffix}`);
  return {selected, actual, cacheSha256: sha256File(cacheFile)};
}
export function recordPreparePython({out, build}) {
  const selected = JSON.parse(fs.readFileSync(path.join(out, 'PYTHON-SELECTED.json'), 'utf8'));
  const configured = pythonCacheConfiguration({selected, build});
  fs.writeFileSync(path.join(out, 'PYTHON-CONFIGURED.json'), JSON.stringify(configured, null, 2) + '\n');
  return configured;
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
    else {
      const platform = option('platform'), out = path.resolve(option('out') || '');
      const python = PREPARE_PYTHON[platform] ? (await preparePython({platform, out})).selected : undefined;
      const built = buildPrepareLlvm({platform, sha: option('sha'), python,
        compiler: option('compiler') && path.resolve(option('compiler')), out});
      if (python) recordPreparePython({out, build: built.build});
      console.log(JSON.stringify(built));
    }
  } catch (error) { console.error(error.message); process.exitCode = error.rc || 1; }
}
