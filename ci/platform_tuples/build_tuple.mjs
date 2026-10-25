#!/usr/bin/env zx
// Build and consume the pinned native tuple, preserving caller-relative paths.
import {fs, path, repo, entry, exit} from '../entry-common.mjs';
import {run, capture, redirect, required, logged} from './entry.mjs';
await entry(async () => {
  const root = required('TUPLE_ROOT', 5, 'TUPLE_ROOT is required');
  const platform = required('TUPLE_PLATFORM', 6, 'TUPLE_PLATFORM is required');
  const targets = required('LLVM_TARGETS', 7, 'LLVM_TARGETS is required');
  const llvmSrc = `${root}/llvm-project`, llvmBuild = `${root}/llvm-build`;
  const flatSrc = `${root}/flatbuffers`, flatBuild = `${root}/flatbuffers-build`;
  const generated = `${root}/shim-generated`, output = `fixed-toolchain/${platform}`;
  await run(['mkdir', '-p', `${root}/logs`, output]);
  await logged(import.meta.url, `${root}/logs/tuple-build.log`, async () => {
    const text = async (command, check = true) => {
      const result = await capture(command, {check});
      process.stderr.write(result.stderr);
      return result.stdout.replace(/\n+$/, '');
    };
    const system = await text(['uname', '-s'], false);
    const windows = system.startsWith('MINGW') || system.startsWith('MSYS');
    const exe = windows ? '.exe' : '', lld = platform.startsWith('darwin_') ? 'ld64.lld' : 'ld.lld';
    await run(['npx', '--yes', 'zx@8', path.join(repo, 'ci/fetch-llvm-runtime.mjs'), '--verify-checkout', `${root}/paired-runtime`]);
    // pwd in the original subshell resolves the actual checkout, not the repo cwd.
    const runtimeSource = await text(['bash', '-c', 'cd "$1" && pwd', 'runtime-source', `${root}/paired-runtime`], false);
    await run(['cmake', '-G', 'Ninja', '-S', `${llvmSrc}/llvm`, '-B', llvmBuild,
      `-DCANGJIE_RUNTIME_SOURCE_DIR=${runtimeSource}`,
      '-DCMAKE_BUILD_TYPE=Release', '-DLLVM_ENABLE_ASSERTIONS=OFF', '-DBUILD_SHARED_LIBS=OFF',
      '-DLLVM_LINK_LLVM_DYLIB=OFF', '-DLLVM_ENABLE_RTTI=OFF', '-DLLVM_ENABLE_ZLIB=OFF',
      '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_TERMINFO=OFF', '-DLLVM_ENABLE_LIBEDIT=OFF',
      '-DLLVM_ENABLE_LIBXML2=OFF',
      '-DLLVM_INCLUDE_TESTS=OFF', '-DLLVM_INCLUDE_EXAMPLES=OFF', '-DLLVM_INCLUDE_BENCHMARKS=OFF',
      `-DLLVM_TARGETS_TO_BUILD=${targets}`, '-DLLVM_ENABLE_PROJECTS=lld',
      '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++',
      '-DCMAKE_CXX_FLAGS=-gline-tables-only -include cstdint -include unordered_map -include map -include vector -include string']);
    await run(['cmake', '--build', llvmBuild, '--target', 'llc', 'opt', 'lld', 'llvm-config', '--parallel', '3']);
    await run(['cmake', '-G', 'Ninja', '-S', flatSrc, '-B', flatBuild,
      '-DFLATBUFFERS_BUILD_TESTS=OFF', '-DFLATBUFFERS_BUILD_FLATLIB=OFF', '-DFLATBUFFERS_BUILD_SHAREDLIB=OFF',
      '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++']);
    await run(['cmake', '--build', flatBuild, '--target', 'flatc', '--parallel', '3']);
    await run(['mkdir', '-p', `${generated}/flatbuffers`]);
    await run([`${flatBuild}/flatc${exe}`, '--no-warnings', '-c', '-o', `${generated}/flatbuffers`, `${root}/cangjie-compiler/schema/CjoFormat.fbs`]);
    await run([...(process.env.SCCACHE_PATH ? [process.env.SCCACHE_PATH] : []), 'clang++', '-std=c++17', '-O2',
      ...(windows ? [] : ['-fPIC']), '-fno-rtti', '-fno-exceptions', `-I${llvmSrc}/llvm/include`, `-I${llvmBuild}/include`,
      `-I${flatSrc}/include`, `-I${generated}`, '-c', 'runtime_shim/cjselfhost_llvmshim.cpp', '-o', `${output}/cjselfhost_llvmshim.o`]);
    for (const tool of ['llc', 'opt', lld]) await redirect(['gzip', '-n', '-c', '-9', `${llvmBuild}/bin/${tool}${exe}`], `${output}/${tool}.gz`);
    const available = async command => (await capture(['bash', '-c', 'command -v "$1" >/dev/null 2>&1', 'has-tool', command], {check: false})).exitCode === 0;
    async function sha(file, check = true) {
      const command = await available('sha256sum') ? ['sha256sum', file] : ['shasum', '-a', '256', file];
      return (await text(command, check)).split(/[ \t]+/)[0];
    }
    // Keep awk's early consumer exit and the original pipefail semantics.
    const version = file => text(['bash', '-c', 'set -o pipefail; "$1" --version | awk \'/LLVM version |^LLD / {sub(/^[[:space:]]+/, ""); print; found=1; exit} END {if (!found) exit 1}\'', 'tool-version', file]);
    const shas = {}, versions = {};
    for (const tool of ['llc', 'opt', lld]) shas[tool] = await sha(`${llvmBuild}/bin/${tool}${exe}`);
    for (const tool of ['llc', 'opt', lld]) versions[tool] = await version(`${llvmBuild}/bin/${tool}${exe}`);
    // Open/truncate before required variables and hashing, as the shell group does.
    const manifest = `${output}/llvm-tools.manifest`, descriptor = fs.openSync(manifest, 'w');
    const emit = (key, value) => fs.writeSync(descriptor, `${key}=${value}\n`);
    try {
      emit('PLATFORM', platform);
      emit('CANGJIE_COMPILER_SHA', required('CANGJIE_COMPILER_SHA', 102));
      emit('FLATBUFFERS_SHA', required('FLATBUFFERS_SHA', 103));
      emit('SHIM_SHA256', await sha(`${output}/cjselfhost_llvmshim.o`, false));
      const llvmSha = required('LLVM_SHA', 105, 'LLVM_SHA is required');
      emit('LLVM_SHA', llvmSha);
      for (const [prefix, tool] of [['LLC', 'llc'], ['OPT', 'opt'], ['LLD', lld]]) {
        if (prefix === 'LLD') emit('LLD_TOOL', lld);
        emit(`${prefix}_SOURCE`, `tuple:${llvmSha}`); emit(`${prefix}_VERSION`, versions[tool]); emit(`${prefix}_SHA256`, shas[tool]);
      }
    } finally { fs.closeSync(descriptor); }
    await run(['mkdir', '-p', `${root}/verify`]);
    for (const tool of ['llc', 'opt', lld]) {
      await redirect(['gunzip', '-c', `${output}/${tool}.gz`], `${root}/verify/${tool}${exe}`);
      await run(['chmod', '0755', `${root}/verify/${tool}${exe}`]);
      await run(['bash', '-c', 'set -o pipefail; "$1" --version | head -n 5', 'verify-version', `${root}/verify/${tool}${exe}`]);
    }
    const llvmSha = process.env.LLVM_SHA;
    await run(['grep', '-Fx', `LLVM_SHA=${llvmSha}`, manifest]);
    for (const [prefix, tool] of [['LLC', 'llc'], ['OPT', 'opt'], ['LLD', lld]]) {
      if (prefix === 'LLD') await run(['grep', '-Fx', `LLD_TOOL=${lld}`, manifest]);
      await run(['grep', '-Fx', `${prefix}_SOURCE=tuple:${llvmSha}`, manifest]);
      await run(['grep', '-Fx', `${prefix}_VERSION=${versions[tool]}`, manifest]);
      await run(['grep', '-Fx', `${prefix}_SHA256=${await sha(`${root}/verify/${tool}${exe}`, false)}`, manifest]);
    }
    await run(['node', 'ci/llvm-tools-manifest.mjs', 'validate', 'tuple', manifest]);
    await run(['file', `${output}/cjselfhost_llvmshim.o`]);
    const nm = await available('llvm-nm') ? 'llvm-nm' : 'nm';
    const exports = await text(['bash', '-c', 'set -o pipefail; "$1" -C "$2" | grep -cE \' [Tt] _?(LLVMGlobalObjectAddStringAttribute|LLVMSelfhost|CJOF)\'', 'shim-exports', nm, `${output}/cjselfhost_llvmshim.o`]);
    if (!(Number(exports) >= 90)) exit(1);
    console.log(`shim exported symbols: ${exports}`);
    if (windows) {
      const components = ['core', 'analysis', 'bitreader', 'bitwriter', 'irreader', 'passes', 'support', 'target', 'transformutils', 'aarch64', 'arm', 'x86'];
      const config = `${llvmBuild}/bin/llvm-config${exe}`, staticDir = `${output}/llvm-static`;
      await run(['mkdir', '-p', staticDir]);
      // mapfile process substitution ignores producer failure, but requires rows.
      const listing = await capture(['bash', '-c', 'ninja -C "$1" -t targets all | grep -oE \'^lib/libLLVM[A-Za-z0-9_]+\\.a\'', 'static-targets', llvmBuild], {check: false});
      process.stderr.write(listing.stderr);
      const staticTargets = listing.stdout.split('\n'); if (staticTargets.at(-1) === '') staticTargets.pop();
      if (!staticTargets.length) exit(1);
      await run(['ninja', '-C', llvmBuild, '-j', '3', 'llc', ...staticTargets]);
      // read -a consumes only the first line and performs IFS splitting without globbing.
      const words = value => value.split('\n')[0].trim().split(/[ \t]+/).filter(Boolean);
      const libResult = await capture([config, '--link-static', '--libfiles', ...components], {check: false}); process.stderr.write(libResult.stderr);
      const libraries = words(libResult.stdout); if (!libraries.length) exit(1);
      fs.writeFileSync(`${output}/llvm-static-libs.txt`, '');
      for (const library of libraries) {
        await run(['test', '-s', library]); const name = library.slice(library.lastIndexOf('/') + 1);
        await run(['cp', library, `${staticDir}/${name}`]); fs.appendFileSync(`${output}/llvm-static-libs.txt`, `${name}\n`);
      }
      const systemResult = await capture([config, '--link-static', '--system-libs', ...components], {check: false}); process.stderr.write(systemResult.stderr);
      fs.writeFileSync(`${output}/llvm-system-libs.txt`, `${words(systemResult.stdout).join('\n')}\n`);
      console.log(`LLVM static archives: ${libraries.length}`);
      await run(['bash', '-c', 'set -o pipefail; du -ch "$1"/*.a | tail -n 1', 'static-size', staticDir]);
    }
    const inventory = await capture(['bash', '-c', 'find "$1" -type f -print0 | sort -z', 'artifacts', output], {check: false});
    process.stderr.write(inventory.stderr);
    for (const artifact of inventory.stdout.split('\0').slice(0, -1)) console.log(`${await sha(artifact, false)}  ${artifact}`);
  });
});
