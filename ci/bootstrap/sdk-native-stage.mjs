#!/usr/bin/env zx
// R stdlib/build.py owns its CMake graph; cjpm owns the compiler workspace.
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectBuildResources} from '../build-resources.mjs';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {command, copyOutputs, atomicJson, fileDigest, inventory, privateRoot, assembleDirectory, withProcessCancellation} from './sdk-flow.mjs';
import {sdkPlatform, stdInstallFiles, cleanSdkEnvironment} from './sdk-platform.mjs';
import {compilerProducer} from './compiler_identity.mjs';
import {verifyStdBuildInputs, prepareStdDependencies} from './stdlib-build.mjs';
import {injectCangjieVersion} from '../srcbuild/steps/inject-version-lib.mjs';
import {prepareTrimpath} from '../release/trimpath.mjs';
import {assertFinalStdInput} from './sdk-final-std.mjs';
import {writeStdProvenance} from '../../build/lib/provenance.mjs';
import {stdIdentity} from '../srcbuild/lib/final-compiler.mjs';
import {resolveProductBinary} from '../srcbuild/lib/product-binary.mjs';
import {acceptInstalledStd, flag, stdBuildType} from './sdk-std-resume.mjs';
import {installCompilerChirInterface} from './compiler-chir-interface.mjs';
import {readInstalledNativeShim,compilerNativeShim} from './native-shim-inputs.mjs';
import {nativeSymbolRows} from './std-runtime-colour.mjs';
import {materializeNativeSource, nativeSourceOptions} from './sdk-source.mjs';
import {visibleOptionsOnly,configureOptionVisibility} from './compiler-option-visibility.mjs';
export {acceptInstalledStd} from './sdk-std-resume.mjs';
// Runtime inputs are a private build input snapshot, not an install overlay.
// Re-entry may reuse equal bytes or publish a complete new snapshot. Keep the
// previous/unfinished trees for diagnosis; never merge stale files into inputs.
export async function prepareRuntimeInputs({runtime, link, native, buildType = 'relwithdebinfo', resume = false, signal}) {
  await privateRoot(link);
  const arch = native.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const common = `common/${native.os === 'win32' ? 'windows' : native.os}_${buildType}_${arch}`;
  const copies = ['lib', 'runtime/lib'].map(dir => ({from: path.join(runtime, dir, native.tuple),
    to: `${common}/${dir}/${native.tuple}`}));
  const expected = {};
  for (const spec of copies) {
    for (const [rel, value] of Object.entries(await inventory(spec.from))) expected[spec.to+'/'+rel] = value;
  }
  const equal = (a,b) => Object.keys(a).length === Object.keys(b).length
    && Object.entries(a).every(([key,value]) => JSON.stringify(value) === JSON.stringify(b[key]));
  const exists = await fs.lstat(link).then(() => true, error => {if (error.code === 'ENOENT') return false; throw error;});
  if (exists && equal(await inventory(link), expected)) {
    console.log('STD_RUNTIME_INPUT_REUSED '+link);
    return;
  }
  if (resume) throw new Error('STD_RESUME_RUNTIME_INPUT_CHANGED '+link);
  signal?.throwIfAborted();
  await fs.mkdir(path.dirname(link), {recursive:true});
  await assembleDirectory(link, async pending => {
    await copyOutputs(pending, copies);
    if (!equal(await inventory(pending), expected)) throw new Error('STD_RUNTIME_INPUT_CHANGED_DURING_COPY');
  }, signal);
  console.log('STD_RUNTIME_INPUT_PUBLISHED '+link);
}
export async function nativeStage(options, {signal} = {}) {
  signal?.throwIfAborted();
  if (options['accept-records'] && !options['resume-installed']) throw new Error('STD_RESUME_ARGUMENTS');
  if (options['resume-installed'] && (options.kind !== 'std' || options['compiler-runtime'] !== 'target')) throw new Error('STD_RESUME_ARGUMENTS');
  const {kind, source, sdk, runtime, output, platform, host} = options;
  if(kind!=='h1'&&kind!=='compiler'&&options['visible-options-only']!==undefined)
    throw Error('COMPILER_OPTION_CONFIGURATION_KIND');
  const optionVisibility=visibleOptionsOnly(options['visible-options-only']);
  const localModeApi=options['local-mode-api']===true;
  if(localModeApi&&kind!=='std')throw Error('STD_LOCAL_MODE_API_KIND');
  if (kind !== 'std' && options['build-type'] !== undefined) throw new Error('STD_BUILD_TYPE_KIND');
  const buildType = kind === 'std' ? stdBuildType(options['build-type']) : undefined;
  const commit = await materializeNativeSource(options,command,{signal});
  let resources;
  try {resources=await selectBuildResources({heap:options.heap,jobs:options.jobs});}
  catch(error){if(error.message.startsWith('BUILD_JOBS'))throw Error('NATIVE_STAGE_JOBS '+error.message);throw error;}
  const native=sdkPlatform(platform), jobs=String(resources.jobs),records=[];
  if(process.platform!==native.os||process.arch!==native.arch)throw new Error('NATIVE_RUNNER_REQUIRED');
  // A directly installed official compiler owns bin/cjc and its loader paths.
  // A selfhost stage still uses its recorded producer and execution runtime.
  let officialStdCompiler;
  if(kind==='std' && options['compiler-runtime']==='host') {
    const present=file=>fs.lstat(file).then(()=>true,e=>{if(e.code==='ENOENT')return false;throw e;});
    if(!await present(path.join(sdk,'STAGE-INPUTS.json'))) {
      const staged=path.join(sdk,'bin','cjcj-stage1'+native.exe);
      if(await present(staged)||await present(staged+'.entry')||await present(path.join(sdk,'libexec','compiler','cjcj-stage1'+native.exe)))
        throw Error('STD_BOOTSTRAP_STAGED_COMPILER_MISSING_INPUTS');
      officialStdCompiler=path.join(sdk,'bin','cjc'+native.exe);
      await fs.access(officialStdCompiler,fs.constants.X_OK);
    }
  }
  const hostRuntime=officialStdCompiler||kind==='compiler'||options['compiler-runtime']==='target'?sdk:path.join(sdk,'.host');
  const env={...cleanSdkEnvironment(sdk,platform,process.env,hostRuntime),cjHeapSize:resources.heap,
    CMAKE_BUILD_PARALLEL_LEVEL:jobs,CANGJIE_BUILD_JOBS:jobs,CJCJ_COMMIT:commit,
    CJCJ_SUPERVISOR_WORK:process.env.CJCJ_SUPERVISOR_WORK||output+'.supervision'};
  delete env.LD_PRELOAD;delete env.LD_AUDIT;
  let accepted;
  if (options['resume-installed']) {
    if (!options['resume-state'] || !options['resume-stage']) throw new Error('WORK_INPUTS_MISSING');
    const previous = JSON.parse(await fs.readFile(options['resume-state'], 'utf8'));
    const last = previous.commands?.filter(row => Array.isArray(row.argv)
      && flag(row.argv, '--output') === output && flag(row.argv, '--kind') === 'std').at(-1);
    const expected = last?.argv.includes('--resume-installed') ? last.resumeOf : last;
    if (expected?.cwd !== path.join(path.dirname(options['resume-state']), 'build', options['resume-stage'])) throw new Error('STD_RESUME_STAGE state');
    accepted = await acceptInstalledStd({file:options['accept-records'], source, output, commit, sdk, runtime,
      link:output+'.runtime-input', platform, compilerRuntime:options['compiler-runtime'], heap:options.heap, previous, expected, buildType, localModeApi});
  }
  await fs.mkdir(output,{recursive:true});
  const restoreOptionVisibility=kind==='h1'||kind==='compiler'
    ?await configureOptionVisibility(source,optionVisibility):async()=>{};
  try {
  if(kind==='std') {
    try {
    await verifyStdBuildInputs(sdk,platform);
    if(!options['resume-installed']) {
      const previous=await fs.readFile(output+'.commands.json','utf8').then(JSON.parse).catch(error=>{if(error.code==='ENOENT')return [];throw error;});
      await prepareStdDependencies({source,dependencies:options['std-dependencies']?JSON.parse(options['std-dependencies']):undefined,previous,records});
    }
    const link=output+'.runtime-input';
    const stdlib=path.join(source,'stdlib');
    const cmakeType = {debug:'Debug',release:'Release',relwithdebinfo:'RelWithDebInfo'}[buildType];
    const build = path.join(stdlib,'build/build');
    // The SDK's bootstrap std may contain older FFI archives. Prefer the
    // current native build before those SDK libraries when linking new std.
    const targetLibraries=[path.join(build,'lib'),link];
    const cache = await fs.readFile(path.join(build,'CMakeCache.txt'),'utf8').catch(error=>{
      if(error.code==='ENOENT')return null;throw error;
    });
    const cached = name => cache?.match(new RegExp('^'+name+':[^=]+=(.*)$','m'))?.[1];
    const reconfigure = cache !== null && (cached('CMAKE_BUILD_TYPE') !== cmakeType || cached('CANGJIE_TARGET_LIB') !== targetLibraries.join(';') ||
      (cached('CANGJIE_ENABLE_LOCAL_MODE_API')==='ON')!==localModeApi);
    if(options['resume-installed'] && reconfigure)throw new Error('STD_RESUME_BUILD_CONFIGURATION');
    await prepareRuntimeInputs({runtime, link, native, buildType, resume:!!options['resume-installed'], signal});
    if (options['resume-installed']) {
      const acceptedRow = {event: 'target-result', argv: ['resume-accepted', options['accept-records']], cwd: stdlib, rc: 0, signal: null,
        build: accepted.build.argv, install: accepted.install.argv};
      records.push(acceptedRow);
      console.log(JSON.stringify(acceptedRow));
    } else {
      // build.py only configures a missing native build directory. Reconfigure
      // an existing cache with the requested type/input while retaining its
      // toolchain, platform and other legitimate cached options.
      if(reconfigure)await command(['cmake','-S',stdlib,'-B',build,'-DCMAKE_BUILD_TYPE='+cmakeType,
        '-DCANGJIE_TARGET_LIB='+targetLibraries.join(';'),
        ...(localModeApi||cached('CANGJIE_ENABLE_LOCAL_MODE_API')!==undefined?['-DCANGJIE_ENABLE_LOCAL_MODE_API='+(localModeApi?'ON':'OFF')]:[]),'-U','RUNTIME_COMMON_LIB_DIR'],{cwd:stdlib,env,records});
      await command(['python3','-I','build.py','build','-t',buildType,'--jobs',jobs,
        ...targetLibraries.map(directory=>'--target-lib='+directory),...(localModeApi?['--local_mode_api']:[])],{cwd:stdlib,env,records});
      await command(['python3','-I','build.py','install','--prefix',output],{cwd:stdlib,env,records});
    }
    for(const rel of stdInstallFiles(platform))
      if(!(await fs.stat(path.join(output,rel))).isFile())throw new Error('STD_INSTALL_SHAPE '+rel);
    if(options['compiler-runtime']==='target')await assertFinalStdInput({sdk,std:output,runtime,
      host:JSON.parse(await fs.readFile(path.join(sdk,'STAGE-INPUTS.json'),'utf8')).selection.bootstrapHost.install,platform,work:output+'.consumers',signal});
    // Use the revision checked against the consumed source before target startup.
    // The legacy writer's trusted environment default is not a native CLI identity.
    await writeStdProvenance({sourceDir:stdlib,sourceRoot:source,sourceRevision:commit,installPrefix:output,compiler:officialStdCompiler??await compilerProducer(sdk),buildSdk:sdk,
      coloured:options['compiler-runtime']==='target'?'true':'bootstrap',preflightC2:options['compiler-runtime']==='target'?'stage2':'not-applicable',
      note:'native target/install '+commit});
    } finally { await atomicJson(output+'.commands.json',records); }
  } else if(kind==='h1') {
    if(native.os!=='linux') {
      // Keep the existing native producer for platforms without the ELF --wrap adapter.
      if(!host||!options['private-tools'])throw new Error('H1_HOST_AND_NATIVE_ADAPTER_REQUIRED');
      await command([process.execPath,path.join(options['private-tools'],'ts/src/sharedbuild/cjcj-stage1.mjs')],{
        cwd:source,env:{...env,CANGJIE_HOME:host,SB_SOURCE:source,SB_OUTPUT:path.join(output,'bin'),SB_NATIVE_ROOT:sdk,
          SB_SHA:commit,SB_PLATFORM:platform,SB_CC:options.cc,SB_OPTIMIZATION:'O1',SB_PARAMETERS_JSON:'{"compile_flags":""}'},records});
    } else {
    if(!host)throw new Error('H1_HOST_REQUIRED');
    const shimInstall=options['shim-install']||sdk;
    const shim=options['shim-install']?await compilerNativeShim({install:shimInstall,nativeInstall:sdk,compilerCommit:commit}):await readInstalledNativeShim({install:sdk});
    const work=output+'.h1',inputs=path.join(work,'inputs'),productRoot=path.join(work,'out');
    await fs.mkdir(inputs,{recursive:true});await fs.mkdir(productRoot,{recursive:true});
    await fs.copyFile(path.join(shimInstall,shim.object.path),path.join(inputs,'llvm-shim.o'));
    const parameters=path.join(work,'parameters.json');await atomicJson(parameters,{compile_flags:''});
    const manifest=path.join(source,'cjpm.toml'),before=await fs.readFile(manifest);
    const packageManifest=path.join(source,'packages/cjc/cjpm.toml'),packageBefore=await fs.readFile(packageManifest);
    const hostRuntimeFile=path.join(host,'runtime/lib',native.tuple,'libcangjie-runtime'+native.shared);
    const hostRuntimeSupportsConfigV1=(await nativeSymbolRows(hostRuntimeFile,{platform,runtime:true,defined:true})).includes('CJ_MRT_CjRuntimeInitWithConfigV1');
    const llvmLibraryFile=path.join(sdk,'third_party/llvm',native.llvmDirectory,native.llvmLibrary);
    await fs.access(llvmLibraryFile,fs.constants.R_OK);
    const startupConfiguration={hostRuntimeFile,hostRuntimeSupportsConfigV1,llvmLibraryFile};
    const linkFile=path.join(source,'runtime_shim','h1-'+native.llvmLibrary);
    let linkCreated=false;
    let packageCompiled=packageBefore;
    const lock=path.join(source,'cjpm.lock'),lockBefore=await fs.readFile(lock).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
    const h1env={...cleanSdkEnvironment(host,platform,process.env,host),cjHeapSize:resources.heap,
      CANGJIE_BUILD_JOBS:jobs,CMAKE_BUILD_PARALLEL_LEVEL:jobs,CJCJ_COMMIT:commit,
      CJCJ_SUPERVISOR_WORK:env.CJCJ_SUPERVISOR_WORK};
    let compiled;
    try {
      // The normal Linux producer owns these operations here. Its installed N
      // shim is already validated; only H1's own runtime configuration is built.
      const params=await fs.readFile(parameters,'utf8').then(JSON.parse);
      if(Object.keys(params).some(key=>key!=='compile_flags')||typeof params.compile_flags!=='string')throw Error('H1_PARAMETERS');
      const compileOption='-O1 '+(params.compile_flags+' --trimpath '+source).trim();
      let replacements=0;
      const text=before.toString().replace(/^(\s*compile-option\s*=\s*)"[^"\n]*"/gm,(_,prefix)=>{
        replacements++;return prefix+JSON.stringify(compileOption);
      });
      if(replacements!==1)throw Error('H1_WORKSPACE_COMPILE_OPTION');
      // cjpm and its compiler run on H. The executable built here links the
      // same N library that stage0-run installs beside the native shim.
      try {await fs.symlink(llvmLibraryFile,linkFile);linkCreated=true;}
      catch(error){if(error.code!=='EEXIST'||await fs.readlink(linkFile)!==llvmLibraryFile)throw error;}
      const hostLLVM='${CANGJIE_HOME}/third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary;
      let llvmInputs=0;
      packageCompiled=Buffer.from(packageBefore.toString().replace(/^(\s*link-option\s*=\s*)"([^"\n]*)"/gm,
        (_,prefix,value)=>prefix+JSON.stringify(value.split(/\s+/)
          .filter(token=>hostRuntimeSupportsConfigV1||token!=='--wrap=CJ_MRT_CjRuntimeInitWithConfigV1')
          .map(token=>{if(token!==hostLLVM)return token;llvmInputs++;return path.relative(source,linkFile);}).join(' '))));
      if(llvmInputs!==1)throw Error('H1_PACKAGE_LLVM_LINK_INPUT');
      await fs.writeFile(packageManifest,packageCompiled);
      await fs.writeFile(manifest,text);
      await fs.copyFile(path.join(inputs,'llvm-shim.o'),path.join(source,'runtime_shim/cjselfhost_llvmshim.o'));
      await command([...(process.env.CMAKE_C_COMPILER_LAUNCHER?[process.env.CMAKE_C_COMPILER_LAUNCHER]:[]),options.cc||'cc',
        '-std=c11','-O2','-fPIC','-D_POSIX_C_SOURCE=200809L','-DCJCJ_COMMIT="'+commit+'"',
        '-c',path.join(source,'runtime_shim/cjc_runtime_config.c'),'-o',path.join(source,'runtime_shim/cjc_runtime_config.o')],
        // The system C compiler loads its own LLVM. H's LLVM loader is for
        // cjpm/cjc and must not be injected into this native tool process.
        {cwd:source,env:{...h1env,LD_LIBRARY_PATH:'',LD_PRELOAD:'',LD_AUDIT:''},records});
      await command([...(process.env.CMAKE_C_COMPILER_LAUNCHER?[process.env.CMAKE_C_COMPILER_LAUNCHER]:[]),options.cc||'cc',
        '-std=c11','-O2','-fPIC',...(!hostRuntimeSupportsConfigV1?['-DCJCJ_LEGACY_HOST_RUNTIME']:[]),
        '-c',path.join(source,'runtime_shim/cjc_heap_defaults.c'),
        '-o',path.join(source,'runtime_shim/cjc_heap_defaults.o')],
        {cwd:source,env:{...h1env,LD_LIBRARY_PATH:'',LD_PRELOAD:'',LD_AUDIT:''},records});
      const target=await privateRoot(options['target-dir']||path.join(source,'target'));
      await command([path.join(host,'tools/bin/cjpm'),'build',...(options['target-dir']?['--target-dir',target]:[]),'-j'+jobs],{cwd:source,env:h1env,records});
      const built=await resolveProductBinary(path.join(target,'release/bin'),'h1');
      await fs.copyFile(built,path.join(productRoot,'cjcj-stage1'));
      await fs.cp(path.join(target,'release'),path.join(productRoot,'release'),{recursive:true,dereference:true});
      compiled=await fs.readFile(manifest);
    } finally {
      await fs.writeFile(manifest,before);
      await fs.writeFile(packageManifest,packageBefore);
      if(linkCreated)await fs.unlink(linkFile);
      const {sha256}=await import('./sdk-io.mjs');
      await atomicJson(path.join(work,'startup-configuration.json'),{...startupConfiguration,sourceChanges:{
        'packages/cjc/cjpm.toml':{beforeSha256:sha256(packageBefore),buildSha256:sha256(packageCompiled)}}});
      if(lockBefore!==null)await fs.writeFile(lock,lockBefore);else await fs.rm(lock,{force:true});
      await atomicJson(output+'.commands.json',records);
    }
    const bin=path.join(output,'bin');await fs.mkdir(bin,{recursive:true});
    const product=path.join(bin,'cjcj-stage1');
    await fs.copyFile(path.join(productRoot,'cjcj-stage1'),product);
    const {sha256}=await import('./sdk-io.mjs');
    await installCompilerChirInterface({source,destination:output,sdk,shim,records,env});
    await atomicJson(path.join(bin,'build-inputs.json'),{producer:'sdk-native-stage:h1',source:commit,sourceRoot:source,host,native:sdk,nativeShim:shim,startupConfiguration,visibleOptionsOnly:optionVisibility,
      sourceChanges:{'cjpm.toml':{beforeSha256:sha256(before),buildSha256:sha256(compiled)},
        'packages/cjc/cjpm.toml':{beforeSha256:sha256(packageBefore),buildSha256:sha256(packageCompiled)}},sha256:await fileDigest(product)});
    }
  } else if(kind==='compiler') {
    const target=await privateRoot(options['target-dir']||path.join(source,'target'));
    if(options.phase==='stage3')await assertFinalStdInput({sdk,std:sdk,runtime:sdk,
      host:JSON.parse(await fs.readFile(path.join(sdk,'STAGE-INPUTS.json'),'utf8')).selection.bootstrapHost.install,platform,work:output+'.std-consumers',signal});
    if(process.env.SOURCE_SDK_VERSION)await injectCangjieVersion(source,process.env.SOURCE_SDK_VERSION);
    const before=await fs.readFile(path.join(source,'cjpm.toml'));
    const shimInstall=options['shim-install']||sdk;
    const shim=await compilerNativeShim({install:options['shim-install'],nativeInstall:sdk,compilerCommit:commit});
    env.CJCJ_LLVM_SHIM_O=path.join(shimInstall,shim.object.path);
    await command([options.zx||'zx',path.join(source,'runtime_shim/build_shim.mjs')],{cwd:source,env,records});
    try {
      await prepareTrimpath(source);
      // A completed user installation need not contain the bootstrap .host
      // tree. The existing explicit host option selects the package manager
      // and its execution libraries; the selected SDK still supplies cjc/std.
      const packageManagerSdk=host??path.join(sdk,'.host');
      await command([path.join(packageManagerSdk,'tools/bin/cjpm'+native.exe),'build',...(options['target-dir']?['--target-dir',target]:[]),'-j',jobs],{cwd:source,env:cleanSdkEnvironment(sdk,platform,env,packageManagerSdk),records});
    } finally { await fs.writeFile(path.join(source,'cjpm.toml'), before); }
    const product=await resolveProductBinary(path.join(target,'release/bin'),options.phase||'stage2',{windows:native.os==='win32'});
    await assembleDirectory(output, async destination => {
    await copyOutputs(destination,[{from:product,to:'bin/cjcj-stage1'+native.exe},
      // These are the new compiler's link inputs. The package manager's host
      // execution libraries can belong to an older compiler and must not travel
      // with this output. Carry dependencies as normal producer artifacts so an
      // independent installer need not select them again.
      {from:path.join(sdk,'runtime/lib',native.tuple),to:'.compiler-exec/runtime/lib/'+native.tuple},
      {from:path.join(sdk,'lib',native.tuple),to:'.compiler-exec/lib/'+native.tuple},
      {from:await fs.realpath(path.join(sdk,'third_party/llvm',native.llvmDirectory,native.llvmLibrary)),to:'.compiler-exec/third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary},
      // runtime_shim/build_shim.mjs links the host runtime into the source tree as
      // ${repo}/target/release/runtime for the compiler's relative lookup. That is
      // a build-tree facility, not a package member: copying it would carry an
      // absolute path out of the tree, which the install guard rejects as escape.
      {from:path.join(target,'release'),to:'share/cjcj/cjo',exclude:['bin','runtime']},
      ...['cjselfhost_llvmshim.o','cjc_runtime_config.o','cjc_heap_defaults.o'].map(name=>({from:path.join(source,'runtime_shim',name),to:'share/cjcj/runtime_shim/'+name}))]);
    await installCompilerChirInterface({source,destination,sdk,shim,records,env});
    await atomicJson(path.join(destination,'compiler-inputs.json'),{commit,nativeShim:shim,visibleOptionsOnly:optionVisibility,version:process.env.SOURCE_SDK_VERSION,parentSha256:await fileDigest(await compilerProducer(sdk)),
      stdSha256:await stdIdentity(options['std-input']||sdk, options['std-input']||sdk, {sourceSdk:sdk}),
      stdCoreSha256:await fileDigest(path.join(sdk,'lib',native.tuple,'libcangjie-std-core.a')),
      compileConfigurationBeforeSha256:(await import('./sdk-io.mjs')).sha256(before),compilerSha256:await fileDigest(product)});
    }, signal);
  } else throw new Error('NATIVE_TARGET_KIND '+kind);
  await atomicJson(output+'.commands.json',records);
  } finally {await restoreOptionVisibility();}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const spec=Object.fromEntries(['jobs','kind','source','sdk','runtime','output','platform','commit','host','heap','private-tools','cc','compiler-runtime','zx','phase','std-input','accept-records','resume-state','resume-stage','source-archive','source-archive-sha256','target-dir','shim-install','build-type','std-dependencies','visible-options-only'].map(k=>[k,{type:'string'}]));
    spec['resume-installed']={type:'boolean'};spec['local-mode-api']={type:'boolean'};
    nativeSourceOptions(process.argv); // Reject duplicate identity flags before parseArgs.
    const {values}=parseArgs({options:spec});
    if(!values.kind||!values.source||!values.sdk||!values.output||!values.platform)throw new Error('native stage needs kind/source/sdk/output/platform');
    await withProcessCancellation(signal => nativeStage(values, {signal}));
  }catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
