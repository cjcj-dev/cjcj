#!/usr/bin/env zx
// The native recipes below are the build-llvm-{tools,dylib}.yml and
// bootstrap.sh::stdlib_build recipes. CMake/Ninja/build.py remain producers.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {gzipSync} from 'node:zlib';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {execute, fileDigest, readJson, atomicJson, canonical, sourceIdentity, registeredSourceIdentity, reject, PLATFORMS, inventory} from './sdk-manifest.mjs';
import {parseLlvmToolsManifest} from '../llvm-tools-manifest.mjs';
import {buildStageCompiler} from './sdk-stage-producer.mjs';
import {writeStdProvenance} from '../../build/lib/provenance.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
let activeRequest;
const tool = name => {
  const declared = activeRequest.component.config.tools[name];
  if (!declared) reject('TOOL_IDENTITY', activeRequest.component.id, `missing tool ${name}`);
  return declared.path;
};
const run = async (argv, options = {}) => {
  argv = [...argv];
  if (!path.isAbsolute(argv[0])) argv[0] = tool(argv[0]);
  console.log(canonical({argv, cwd: options.cwd}).trim());
  const started = performance.now();
  const result = await new Promise((resolve, rejectPromise) => {
    const child = spawn(argv[0], argv.slice(1), {...options, stdio: 'inherit'});
    child.once('error', rejectPromise); child.once('exit', (rc, signal) => resolve({rc, signal}));
  });
  console.log(canonical({event: 'native-command-result', command: argv[0], ...result, wall: (performance.now() - started) / 1000}).trim());
  if (result.rc !== 0 || result.signal) throw Object.assign(new Error(`native producer rc=${result.rc} signal=${result.signal} command=${argv[0]}`), result);
  return result;
};
async function fetchIdentity(input, target, label) {
  if (!input || !/^[0-9a-f]{40}$/.test(input.commit) || !/^[0-9a-f]{40}$/.test(input.tree) || !input.repo) reject('SOURCE', label, 'full dependency source identity');
  await fs.mkdir(target, {recursive: true});
  try { await sourceIdentity(target, input, label, tool('git')); }
  catch (error) {
    // Only initialize a genuinely new source directory. A mismatched existing
    // checkout is never reset or repurposed under another source identity.
    if ((await fs.readdir(target)).length) throw error;
    await run(['git', 'init', '-q', target]);
    await run(['git', '-C', target, 'fetch', '--depth=1', '--no-tags', input.repo, input.commit]);
    await run(['git', '-C', target, 'checkout', '--quiet', '--detach', input.commit]);
  }
  await sourceIdentity(target, input, label, tool('git')); return target;
}
function optionsOnly(options, names, label) {
  if (Object.keys(options).some(key => !names.includes(key))) reject('PRODUCER_OPTIONS', label, 'unknown option');
}
async function llvm(request) {
  const {component, source, directory, dependencies} = request;
  const options = component.config.options, dylib = component.producer.adapter === 'llvm-dylib';
  optionsOnly(options, ['targets', 'runtimeDependency', 'compilerSource', 'flatbuffersSource', 'launcher', 'auxiliaryOnly', 'bitcodeReadersOnly', 'releaseToolsOnly', 'releaseLibrariesOnly'], component.id);
  if (options.targets !== 'X86;ARM;AArch64') reject('PRODUCER_OPTIONS', component.id, 'complete LLVM C API target set required');
  const runtime = dependencies[options.runtimeDependency];
  if (!runtime?.component.roles.includes('runtime') || runtime.component.source.kind !== 'git') reject('PRODUCER_DEPENDENCY', component.id, 'paired runtime Git producer');
  const paired = await fetchIdentity(runtime.component.source, path.join(directory, 'source-inputs', 'runtime'), 'llvm-runtime');
  const build = path.join(directory, 'build', dylib ? 'dylib' : 'tools');
  const flags = '-include cstdint -include unordered_map -include map -include vector -include string';
  const cmake = ['cmake', '-G', 'Ninja', '-S', path.join(source, 'llvm'), '-B', build,
    `-DCANGJIE_RUNTIME_SOURCE_DIR=${paired}`, `-DCMAKE_BUILD_TYPE=${dylib ? 'RelWithDebInfo' : 'Release'}`,
    `-DCMAKE_C_COMPILER=${tool('clang')}`, `-DCMAKE_CXX_COMPILER=${tool('clang++')}`,
    `-DCMAKE_MAKE_PROGRAM=${tool('ninja')}`, '-DLLVM_ENABLE_ASSERTIONS=OFF',
    '-DLLVM_ENABLE_RTTI=OFF', '-DBUILD_SHARED_LIBS=OFF', '-DLLVM_LINK_LLVM_DYLIB=OFF',
    `-DLLVM_BUILD_LLVM_DYLIB=${dylib ? 'ON' : 'OFF'}`, `-DLLVM_TARGETS_TO_BUILD=${options.targets}`,
    `-DLLVM_ENABLE_PROJECTS=${dylib ? '' : options.releaseLibrariesOnly ? 'clang' : 'lld'}`, `-DCMAKE_CXX_FLAGS=${dylib ? '' : '-gline-tables-only '}${flags}`];
  if (dylib) cmake.push('-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG', '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O2 -g1 -DNDEBUG');
  else cmake.push('-DLLVM_ENABLE_LIBXML2=OFF');
  if (options.launcher) {
    const launcher = component.config.tools.launcher;
    if (!launcher || options.launcher !== launcher.path) reject('TOOL_IDENTITY', component.id, 'launcher must be explicitly pinned');
    cmake.push(`-DCMAKE_C_COMPILER_LAUNCHER=${launcher.path}`, `-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher.path}`);
  }
  await run(cmake);
  const releaseTargets = ['lld', 'lli', 'llvm-link', 'llvm-lto', 'llvm-lto2', 'llvm-cov', 'llvm-profdata', 'llvm-profgen', 'llvm-symbolizer', 'llvm-objdump', 'llvm-addr2line', 'llvm-otool'];
  await run(['cmake', '--build', build, '--target', ...(dylib ? ['LLVM', 'llvm-nm'] : options.releaseLibrariesOnly ? ['LTO', 'clang-cpp'] : options.releaseToolsOnly ? releaseTargets : options.bitcodeReadersOnly ? ['llvm-dis', 'llvm-as'] : options.auxiliaryOnly ? ['llvm-objcopy', 'llvm-ar'] : ['llc', 'opt', 'lld', 'llvm-dis', 'llvm-as']), '-j', String(os.availableParallelism())]);
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts, {recursive: true});
  if (options.releaseLibrariesOnly) {
    await fs.mkdir(path.join(artifacts, 'lib'));
    for (const name of ['libLTO.so.15', 'libclang-cpp.so.15']) await fs.copyFile(path.join(build, 'lib', name), path.join(artifacts, 'lib', name));
    await fs.symlink('libLTO.so.15', path.join(artifacts, 'lib/libLTO.so'));
    await atomicJson(path.join(artifacts, 'release-libraries.json'), {source: component.source, targets: ['LTO', 'clang-cpp'],
      host: component.config.host, target: component.config.target, producer: component.producer, buildId: request.identity.buildId});
    await sourceIdentity(paired, runtime.component.source, 'llvm-runtime', tool('git'));
    return;
  }
  if (options.releaseToolsOnly) {
    // These are native targets and aliases from the LLVM/lld CMake graph,
    // independently sealed from the bootstrap tuple and completed readers.
    const binaries = ['lld', 'ld.lld', 'ld64.lld', 'lld-link', ...releaseTargets.slice(1)];
    await fs.mkdir(path.join(artifacts, 'bin'));
    for (const name of binaries) {
      const input = path.join(build, 'bin', name), output = path.join(artifacts, 'bin', name);
      if ((await fs.lstat(input)).isSymbolicLink()) await fs.symlink(await fs.readlink(input), output);
      else { await fs.copyFile(input, output); await fs.chmod(output, 0o755); }
    }
    await atomicJson(path.join(artifacts, 'release-tools.json'), {source: component.source, targets: releaseTargets, binaries,
      host: component.config.host, target: component.config.target, producer: component.producer, buildId: request.identity.buildId});
    await sourceIdentity(paired, runtime.component.source, 'llvm-runtime', tool('git'));
    return;
  }
  if (options.auxiliaryOnly || options.bitcodeReadersOnly) {
    await fs.mkdir(path.join(artifacts, 'bin'));
    const tools = {};
    const targets = options.bitcodeReadersOnly ? ['llvm-dis', 'llvm-as'] : ['llvm-objcopy', 'llvm-ar'];
    for (const name of targets) {
      const binary = path.join(build, 'bin', name), destination = path.join(artifacts, 'bin', name);
      await fs.copyFile(binary, destination); await fs.chmod(destination, 0o755);
      tools[name] = {sha256: await fileDigest(destination), version: (await execute(binary, ['--version'])).stdout.trim()};
    }
    await atomicJson(path.join(artifacts, options.bitcodeReadersOnly ? 'bitcode-readers.json' : 'auxiliary-producer.json'), {source: component.source, targets, tools,
      producer: component.producer, buildId: request.identity.buildId});
    await sourceIdentity(paired, runtime.component.source, 'llvm-runtime', tool('git'));
    return;
  }
  if (dylib) {
    const library = component.config.target.startsWith('darwin_') ? 'libLLVM.dylib' : 'libLLVM-15.so';
    await fs.copyFile(path.join(build, 'lib', library), path.join(artifacts, library));
    const symbols = (await execute(path.join(build, 'bin', 'llvm-nm'), ['--defined-only', path.join(build, 'lib', library)], {maxBuffer: 64 * 1024 * 1024})).stdout;
    await fs.writeFile(path.join(artifacts, 'defined-symbols.txt'), symbols);
    await atomicJson(path.join(artifacts, 'manifest.json'), {llvm_sha: component.source.commit,
      sha256: await fileDigest(path.join(artifacts, library)), platform: component.config.target, library,
      targets: options.targets.split(';'), producer: {version: component.producer.version, buildId: request.identity.buildId}});
    await run(['python3', path.join(component.producer.repository, 'ci/llvm-dylib/verify.py'), artifacts, component.source.commit,
      await fileDigest(path.join(artifacts, library))], {env: {...process.env,
        LLVM_NM: path.join(build, 'bin', 'llvm-nm'),
        LD_LIBRARY_PATH: path.join(runtime.artifacts, 'install/runtime/lib', PLATFORMS[component.config.target][2])}});
  } else {
    const compiler = await fetchIdentity(options.compilerSource, path.join(directory, 'source-inputs', 'compiler'), 'llvm-schema');
    const flatbuffers = await fetchIdentity(options.flatbuffersSource, path.join(directory, 'source-inputs', 'flatbuffers'), 'flatbuffers');
    const flatBuild = path.join(directory, 'build', 'flatbuffers');
    await run(['cmake', '-G', 'Ninja', '-S', flatbuffers, '-B', flatBuild, '-DFLATBUFFERS_BUILD_TESTS=OFF',
      `-DCMAKE_C_COMPILER=${tool('clang')}`, `-DCMAKE_CXX_COMPILER=${tool('clang++')}`, `-DCMAKE_MAKE_PROGRAM=${tool('ninja')}`,
      '-DFLATBUFFERS_BUILD_FLATLIB=OFF', '-DFLATBUFFERS_BUILD_SHAREDLIB=OFF',
      ...(options.launcher ? [`-DCMAKE_C_COMPILER_LAUNCHER=${options.launcher}`, `-DCMAKE_CXX_COMPILER_LAUNCHER=${options.launcher}`] : [])]);
    await run(['cmake', '--build', flatBuild, '--target', 'flatc', '-j', String(os.availableParallelism())]);
    const generated = path.join(directory, 'build', 'generated'); await fs.mkdir(path.join(generated, 'flatbuffers'), {recursive: true});
    await run([path.join(flatBuild, 'flatc'), '--no-warnings', '-c', '-o', path.join(generated, 'flatbuffers'), path.join(compiler, 'schema/ModuleFormat.fbs')]);
    const fixed = path.join(artifacts, 'fixed-llc'); await fs.mkdir(fixed, {recursive: true});
    await run([...(options.launcher ? [options.launcher] : []), tool('clang++'), '-std=c++17', '-O2', '-fPIC', '-fno-rtti', '-fno-exceptions',
      `-I${source}/llvm/include`, `-I${build}/include`, `-I${flatbuffers}/include`, `-I${generated}`,
      '-c', path.join(component.producer.repository, 'runtime_shim/cjselfhost_llvmshim.cpp'), '-o', path.join(fixed, 'cjselfhost_llvmshim.o')]);
    const lld = component.config.target.startsWith('darwin_') ? 'ld64.lld' : 'ld.lld';
    const values = {PLATFORM: component.config.target, LLVM_SHA: component.source.commit,
      CANGJIE_COMPILER_SHA: options.compilerSource.commit, FLATBUFFERS_SHA: options.flatbuffersSource.commit};
    await fs.mkdir(path.join(artifacts, 'bin')); await fs.mkdir(path.join(artifacts, 'lib'));
    for (const [tool, prefix] of [['llc', 'LLC'], ['opt', 'OPT'], [lld, 'LLD']]) {
      const binary = path.join(build, 'bin', tool);
      const version = (await execute(binary, ['--version'])).stdout.split('\n').map(line => line.trim()).find(line => /LLVM version |^LLD /.test(line));
      if (!version) reject('LLVM_VERSION', component.id, tool);
      values[`${prefix}_SOURCE`] = `tuple:${component.source.commit}`;
      values[`${prefix}_VERSION`] = version; values[`${prefix}_SHA256`] = await fileDigest(binary);
      await fs.copyFile(binary, path.join(artifacts, 'bin', tool)); await fs.chmod(path.join(artifacts, 'bin', tool), 0o755);
      await fs.writeFile(path.join(fixed, `${tool}.gz`), gzipSync(await fs.readFile(binary), {level: 9}));
    }
    const readers = {};
    for (const name of ['llvm-dis', 'llvm-as']) {
      const destination = path.join(artifacts, 'bin', name);
      await fs.copyFile(path.join(build, 'bin', name), destination); await fs.chmod(destination, 0o755);
      readers[name] = {sha256: await fileDigest(destination), version: (await execute(destination, ['--version'])).stdout.trim()};
    }
    await atomicJson(path.join(artifacts, 'bitcode-readers.json'), {source: component.source, targets: ['llvm-dis', 'llvm-as'],
      tools: readers, producer: component.producer, buildId: request.identity.buildId});
    values.LLD_TOOL = lld; values.SHIM_SHA256 = await fileDigest(path.join(fixed, 'cjselfhost_llvmshim.o'));
    const text = Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join('');
    parseLlvmToolsManifest(text); await fs.writeFile(path.join(fixed, 'llvm-tools.manifest'), text);
    const manifest = `PLATFORM=${component.config.target}\nLLVM_SHA=${component.source.commit}\nCANGJIE_COMPILER_SHA=${options.compilerSource.commit}\nRECIPE_CJCJ_SHA=${component.producer.version}\nDEPOT_ROLE=producer output\n`;
    await fs.writeFile(path.join(artifacts, 'MANIFEST'), manifest); await fs.writeFile(path.join(artifacts, 'lib/STATIC_LLVM.txt'), manifest);
    const payloads = ['bin/llvm-dis', 'bin/llvm-as', 'bitcode-readers.json', 'MANIFEST', `bin/${lld}`, 'bin/llc', 'bin/opt', 'lib/STATIC_LLVM.txt', 'fixed-llc/llc.gz', 'fixed-llc/opt.gz',
      `fixed-llc/${lld}.gz`, 'fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/llvm-tools.manifest'];
    await fs.writeFile(path.join(artifacts, 'SHA256SUMS'), (await Promise.all(payloads.map(async rel => `${await fileDigest(path.join(artifacts, rel))}  ./${rel}\n`))).join(''));
    await sourceIdentity(compiler, options.compilerSource, 'llvm-schema', tool('git')); await sourceIdentity(flatbuffers, options.flatbuffersSource, 'flatbuffers', tool('git'));
  }
  await sourceIdentity(paired, runtime.component.source, 'llvm-runtime', tool('git'));
}
async function std(request) {
  const {component, source, directory, dependencies} = request, options = component.config.options;
  optionsOnly(options, ['sdkDependency', 'compilerDependency', 'runtimeDependency', 'llvmToolsDependency', 'llvmDylibDependency',
    'astDependency', 'heap', 'targetLibRelative', 'launcher', 'llvmAuxiliaryDependency', 'compilerRuntime', 'previousStdDependency', 'provenance'], component.id);
  const seed = dependencies[options.sdkDependency], compiler = dependencies[options.compilerDependency], runtime = dependencies[options.runtimeDependency];
  if (!seed?.component.roles.includes('official-host') || !compiler?.component.roles.includes('compiler')
    || !runtime?.component.roles.includes('runtime')) reject('PRODUCER_DEPENDENCY', component.id, 'std needs explicit host seed/compiler/target runtime');
  const sdk = path.join(directory, 'build', 'sdk'); await fs.mkdir(sdk, {recursive: true});
  await fs.cp(seed.artifacts, sdk, {recursive: true, dereference: false});
  if (options.previousStdDependency) {
    const previous = dependencies[options.previousStdDependency];
    if (!previous?.component.roles.includes('std')) reject('PRODUCER_DEPENDENCY', component.id, 'full previous std receipt required');
    await fs.cp(previous.artifacts, sdk, {recursive: true, dereference: false, verbatimSymlinks: true, force: true});
  }
  // This is a target backend installation, not an overlay on host LLVM.
  // Leaving the official llvm-ar/other dynamic tools beside the target
  // libLLVM lets CMake select an incompatible archiver by PATH. Native
  // binutils come from the separately frozen tool inputs below.
  await fs.rm(path.join(sdk, 'third_party/llvm'), {recursive: true, force: true});
  const compilerFile = path.join(compiler.artifacts, 'bin/cjcj-stage1');
  await run(['python3', '-B', path.join(here, 'compiler_identity.py'), sdk, '--install', compilerFile]);
  const tuple = PLATFORMS[component.config.target][2];
  const targetLib = path.join(runtime.artifacts, options.targetLibRelative || '');
  const hostRuntime = path.join(seed.artifacts, 'runtime/lib', tuple);
  if (!/^\d+GB$/.test(options.heap || '')) reject('PRODUCER_OPTIONS', component.id, 'explicit compiler heap');
  const frozenTools = path.join(directory, 'build', 'frozen-tools'); await fs.mkdir(frozenTools, {recursive: true});
  for (const [name, input] of Object.entries(component.config.tools)) {
    const destination = path.join(frozenTools, name);
    try { await fs.symlink(input.path, destination); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const env = {...process.env, CANGJIE_HOME: sdk, PATH: `${sdk}/bin:${sdk}/tools/bin:${sdk}/third_party/llvm/bin:${frozenTools}:/usr/bin:/bin`,
    CC: tool('clang'), CXX: tool('clang++'), AR: tool('ar'),
    LD_LIBRARY_PATH: `${options.compilerRuntime === 'target' ? path.join(runtime.artifacts, options.targetLibRelative, 'runtime/lib', tuple) : hostRuntime}:${sdk}/third_party/llvm/lib:${sdk}/tools/lib`, cjHeapSize: options.heap,
    TMPDIR: path.join(directory, 'build', 'tmp'), CANGJIE_BUILD_JOBS: String(os.availableParallelism()), CMAKE_BUILD_PARALLEL_LEVEL: String(os.availableParallelism())};
  if (options.launcher) {
    env.CMAKE_C_COMPILER_LAUNCHER = options.launcher;
    env.CMAKE_CXX_COMPILER_LAUNCHER = options.launcher;
  }
  await fs.mkdir(env.TMPDIR, {recursive: true});
  // Native backend tools and the in-process library must come from the same
  // explicit target LLVM output. Managed compiler loading keeps host runtime.
  for (const [dependencyName, destination] of [[options.llvmToolsDependency, 'third_party/llvm'], [options.llvmDylibDependency, 'third_party/llvm/lib']]) {
    const dependency = dependencies[dependencyName]; if (!dependency) reject('PRODUCER_DEPENDENCY', component.id, dependencyName);
    await fs.cp(dependency.artifacts, path.join(sdk, destination), {recursive: true, dereference: false, force: true});
  }
  if (options.llvmAuxiliaryDependency) {
    const auxiliary = dependencies[options.llvmAuxiliaryDependency];
    if (!auxiliary?.component.config.options.auxiliaryOnly) reject('PRODUCER_DEPENDENCY', component.id, 'declared auxiliary LLVM producer');
    await fs.cp(path.join(auxiliary.artifacts, 'bin'), path.join(sdk, 'third_party/llvm/bin'), {recursive: true, dereference: false, force: true});
  }
  const ast = dependencies[options.astDependency]; if (!ast) reject('PRODUCER_DEPENDENCY', component.id, options.astDependency);
  await run(['python3', path.join(component.producer.repository, 'ci/install_std_sdk_inputs.py'), ast.artifacts, sdk, tuple]);
  // Preserve bootstrap_target_std's first-probe common layout. The target
  // pair must be found before build.py can fall back to the host SDK.
  const link = path.join(directory, 'build', 'std-runtime-link');
  const arch = component.config.target.slice('linux_'.length);
  const common = path.join(link, 'common', `linux_relwithdebinfo_${arch}`);
  const native = path.join(common, 'lib', tuple), dynamic = path.join(common, 'runtime/lib', tuple);
  await fs.mkdir(native, {recursive: true}); await fs.mkdir(dynamic, {recursive: true});
  for (const file of ['libcangjie-aio.a', 'cjstart.o', 'cjld.shared.lds', 'discard_eh_frame.lds']) {
    await fs.copyFile(path.join(sdk, 'lib', tuple, file), path.join(native, file));
  }
  const dynamicSource = await fs.stat(path.join(targetLib, 'runtime/lib', tuple)).then(() => path.join(targetLib, 'runtime/lib', tuple)).catch(error => {
    if (error.code !== 'ENOENT') throw error; return targetLib;
  });
  for (const file of ['libcangjie-runtime.so', 'libboundscheck.so']) await fs.copyFile(path.join(dynamicSource, file), path.join(dynamic, file));
  const stdlib = path.join(source, 'stdlib');
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  await run(['python3', 'build.py', 'build', '-t', 'relwithdebinfo', '--jobs', String(os.availableParallelism()), `--target-lib=${link}`], {cwd: stdlib, env});
  await run(['python3', 'build.py', 'install', '--prefix', artifacts], {cwd: stdlib, env});
  // AddCangjieSource.cmake installs package CJO/bitcode, not a synthetic
  // per-type .ti tree. Require the actual core module and both native forms.
  for (const rel of [`modules/${tuple}/std/std.core.cjo`, `modules/${tuple}/std/libstd.core.bc`,
    `lib/${tuple}/libcangjie-std-core.a`, `runtime/lib/${tuple}/libcangjie-std-core.so`, 'lib/libstdFFI.so']) {
    if (!(await fs.stat(path.join(artifacts, rel))).isFile()) reject('STD_INSTALL_SHAPE', component.id, rel);
  }
  await atomicJson(path.join(artifacts, 'std-producer.json'), {compiler_sha256: await fileDigest(compilerFile),
    compiler_build_id: compiler.buildId, runtime_build_id: runtime.buildId, source_commit: component.source.commit,
    source_tree: component.source.tree, stage: 'completed-std', producer: component.producer});
  if (options.provenance) await writeStdProvenance({sourceDir: stdlib, installPrefix: artifacts, buildSdk: sdk, compiler: compilerFile});
}
async function llvmReleaseLayout(request) {
  const {component, dependencies, directory, source} = request;
  const options = component.config.options;
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  const inputs = {};
  async function copyDependency(key, prefix = '', omit = []) {
    const output = dependencies[options[key]];
    if (!output || output.component.source.commit !== component.source.commit
      || output.component.config.host !== component.config.host || output.component.config.target !== component.config.target) {
      reject('PRODUCER_DEPENDENCY', component.id, `paired LLVM source/host/target required: ${key}`);
    }
    inputs[key] = {buildId: output.buildId, receiptSha256: output.receiptSha256};
    for (const [rel, row] of Object.entries(output.files)) {
      if (omit.includes(rel)) continue;
      const input = path.join(output.artifacts, rel), target = path.join(artifacts, prefix, rel);
      if (await fileDigest(input) !== row.sha256) reject('DEPENDENCY_DIGEST', component.id, `${key}/${rel}`);
      await fs.mkdir(path.dirname(target), {recursive: true});
      try { await fs.lstat(target); reject('PRODUCER_DEPENDENCY', component.id, `duplicate export ${prefix}/${rel}`); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (row.type === 'symlink') {
        if (await fs.readlink(input) !== row.target) reject('DEPENDENCY_DIGEST', component.id, `${key}/${rel} link`);
        await fs.symlink(row.target, target);
      } else { await fs.copyFile(input, target); await fs.chmod(target, row.mode); }
    }
  }
  await copyDependency('toolsDependency');
  await copyDependency('dylibDependency', 'lib');
  await copyDependency('auxiliaryDependency');
  await copyDependency('readersDependency');
  // The fixed bootstrap checksum tuple authenticates the old lld bytes.
  // Reuse that native executable as the release graph's canonical lld name;
  // its ld.lld alias still hashes to the exact bootstrap tuple member.
  await fs.rename(path.join(artifacts, 'bin/ld.lld'), path.join(artifacts, 'bin/lld'));
  await fs.symlink('lld', path.join(artifacts, 'bin/ld.lld'));
  await copyDependency('releaseDependency', '', ['bin/lld', 'bin/ld.lld', 'bin/ld64.lld', 'bin/lld-link']);
  const lldGraph = await fs.readFile(path.join(source, 'lld/tools/lld/CMakeLists.txt'), 'utf8');
  if (!lldGraph.includes('lld-link ld.lld ld64.lld wasm-ld')) reject('SOURCE', component.id, 'release lld alias graph changed');
  for (const alias of ['ld64.lld', 'lld-link']) await fs.symlink('lld', path.join(artifacts, 'bin', alias));
  const cmake = await fs.readFile(path.join(source, 'llvm/CMakeLists.txt'), 'utf8');
  const version = ['MAJOR', 'MINOR', 'PATCH'].map(part => cmake.match(new RegExp(`set\\(LLVM_VERSION_${part} ([0-9]+)\\)`))?.[1]);
  if (version.some(part => !part)) reject('SOURCE', component.id, 'LLVM source version required');
  for (const alias of [`libLLVM-${version.join('.')}.so`, 'libLLVM.so']) await fs.symlink(`libLLVM-${version[0]}.so`, path.join(artifacts, 'lib', alias));
  if (options.librariesDependency) await copyDependency('librariesDependency');
  const readerInput = dependencies[options.readersDependency];
  const readerFile = path.join(artifacts, 'bitcode-readers.json');
  const readerRecord = await readJson(readerFile);
  const {receipt, receiptSha256, originBuildRoot, ...readerProducer} = readerInput.component.producer;
  if (canonical(readerRecord.source) !== canonical(readerInput.component.source)
    || canonical(readerRecord.producer) !== canonical(readerProducer) || readerRecord.buildId !== readerInput.buildId
    || canonical(readerRecord.targets) !== canonical(['llvm-dis', 'llvm-as'])) reject('LLVM_READERS', component.id, 'input reader provenance differs');
  for (const name of readerRecord.targets) if (readerRecord.tools[name]?.sha256 !== readerInput.files[`bin/${name}`]?.sha256) reject('LLVM_READERS', component.id, `input reader digest differs: ${name}`);
  await atomicJson(readerFile, {...readerRecord, source: component.source, producer: component.producer,
    buildId: request.identity.buildId, origin: {record: readerRecord, receiptSha256: readerInput.receiptSha256}});
  const sumsFile = path.join(artifacts, 'SHA256SUMS');
  const originalSums = await fs.readFile(sumsFile, 'utf8');
  for (const line of originalSums.trimEnd().split('\n')) {
    const match = line.match(/^([a-f0-9]{64})  (?:\.\/)?(.+)$/);
    if (!match || await fileDigest(path.join(artifacts, match[2])) !== match[1]) reject('DEPENDENCY_DIGEST', component.id, 'fixed bootstrap tuple changed during release layout');
  }
  const readers = ['bin/llvm-dis', 'bin/llvm-as', 'bitcode-readers.json'];
  await fs.writeFile(sumsFile, originalSums + (await Promise.all(readers.map(async rel => `${await fileDigest(path.join(artifacts, rel))}  ./${rel}\n`))).join(''));
  await atomicJson(path.join(artifacts, 'release-layout.json'), {source: component.source, inputs,
    version: version.join('.'), host: component.config.host, target: component.config.target,
    producer: component.producer, buildId: request.identity.buildId});
}
async function astSupport(request) {
  const {component, source, directory, dependencies} = request, options = component.config.options;
  optionsOnly(options, ['sdkDependency', 'flatbuffersSource', 'launcher', 'flatbuffersTransform'], component.id);
  const seed = dependencies[options.sdkDependency];
  if (seed?.component.source.kind !== 'distribution' || seed.component.domain !== 'host') reject('PRODUCER_DEPENDENCY', component.id, 'AST needs the declared official FlatBuffers SDK');
  // This subset crosses the existing AST install boundary unchanged. Bind
  // membership and bytes to the seed receipt before the legacy producer can
  // issue a new checksum list; never rescan the entire host SDK here.
  const prefix = 'third_party/flatbuffers/';
  const expected = Object.fromEntries(Object.entries(seed.files).filter(([rel]) => rel.startsWith(prefix))
    .map(([rel, row]) => [rel.slice(prefix.length), row]));
  if (!Object.keys(expected).length || canonical(await inventory(path.join(seed.artifacts, 'third_party/flatbuffers'))) !== canonical(expected)) {
    reject('DEPENDENCY_DIGEST', component.id, 'official FlatBuffers subset differs from its presealed producer inventory');
  }
  // This is the existing AST workflow's pinned nested source input.
  const flatbuffers = await fetchIdentity(options.flatbuffersSource, path.join(source, 'third_party/flatbuffers'), 'ast-flatbuffers');
  let transformation;
  if (options.flatbuffersTransform !== undefined) {
    if (options.flatbuffersTransform !== 'cangjie-package-mapping-v1') reject('SOURCE_TRANSFORM', component.id, 'unknown transformation');
    // The pinned compiler's ExternalProject PATCH_COMMAND modifies this one
    // file. Derive and record its exact expected result before building; do
    // not infer permitted changes from whatever the producer leaves behind.
    const rel = 'src/idl_gen_cangjie.cpp', original = path.join(flatbuffers, rel);
    const script = path.join(source, 'third_party/cmake/ApplyCangjieIdlPackagePatch.cmake');
    const expectedRoot = path.join(directory, 'build', 'registered-flatbuffers');
    const expectedFile = path.join(expectedRoot, rel);
    await fs.mkdir(path.dirname(expectedFile), {recursive: true});
    await fs.copyFile(original, expectedFile);
    await run(['cmake', `-DFLATBUFFERS_SRC=${expectedRoot}`, '-P', script]);
    transformation = {name: options.flatbuffersTransform, script: {source: component.source, path: 'third_party/cmake/ApplyCangjieIdlPackagePatch.cmake', sha256: await fileDigest(script)},
      input: {source: options.flatbuffersSource, path: rel, sha256: await fileDigest(original)},
      changes: {[rel]: {sha256: await fileDigest(expectedFile), mode: (await fs.stat(original)).mode & 0o777}}};
    if (transformation.input.sha256 === transformation.changes[rel].sha256) reject('SOURCE_TRANSFORM', component.id, 'declared transformation did not change the original');
    await atomicJson(path.join(directory, 'logs', 'registered-source-transform.json'), transformation);
  }
  const frozenTools = path.join(directory, 'build', 'ast-tools'); await fs.mkdir(frozenTools, {recursive: true});
  for (const [name, input] of Object.entries(component.config.tools)) {
    const destination = path.join(frozenTools, name);
    try { await fs.symlink(input.path, destination); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const artifacts = path.join(directory, 'artifacts');
  const env = {...process.env, PATH: `${frozenTools}:/usr/bin:/bin`, NM: tool('nm')};
  if (options.launcher) {
    env.CMAKE_C_COMPILER_LAUNCHER = options.launcher;
    env.CMAKE_CXX_COMPILER_LAUNCHER = options.launcher;
  }
  await run(['bash', path.join(component.producer.repository, 'ci/build_ast_support.sh'), source,
    path.join(directory, 'build', 'ast'), artifacts, seed.artifacts], {env});
  for (const rel of ['libcangjie-ast-support.a', 'include/cangjie', 'include/flatbuffers/StdAstFormat_generated.h',
    'schema/StdAstFormat.fbs', 'schema/StdxChirFormat.fbs', 'third_party/flatbuffers/bin/flatc', 'SHA256SUMS']) {
    await fs.access(path.join(artifacts, rel));
  }
  const flatbuffersAfter = transformation
    ? await registeredSourceIdentity(flatbuffers, options.flatbuffersSource, 'ast-flatbuffers', transformation.changes, tool('git'))
    : await sourceIdentity(flatbuffers, options.flatbuffersSource, 'ast-flatbuffers', tool('git'));
  await atomicJson(path.join(artifacts, 'ast-producer.json'), {source: component.source,
    flatbuffers: options.flatbuffersSource, flatbuffersAfter, transformation, official_sdk_build_id: seed.buildId,
    producer: component.producer, buildId: request.identity.buildId});
}
export async function nativeProducer(request) {
  activeRequest = request;
  const {component} = request;
  const platform = PLATFORMS[component.config.host];
  if (!platform || platform[0] !== process.platform || platform[1] !== process.arch) reject('PRODUCER_PLATFORM', component.id, `needs ${component.config.host}`);
  if (os.availableParallelism() < 64 && process.env.GITHUB_ACTIONS !== 'true') reject('PRODUCER_RESOURCES', component.id, 'at least 64 native build CPUs');
  if (process.env.GITHUB_ACTIONS === 'true' && !component.producer.receipt
    && (!component.config.options.launcher || !/^sccache(?:\.exe)?$/.test(path.basename(component.config.options.launcher)))) {
    reject('PRODUCER_CACHE', component.id, 'official GHA native C++ builds require a frozen sccache launcher');
  }
  await sourceIdentity(request.source, component.source, component.id, tool('git'));
  if (component.producer.adapter === 'bootstrap-std') await std(request);
  else if (component.producer.adapter === 'llvm-release-layout') await llvmReleaseLayout(request);
  else if (component.producer.adapter === 'compiler-schema') {
    const schemas = ['StdAstFormat.fbs', 'StdxChirFormat.fbs'];
    const artifacts = path.join(request.directory, 'artifacts');
    await fs.mkdir(path.join(artifacts, 'schema'), {recursive: true});
    for (const name of schemas) await fs.copyFile(path.join(request.source, 'schema', name), path.join(artifacts, 'schema', name));
    await atomicJson(path.join(artifacts, 'schema-producer.json'), {source: component.source, schemas,
      host: component.config.host, target: component.config.target, producer: component.producer, buildId: request.identity.buildId});
  }
  else if (component.producer.adapter === 'bootstrap-compiler') await buildStageCompiler(request, run);
  else if (component.producer.adapter === 'ast-support') await astSupport(request);
  else if (['llvm-tools', 'llvm-dylib'].includes(component.producer.adapter)) await llvm(request);
  else reject('ADAPTER', component.id, component.producer.adapter);
  if (component.producer.adapter === 'bootstrap-compiler') {
    await registeredSourceIdentity(request.source, component.source, component.id,
      (await readJson(path.join(request.directory, 'native-execution.json'))).sourceChanges, tool('git'));
  } else await sourceIdentity(request.source, component.source, component.id, tool('git'));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await nativeProducer(await readJson(process.argv[2])); }
  catch (error) { console.error(error.message); process.exitCode = Number.isInteger(error.rc) && error.rc > 0 ? error.rc : 1; }
}
