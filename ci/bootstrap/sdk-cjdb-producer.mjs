// Build the fixed compiler's complete CJDB graph. Its ExternalProjects own
// LLVM, frontend/LSP, LLDB, Python bindings and the installed cjdb link.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileDigest, readJson, atomicJson, inventory, sourceIdentity, registeredSourceIdentity, reject} from './sdk-manifest.mjs';

export async function buildCjdb(request, {run, tool, fetchIdentity, execute: requestExecute}) {
  const {component, source: llvmReference, directory, dependencies} = request;
  const options = component.config.options;
  const llvm = await fetchIdentity({...component.source, repo: llvmReference}, path.join(directory, 'source-inputs/llvm'), 'cjdb-llvm');
  const runtime = dependencies[options.runtimeDependency];
  if (runtime?.component.source.kind !== 'git' || !runtime.component.roles.includes('runtime')) reject('PRODUCER_DEPENDENCY', component.id, 'paired runtime Git source required');
  const paired = await fetchIdentity(runtime.component.source, path.join(directory, 'source-inputs/runtime'), 'cjdb-runtime');
  const compiler = await fetchIdentity(options.compilerSource, path.join(directory, 'source-inputs/compiler'), 'cjdb-compiler');
  const bounds = await fetchIdentity(options.boundscheckSource, path.join(compiler, 'third_party/boundscheck'), 'cjdb-boundscheck');
  const flatbuffers = await fetchIdentity(options.flatbuffersSource, path.join(compiler, 'third_party/flatbuffers'), 'cjdb-flatbuffers');
  const python = await readJson(options.python.receipt);
  if (await fileDigest(options.python.receipt) !== options.python.sha256 || python.schema !== 'cjcj-python-dependency-v1'
    || python.status !== 'complete' || python.rc !== 0 || python.host !== component.config.host || python.source.version !== '3.11.17') reject('DEPENDENCY_DIGEST', component.id, 'complete actual private Python receipt required');
  for (const [rel, row] of Object.entries(python.files)) if (await fileDigest(path.join(options.python.root, rel)) !== row.sha256) reject('DEPENDENCY_DIGEST', component.id, `Python ${rel}`);
  await run([path.join(options.python.root, 'bin/python3.11'), '-c', 'import sys,sysconfig,ssl,_ctypes; assert sys.version_info[:2] == (3,11); print(sys.version); print(sysconfig.get_path("include"))']);
  const libedit = options.libedit;
  for (const [rel, row] of Object.entries(libedit.files)) if (await fileDigest(path.join(libedit.root, rel)) !== row.sha256) reject('DEPENDENCY_DIGEST', component.id, `libedit ${rel}`);
  await run(['swig', '-version']);
  const archive = options.xml2Archive;
  if (await fileDigest(archive.path) !== archive.sha256) reject('DEPENDENCY_DIGEST', component.id, 'XML2 source archive');
  const xml2 = path.join(directory, 'source-inputs/xml2'); await fs.mkdir(xml2, {recursive: true});
  await run(['tar', '-xJf', archive.path, '--strip-components=1', '-C', xml2]);
  // Precompute the two source edits made by the unchanged compiler recipes.
  // Their expected bytes are registered before CMake can touch the inputs.
  const boundsRel = 'CMakeLists.txt';
  const boundsChanges = {[boundsRel]: {sha256: await fileDigest(path.join(compiler, 'third_party/cmake/BoundsCheck.cmake')), mode: (await fs.stat(path.join(bounds, boundsRel))).mode & 0o777}};
  const flatRel = 'src/idl_gen_cangjie.cpp', projection = path.join(directory, 'build/flatbuffers-transform');
  await fs.mkdir(path.join(projection, 'src'), {recursive: true});
  await fs.copyFile(path.join(flatbuffers, flatRel), path.join(projection, flatRel));
  await run(['cmake', `-DFLATBUFFERS_SRC=${projection}`, '-P', path.join(compiler, 'third_party/cmake/ApplyCangjieIdlPackagePatch.cmake')]);
  const flatChanges = {[flatRel]: {sha256: await fileDigest(path.join(projection, flatRel)), mode: (await fs.stat(path.join(flatbuffers, flatRel))).mode & 0o777}};
  await atomicJson(path.join(directory, 'logs/registered-source-transforms.json'), {boundsChanges, flatChanges});
  const build = path.join(directory, 'build/compiler'), installed = path.join(directory, 'build/install');
  const launcher = tool('launcher'), jobs = String(os.availableParallelism());
  const prefix = [options.python.root, libedit.root, path.join(build, 'third_party/xml2')].join(';');
  const llvmArgs = [`-DCANGJIE_RUNTIME_SOURCE_DIR=${paired}`, `-DCMAKE_C_COMPILER_LAUNCHER=${launcher}`, `-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher}`,
    '-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string', '-DLLVM_PARALLEL_LINK_JOBS=8'];
  const env = {...process.env, PATH: `${path.join(options.python.root, 'bin')}:/usr/lib/ccache:/usr/bin:/bin`,
    CCACHE_DIR: '/root/.ccache', CCACHE_BASEDIR: directory, CCACHE_NOHASHDIR: '1', CMAKE_BUILD_PARALLEL_LEVEL: jobs,
    LD_LIBRARY_PATH: `${path.join(options.python.root, 'lib')}:${path.join(libedit.root, 'lib/x86_64-linux-gnu')}`};
  await run(['cmake', '-G', 'Ninja', '-S', compiler, '-B', build, '-DCMAKE_BUILD_TYPE=Release',
    `-DCMAKE_TOOLCHAIN_FILE=${path.join(compiler, 'cmake/linux_toolchain.cmake')}`, `-DCMAKE_C_COMPILER=${tool('clang')}`, `-DCMAKE_CXX_COMPILER=${tool('clang++')}`,
    `-DCMAKE_MAKE_PROGRAM=${tool('ninja')}`, `-DCMAKE_C_COMPILER_LAUNCHER=${launcher}`, `-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher}`,
    '-DCANGJIE_BUILD_CJC=ON', '-DCANGJIE_BUILD_STD_SUPPORT=ON', '-DCANGJIE_BUILD_TESTS=OFF', '-DCANGJIE_BUILD_CJDB=ON',
    '-DCANGJIE_LLVM_BUILD_TYPE=Release', '-DCANGJIE_CJDB_BUILD_TYPE=Release', `-DCANGJIE_CJNATIVE_SOURCE_DIR=${llvm}`,
    `-DCANGJIE_RUNTIME_SOURCE_DIR=${paired}`, `-DCANGJIE_XML2_SOURCE_DIR=${xml2}`, `-DCMAKE_PREFIX_PATH=${prefix}`,
    `-DPython3_EXECUTABLE=${path.join(options.python.root, 'bin/python3.11')}`, `-DCANGJIE_LLVM_BUILD_ARGS=${llvmArgs.join(';')}`,
    '-DCANGJIE_LINK_JOB_POOL=8', `-DCMAKE_INSTALL_PREFIX=${installed}`], {env});
  // Query the real graph before production; no hand-maintained object subset.
  await run(['ninja', '-C', build, '-t', 'query', 'lldb'], {env});
  await run(['cmake', '--build', build, '--target', 'lldb', 'cjdb', 'lldb-boundscheck', 'lldb-cangjie-lsp', 'lldb-cangjie-frontend', '-j', jobs], {env});
  // The normal compiler install includes compiler utilities as well. Build
  // these through the same graph before invoking its complete install rules.
  await run(['cmake', '--build', build, '-j', jobs], {env});
  await run(['cmake', '--install', build], {env});
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  // Export whole native installation roots, preserving every native alias and
  // Python module. The SDK plan decides ownership outside these roots.
  for (const rel of ['third_party/llvm', 'tools']) {
    await fs.mkdir(path.dirname(path.join(artifacts, rel)), {recursive: true});
    await fs.cp(path.join(installed, rel), path.join(artifacts, rel), {recursive: true, verbatimSymlinks: true, preserveTimestamps: true});
  }
  // BuildCJDB's installed links point to the canonical runtime boundscheck.
  const runtimeRel = 'runtime/lib/linux_x86_64_cjnative'; await fs.mkdir(path.join(artifacts, runtimeRel), {recursive: true});
  await fs.copyFile(path.join(build, 'lib/libboundscheck.so'), path.join(artifacts, runtimeRel, 'libboundscheck.so'));
  await fs.copyFile(path.join(build, 'lib/libboundscheck.so'), path.join(artifacts, runtimeRel, 'libsecurec.so'));
  // Keep the complete raw LLDB installation (including IntelFeatures) sealed;
  // install any native library omitted by the parent compiler's broad rules.
  const rawLldb = path.join(build, 'third_party/lldb');
  for (const [rel] of Object.entries(await inventory(rawLldb, {links: true}))) {
    if (!rel.startsWith('lib/') || rel.startsWith('lib/python')) continue;
    const from = path.join(rawLldb, rel), to = path.join(artifacts, 'third_party/llvm', rel);
    try { await fs.lstat(to); } catch (e) { if(e.code!=='ENOENT')throw e; await fs.mkdir(path.dirname(to), {recursive:true}); const st=await fs.lstat(from); if(st.isSymbolicLink())await fs.symlink(await fs.readlink(from),to); else await fs.copyFile(from,to); }
  }
  await fs.mkdir(path.join(artifacts, 'native-closure'), {recursive: true});
  await fs.cp(rawLldb, path.join(artifacts, 'native-closure/lldb'), {recursive: true, verbatimSymlinks: true});
  await fs.cp(options.python.root, path.join(artifacts, 'native-closure/python'), {recursive: true, verbatimSymlinks: true});
  const boundsAfter = await registeredSourceIdentity(bounds, options.boundscheckSource, 'cjdb-boundscheck', boundsChanges, tool('git'));
  const flatAfter = await registeredSourceIdentity(flatbuffers, options.flatbuffersSource, 'cjdb-flatbuffers', flatChanges, tool('git'));
  const generatedInputs = {
    'utils/demangle/CangjieDemangle.h': path.join(build, 'cangjie-demangler/include/CangjieDemangle.h'),
    'utils/demangle/libcangjie-demangle.a': path.join(build, 'cangjie-demangler/lib/libcangjie-demangle.a'),
    'utils/boundscheck/include/securec.h': path.join(bounds, 'include/securec.h'),
    'utils/boundscheck/include/securectype.h': path.join(bounds, 'include/securectype.h'),
    'utils/boundscheck/lib/x86_64/libboundscheck.so': path.join(build, 'lib/libboundscheck.so'),
  };
  const generated = {};
  for (const [rel, input] of Object.entries(generatedInputs)) {
    const sha256 = await fileDigest(input);
    if (await fileDigest(path.join(llvm, rel)) !== sha256) reject('DEPENDENCY_DIGEST', component.id, `native PATCH_COMMAND input ${rel}`);
    generated[rel] = {input, sha256};
  }
  const status = (await requestExecute(tool('git'), ['-C', llvm, 'status', '--porcelain', '-z', '--untracked-files=all'])).stdout.split('\0').filter(Boolean).sort();
  if (JSON.stringify(status) !== JSON.stringify(Object.keys(generated).map(rel => `?? ${rel}`).sort())) reject('SOURCE_TRANSFORM', component.id, `unexpected native generated source changes ${JSON.stringify(status)}`);
  await sourceIdentity(compiler, options.compilerSource, 'cjdb-compiler', tool('git'));
  await sourceIdentity(paired, runtime.component.source, 'cjdb-runtime', tool('git'));
  await atomicJson(path.join(artifacts, 'cjdb-producer.json'), {source: component.source, compiler: options.compilerSource, runtime: runtime.component.source,
    boundsAfter, flatAfter, generated, python: options.python, libedit, xml2: archive, producer: component.producer, buildId: request.identity.buildId,
    entry: 'CANGJIE_BUILD_CJDB', targets: ['lldb','cjdb'], build, installed, jobs:Number(jobs), rtti:true});
}
