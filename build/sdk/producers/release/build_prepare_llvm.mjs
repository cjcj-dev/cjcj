#!/usr/bin/env node
// phase=prepare N/LLVM producer, one entry for all five hosts. It builds the
// pinned cjcj-llvm fork with LLVM_BUILD_LLVM_DYLIB (the b2701d39
// build-llvm-dylib.yml CMake configuration) and the llc/llvm-as/llvm-dis tools
// of the same build tree that the native consumer requires
// (ci/bootstrap/sdk-inputs.mjs shapes.llvm). Windows runs it in the MSYS2
// MINGW64 shell so the same CMake build yields bin/libLLVM-15.dll; the static
// platform_tuples build does not produce an in-process library.
// Output: OUT/<llvmLibrary>, OUT/bin/<tool><exe>, OUT/BUILD-COMMANDS.json.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sdkPlatform} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {nativeLlvmInputs} from '../../../../ci/native-llvm-inputs.mjs';

export const PREPARE_LLVM_TARGETS = Object.freeze(['LLVM', 'llc', 'llvm-as', 'llvm-dis', 'llvm-nm']);
export function llvmConfigureArgs({source, build, runtime, sha, jobs, os}) {
  return ['-G', 'Ninja', '-S', source, '-B', build,
    `-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`, `-DCJ_LLVM_COMMIT=${sha}`,
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++',
    '-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG', '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG',
    '-DLLVM_ENABLE_ASSERTIONS=OFF', '-DLLVM_ENABLE_RTTI=OFF',
    `-DLLVM_PARALLEL_COMPILE_JOBS=${jobs}`, '-DLLVM_PARALLEL_LINK_JOBS=1',
    '-DBUILD_SHARED_LIBS=OFF', '-DLLVM_BUILD_LLVM_DYLIB=ON', '-DLLVM_LINK_LLVM_DYLIB=OFF',
    '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64', '-DLLVM_ENABLE_PROJECTS=',
    ...(os === 'win32' ? ['-DLLVM_ENABLE_ZLIB=OFF', '-DLLVM_ENABLE_LIBXML2=OFF'] : []),
    '-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string'];
}
export function buildPrepareLlvm({platform, sha, out, work = process.cwd(), env = process.env, run = spawnSync}) {
  const native = sdkPlatform(platform);
  if (!/^[0-9a-f]{40}$/.test(sha || '')) throw new Error('PREPARE_LLVM_SHA');
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
    command(['cmake', ...llvmConfigureArgs({source: path.join(source, 'llvm'), build, runtime, sha, jobs, os: native.os})]);
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
    return {platform, sha, library: native.llvmLibrary, tools: ['llc', 'llvm-as', 'llvm-dis']};
  } finally {
    fs.writeFileSync(path.join(out, 'BUILD-COMMANDS.json'), JSON.stringify(records, null, 2) + '\n');
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const rest = process.argv.slice(2);
    const option = name => { const i = rest.indexOf(`--${name}`); return i >= 0 ? rest[i + 1] : undefined; };
    console.log(JSON.stringify(buildPrepareLlvm({platform: option('platform'), sha: option('sha'),
      out: path.resolve(option('out') || '')})));
  } catch (error) { console.error(error.message); process.exitCode = error.rc || 1; }
}
