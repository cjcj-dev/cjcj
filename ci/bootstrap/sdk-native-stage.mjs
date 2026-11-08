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
import {verifyStdBuildInputs} from './stdlib-build.mjs';
import {injectCangjieVersion} from '../srcbuild/steps/inject-version-lib.mjs';
import {prepareTrimpath} from '../release/trimpath.mjs';
import {assertFinalStdInput} from './sdk-final-std.mjs';
import {writeStdProvenance} from '../../build/lib/provenance.mjs';
import {stdIdentity} from '../srcbuild/lib/final-compiler.mjs';
import {resolveProductBinary} from '../srcbuild/lib/product-binary.mjs';
import {acceptInstalledStd, flag, stdBuildType} from './sdk-std-resume.mjs';
import {readInstalledNativeShim} from './native-shim-inputs.mjs';
import {materializeNativeSource, nativeSourceOptions} from './sdk-source.mjs';
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
  if (kind !== 'std' && options['build-type'] !== undefined) throw new Error('STD_BUILD_TYPE_KIND');
  const buildType = kind === 'std' ? stdBuildType(options['build-type']) : undefined;
  const commit = await materializeNativeSource(options,command,{signal});
  let resources;
  try {resources=await selectBuildResources({heap:options.heap,jobs:options.jobs});}
  catch(error){if(error.message.startsWith('BUILD_JOBS'))throw Error('NATIVE_STAGE_JOBS '+error.message);throw error;}
  const native=sdkPlatform(platform), jobs=String(resources.jobs),records=[];
  if(process.platform!==native.os||process.arch!==native.arch)throw new Error('NATIVE_RUNNER_REQUIRED');
  const hostRuntime=kind==='compiler'||options['compiler-runtime']==='target'?sdk:path.join(sdk,'.host');
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
      link:output+'.runtime-input', platform, compilerRuntime:options['compiler-runtime'], heap:options.heap, previous, expected, buildType});
  }
  await fs.mkdir(output,{recursive:true});
  if(kind==='std') {
    await verifyStdBuildInputs(sdk,platform);
    const link=output+'.runtime-input';
    const stdlib=path.join(source,'stdlib');
    const cmakeType = {debug:'Debug',release:'Release',relwithdebinfo:'RelWithDebInfo'}[buildType];
    const build = path.join(stdlib,'build/build');
    const cache = await fs.readFile(path.join(build,'CMakeCache.txt'),'utf8').catch(error=>{
      if(error.code==='ENOENT')return null;throw error;
    });
    const cached = name => cache?.match(new RegExp('^'+name+':[^=]+=(.*)$','m'))?.[1];
    const reconfigure = cache !== null && (cached('CMAKE_BUILD_TYPE') !== cmakeType || cached('CANGJIE_TARGET_LIB') !== link);
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
        '-DCANGJIE_TARGET_LIB='+link,'-U','RUNTIME_COMMON_LIB_DIR'],{cwd:stdlib,env,records});
      await command(['python3','-I','build.py','build','-t',buildType,'--jobs',jobs,'--target-lib='+link],{cwd:stdlib,env,records});
      await command(['python3','-I','build.py','install','--prefix',output],{cwd:stdlib,env,records});
    }
    for(const rel of stdInstallFiles(platform))
      if(!(await fs.stat(path.join(output,rel))).isFile())throw new Error('STD_INSTALL_SHAPE '+rel);
    if(options['compiler-runtime']==='target')await assertFinalStdInput({sdk,std:output,runtime,
      host:JSON.parse(await fs.readFile(path.join(sdk,'STAGE-INPUTS.json'),'utf8')).selection.bootstrapHost.install,platform,work:output+'.consumers',signal});
    // Use the revision checked against the consumed source before target startup.
    // The legacy writer's trusted environment default is not a native CLI identity.
    await writeStdProvenance({sourceDir:stdlib,sourceRoot:source,sourceRevision:commit,installPrefix:output,compiler:await compilerProducer(sdk),buildSdk:sdk,
      coloured:options['compiler-runtime']==='target'?'true':'bootstrap',preflightC2:options['compiler-runtime']==='target'?'stage2':'not-applicable',
      note:'native target/install '+commit});
  } else if(kind==='h1') {
    if(!host||!options['private-tools'])throw new Error('H1_HOST_AND_NATIVE_ADAPTER_REQUIRED');
    if(native.os!=='linux')throw new Error('H1_LINUX_PRODUCER_REQUIRED');
    const shim=await readInstalledNativeShim({install:sdk});
    const work=output+'.h1',inputs=path.join(work,'inputs'),productRoot=path.join(work,'out');
    await fs.mkdir(inputs,{recursive:true});await fs.mkdir(productRoot,{recursive:true});
    await fs.copyFile(path.join(sdk,shim.object.path),path.join(inputs,'llvm-shim.o'));
    const parameters=path.join(work,'parameters.json');await atomicJson(parameters,{compile_flags:''});
    const manifest=path.join(source,'cjpm.toml'),before=await fs.readFile(manifest);
    let compiled;
    try {
      await command(['bash',path.join(options['private-tools'],'ts/src/sharedbuild/cjcj-stage1.sh')],{
        cwd:source,env:{...cleanSdkEnvironment(host,platform,process.env,host),cjHeapSize:resources.heap,
          CANGJIE_BUILD_JOBS:jobs,SB_SOURCE:source,SB_OUTPUT:productRoot,SB_INPUTS:inputs,
          SB_SHA:commit,SB_OPTIMIZATION:'O1',SB_PARAMETERS:parameters},records});
      compiled=await fs.readFile(manifest);
    } finally {
      await fs.writeFile(manifest,before);
      await atomicJson(output+'.commands.json',records);
    }
    const bin=path.join(output,'bin');await fs.mkdir(bin,{recursive:true});
    const product=path.join(bin,'cjcj-stage1');
    await fs.copyFile(path.join(productRoot,'cjcj-stage1'),product);
    const {sha256}=await import('./sdk-io.mjs');
    await atomicJson(path.join(bin,'build-inputs.json'),{source:commit,host,native:sdk,nativeShim:shim,
      sourceChanges:{'cjpm.toml':{beforeSha256:sha256(before),buildSha256:sha256(compiled)}},sha256:await fileDigest(product)});
  } else if(kind==='compiler') {
    const target=await privateRoot(options['target-dir']||path.join(source,'target'));
    if(options.phase==='stage3')await assertFinalStdInput({sdk,std:sdk,runtime:sdk,
      host:JSON.parse(await fs.readFile(path.join(sdk,'STAGE-INPUTS.json'),'utf8')).selection.bootstrapHost.install,platform,work:output+'.std-consumers',signal});
    if(process.env.SOURCE_SDK_VERSION)await injectCangjieVersion(source,process.env.SOURCE_SDK_VERSION);
    const before=await fs.readFile(path.join(source,'cjpm.toml'));
    const shimInstall=options['shim-install']||sdk;
    const shim=await readInstalledNativeShim({install:shimInstall});
    if(shim.source.commit!==commit)throw Error('NATIVE_SHIM_COMPILER_SOURCE '+shim.source.commit+' != '+commit);
    // A separate shim installation may update compiler-owned glue, but must
    // still target this SDK's LLVM and compiler schema dependency pair.
    if(options['shim-install']) {
      const sdkShim=await readInstalledNativeShim({install:sdk});
      if(shim.llvm.commit!==sdkShim.llvm.commit||shim.compiler.commit!==sdkShim.compiler.commit)
        throw Error('NATIVE_SHIM_DEPENDENCY_PAIR');
    }
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
    await atomicJson(path.join(destination,'compiler-inputs.json'),{commit,nativeShim:shim,version:process.env.SOURCE_SDK_VERSION,parentSha256:await fileDigest(await compilerProducer(sdk)),
      stdSha256:await stdIdentity(options['std-input']||sdk, options['std-input']||sdk, {sourceSdk:sdk}),
      stdCoreSha256:await fileDigest(path.join(sdk,'lib',native.tuple,'libcangjie-std-core.a')),
      compileConfigurationBeforeSha256:(await import('./sdk-io.mjs')).sha256(before),compilerSha256:await fileDigest(product)});
    }, signal);
  } else throw new Error('NATIVE_TARGET_KIND '+kind);
  await atomicJson(output+'.commands.json',records);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const spec=Object.fromEntries(['jobs','kind','source','sdk','runtime','output','platform','commit','host','heap','private-tools','cc','compiler-runtime','zx','phase','std-input','accept-records','resume-state','resume-stage','source-archive','source-archive-sha256','target-dir','shim-install','build-type'].map(k=>[k,{type:'string'}]));
    spec['resume-installed']={type:'boolean'};
    nativeSourceOptions(process.argv); // Reject duplicate identity flags before parseArgs.
    const {values}=parseArgs({options:spec});
    if(!values.kind||!values.source||!values.sdk||!values.output||!values.platform)throw new Error('native stage needs kind/source/sdk/output/platform');
    await withProcessCancellation(signal => nativeStage(values, {signal}));
  }catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
