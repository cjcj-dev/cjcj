// Build the fixed compiler's complete CJDB graph. Its ExternalProjects own
// LLVM, frontend/LSP, LLDB, Python bindings and the installed cjdb link.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {gzipSync} from 'node:zlib';
import {fileDigest, readJson, atomicJson, inventory, sourceIdentity, registeredSourceIdentity, reject} from './sdk-manifest.mjs';
import {parseLlvmToolsManifest} from '../llvm-tools-manifest.mjs';
import {prepareQualification, qualifyGeneratedInputs, CJDB_QUALIFICATION} from './sdk-cjdb-qualification.mjs';

export async function buildCjdb(request, {run, tool, fetchIdentity, execute: requestExecute}) {
  const {component, source: llvmReference, directory, dependencies} = request;
  const options = component.config.options;
  const llvm = await fetchIdentity({...component.source, repo: llvmReference}, path.join(directory, 'source-inputs/llvm'), 'cjdb-llvm');
  const runtime = dependencies[options.runtimeDependency];
  if (runtime?.component.source.kind !== 'git' || !runtime.component.roles.includes('runtime')) reject('PRODUCER_DEPENDENCY', component.id, 'paired runtime Git source required');
  const runtimeSource = options.runtimeSource || runtime.component.source;
  if (runtimeSource.commit !== runtime.component.source.commit || runtimeSource.tree !== runtime.component.source.tree) reject('PRODUCER_DEPENDENCY', component.id, 'runtime source locator differs from sealed dependency');
  const paired = await fetchIdentity(runtimeSource, path.join(directory, 'source-inputs/runtime'), 'cjdb-runtime');
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
  const boundsChanges = {[boundsRel]: {sha256: await fileDigest(path.join(compiler, 'third_party/cmake/BoundsCheck.cmake')), mode: 0o644}};
  const flatRel = 'src/idl_gen_cangjie.cpp', projection = path.join(directory, 'build/flatbuffers-transform');
  await fs.mkdir(path.join(projection, 'src'), {recursive: true});
  await fs.copyFile(path.join(flatbuffers, flatRel), path.join(projection, flatRel));
  await run(['cmake', `-DFLATBUFFERS_SRC=${projection}`, '-P', path.join(compiler, 'third_party/cmake/ApplyCangjieIdlPackagePatch.cmake')]);
  const flatChanges = {[flatRel]: {sha256: await fileDigest(path.join(projection, flatRel)), mode: (await fs.stat(path.join(flatbuffers, flatRel))).mode & 0o777}};
  await atomicJson(path.join(directory, 'logs/registered-source-transforms.json'), {boundsChanges, flatChanges});
  const build = path.join(directory, 'build/compiler'), installed = path.join(directory, 'build/install');
  const qualification = await prepareQualification(request,{llvm,compiler,bounds,build,demangler:path.join(build,'cangjie-demangler')},path.join(directory,'native-qualification'));
  const launcher = tool('launcher'), jobs = String(os.availableParallelism());
  const prefix = [options.python.root, libedit.root, path.join(build, 'third_party/xml2')].join(';');
  const llvmArgs = [`-DCANGJIE_RUNTIME_SOURCE_DIR=${paired}`, `-DCMAKE_C_COMPILER_LAUNCHER=${launcher}`, `-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher}`,
    '-DLLVM_PARALLEL_LINK_JOBS=8', `-DCMAKE_PROJECT_LLVM_INCLUDE_BEFORE=${qualification.hook}`, `-DCJ_LLVM_COMMIT=${component.source.commit}`];
  const env = {...process.env, PATH: `${path.join(options.python.root, 'bin')}:${path.dirname(tool('clang'))}:/usr/lib/ccache:/usr/bin:/bin`,
    CCACHE_DIR: '/root/.ccache', CCACHE_BASEDIR: directory, CCACHE_NOHASHDIR: '1', CMAKE_BUILD_PARALLEL_LEVEL: jobs,
    CMAKE_C_COMPILER_LAUNCHER:launcher, CMAKE_CXX_COMPILER_LAUNCHER:launcher,
    LD_LIBRARY_PATH: `${path.join(options.python.root, 'lib')}:${path.join(libedit.root, 'lib/x86_64-linux-gnu')}`};
  await run(['cmake', '-G', 'Ninja', '-S', compiler, '-B', build, '-DCMAKE_BUILD_TYPE=Release',
    `-DCMAKE_TOOLCHAIN_FILE=${path.join(compiler, 'cmake/linux_x86_64_toolchain.cmake')}`, `-DCMAKE_C_COMPILER=${tool('clang')}`, `-DCMAKE_CXX_COMPILER=${tool('clang++')}`,
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
  // Recheck the same physical source and producer inputs before sealing. The
  // configure-time record cannot be replaced by a post-build observation.
  const postQualification = await qualifyGeneratedInputs(qualification.contractFile,'preseal');
  const certificate = {schema:CJDB_QUALIFICATION,preconfigure:await readJson(path.join(directory,'native-qualification/preconfigure.json')),preseal:postQualification};
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  for(const [rel,row] of Object.entries(postQualification.body.generated)){
    const destination=path.join(artifacts,row.artifact);await fs.mkdir(path.dirname(destination),{recursive:true});
    await fs.copyFile(path.join(llvm,rel),destination);await fs.chmod(destination,row.mode);
  }
  await atomicJson(path.join(artifacts,'native-inputs/qualification.json'),certificate);
  await atomicJson(path.join(directory,'native-execution.json'),{generatedInputs:certificate});
  const llvmBuild = path.join(build, 'third_party/cjnative-prefix/src/cjnative-build');
  const llvmCache = await fs.readFile(path.join(llvmBuild, 'CMakeCache.txt'), 'utf8');
  const cacheValue = name => llvmCache.match(new RegExp(`^${name}:[^=]+=([^\\n]*)$`, 'm'))?.[1];
  if (cacheValue('LLVM_ENABLE_RTTI') !== 'ON' || cacheValue('LLVM_BUILD_LLVM_DYLIB') !== 'ON'
    || cacheValue('LLVM_TARGETS_TO_BUILD') !== 'X86;ARM;AArch64' || cacheValue('CJ_LLVM_COMMIT') !== component.source.commit
    || cacheValue('CMAKE_PROJECT_LLVM_INCLUDE_BEFORE') !== qualification.hook) reject('CJDB_CONFIGURATION', component.id, 'actual native cache must retain RTTI, dylib, baseline, qualification hook and all declared targets');
  // Export whole native installation roots, preserving every native alias and
  // Python module. The SDK plan decides ownership outside these roots.
  await fs.mkdir(path.join(artifacts, 'third_party'), {recursive:true});
  await fs.cp(path.join(build, 'third_party/llvm'), path.join(artifacts, 'third_party/llvm'), {recursive:true, verbatimSymlinks:true, preserveTimestamps:true});
  for (const rel of ['third_party/llvm', 'tools']) {
    await fs.mkdir(path.dirname(path.join(artifacts, rel)), {recursive: true});
    await fs.cp(path.join(installed, rel), path.join(artifacts, rel), {recursive: true, verbatimSymlinks: true, preserveTimestamps: true});
  }
  // The native LLDB install supplies its binding module; its declared Python
  // supplies the interpreter, shared library and standard library. Merge the
  // complete Python install so the relocatable binding keeps working away
  // from the private dependency prefix. Export the actual libedit dependency
  // alongside the native loader's libraries, retaining its relative aliases.
  const nativeRoot = path.join(artifacts, 'third_party/llvm');
  for (const rel of ['bin', 'lib', 'include', 'share']) {
    const input = path.join(options.python.root, rel);
    try { await fs.lstat(input); } catch (e) { if(e.code==='ENOENT')continue; throw e; }
    await fs.cp(input, path.join(nativeRoot, rel), {recursive:true, verbatimSymlinks:true, preserveTimestamps:true});
  }
  const editLibrary = path.join(libedit.root, 'lib/x86_64-linux-gnu');
  for (const name of (await fs.readdir(editLibrary)).filter(name => /^libedit\.so(?:\.|$)/.test(name))) {
    const input = path.join(editLibrary, name), output = path.join(nativeRoot, 'lib', name), stat = await fs.lstat(input);
    if (stat.isSymbolicLink()) await fs.symlink(await fs.readlink(input), output);
    else await fs.copyFile(input, output);
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
  // Bind the bootstrap shim and tuple metadata to these native executables,
  // headers and schema. No RTTI-OFF tuple contributes bytes to this install.
  const generatedHeaders = path.join(directory, 'build/shim-schema');
  await fs.mkdir(path.join(generatedHeaders, 'flatbuffers'), {recursive:true});
  await run([path.join(build, 'bin/flatc'), '--no-warnings', '-c', '-o', path.join(generatedHeaders, 'flatbuffers'), path.join(compiler, 'schema/ModuleFormat.fbs')], {env});
  const fixed = path.join(nativeRoot, 'fixed-llc'); await fs.mkdir(fixed);
  await run([launcher, tool('clang++'), '-std=c++17', '-O2', '-fPIC', '-fno-rtti', '-fno-exceptions',
    `-I${llvm}/llvm/include`, `-I${llvmBuild}/include`, `-I${flatbuffers}/include`, `-I${generatedHeaders}`,
    '-c', path.join(component.producer.repository, 'runtime_shim/cjselfhost_llvmshim.cpp'), '-o', path.join(fixed,'cjselfhost_llvmshim.o')], {env});
  const values = {PLATFORM:component.config.target,LLVM_SHA:component.source.commit,CANGJIE_COMPILER_SHA:options.compilerSource.commit,FLATBUFFERS_SHA:options.flatbuffersSource.commit};
  for (const [name,prefix] of [['llc','LLC'],['opt','OPT'],['ld.lld','LLD']]) {
    const binary=path.join(nativeRoot,'bin',name), result=await requestExecute(binary,['--version'],{env:{...env,LD_LIBRARY_PATH:path.join(nativeRoot,'lib')}});
    const version=result.stdout.split('\n').map(line=>line.trim()).find(line=>/LLVM version |^LLD /.test(line));
    if(!version)reject('LLVM_VERSION',component.id,name);
    values[`${prefix}_SOURCE`]=`tuple:${component.source.commit}`; values[`${prefix}_VERSION`]=version; values[`${prefix}_SHA256`]=await fileDigest(binary);
    await fs.writeFile(path.join(fixed,`${name}.gz`),gzipSync(await fs.readFile(binary),{level:9}));
  }
  values.LLD_TOOL='ld.lld';values.SHIM_SHA256=await fileDigest(path.join(fixed,'cjselfhost_llvmshim.o'));
  const tupleText=Object.entries(values).map(([key,value])=>`${key}=${value}\n`).join('');parseLlvmToolsManifest(tupleText);
  await fs.writeFile(path.join(fixed,'llvm-tools.manifest'),tupleText);
  const readers={};for(const name of ['llvm-dis','llvm-as'])readers[name]={sha256:await fileDigest(path.join(nativeRoot,'bin',name)),version:(await requestExecute(path.join(nativeRoot,'bin',name),['--version'],{env:{...env,LD_LIBRARY_PATH:path.join(nativeRoot,'lib')}})).stdout.trim()};
  await atomicJson(path.join(nativeRoot,'bitcode-readers.json'),{source:component.source,targets:['llvm-dis','llvm-as'],tools:readers,producer:component.producer,buildId:request.identity.buildId});
  const tupleIdentity=`PLATFORM=${component.config.target}\nLLVM_SHA=${component.source.commit}\nCANGJIE_COMPILER_SHA=${options.compilerSource.commit}\nRECIPE_CJCJ_SHA=${component.producer.version}\nLLVM_ENABLE_RTTI=ON\nLLVM_LINK_LLVM_DYLIB=ON\nDEPOT_ROLE=producer output\n`;
  await fs.writeFile(path.join(nativeRoot,'MANIFEST'),tupleIdentity);
  // Retain the existing tuple metadata path; its contents declare this actual
  // native shared-library configuration rather than claiming static linkage.
  await fs.writeFile(path.join(nativeRoot,'lib/STATIC_LLVM.txt'),tupleIdentity);
  const tupleMembers=['bin/llvm-dis','bin/llvm-as','bitcode-readers.json','MANIFEST','bin/ld.lld','bin/llc','bin/opt','lib/STATIC_LLVM.txt','fixed-llc/llc.gz','fixed-llc/opt.gz','fixed-llc/ld.lld.gz','fixed-llc/cjselfhost_llvmshim.o','fixed-llc/llvm-tools.manifest'];
  await fs.writeFile(path.join(nativeRoot,'SHA256SUMS'),(await Promise.all(tupleMembers.map(async rel=>`${await fileDigest(path.join(nativeRoot,rel))}  ./${rel}\n`))).join(''));
  const dylib=path.join(nativeRoot,'lib/libLLVM-15.so');
  await atomicJson(path.join(nativeRoot,'lib/manifest.json'),{llvm_sha:component.source.commit,sha256:await fileDigest(dylib),platform:component.config.target,library:'libLLVM-15.so',targets:['X86','ARM','AArch64'],producer:{version:component.producer.version,buildId:request.identity.buildId}});
  // Boundscheck's official source has no CMakeLists.txt; the compiler adds
  // its own unchanged recipe as an authenticated generated build input.
  const boundsStatus = (await requestExecute(tool('git'), ['-C', bounds, 'status', '--porcelain', '-z', '--untracked-files=all'])).stdout;
  if (boundsStatus !== '?? CMakeLists.txt\0' || await fileDigest(path.join(bounds, boundsRel)) !== boundsChanges[boundsRel].sha256) reject('SOURCE_TRANSFORM', component.id, 'unexpected boundscheck generated recipe');
  const boundsAfter = {commit: options.boundscheckSource.commit, tree: options.boundscheckSource.tree, generated: boundsChanges};
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
  await sourceIdentity(paired, runtimeSource, 'cjdb-runtime', tool('git'));
  await atomicJson(path.join(artifacts, 'cjdb-producer.json'), {source: component.source, compiler: options.compilerSource, runtime: runtime.component.source,
    boundsAfter, flatAfter, generated, python: options.python, libedit, xml2: archive, producer: component.producer, buildId: request.identity.buildId,
    entry: 'CANGJIE_BUILD_CJDB', targets: ['lldb','cjdb'], build, installed, jobs:Number(jobs),
    llvmConfiguration:{rtti:cacheValue('LLVM_ENABLE_RTTI'), dylib:cacheValue('LLVM_BUILD_LLVM_DYLIB'), targets:cacheValue('LLVM_TARGETS_TO_BUILD')},
    llvmCacheSha256:await fileDigest(path.join(llvmBuild,'CMakeCache.txt'))});
}
