// Facts captured around the actual producer, carried with its outputs. An
// install-only invocation never assigns its current selector to an old binary.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {atomicJson, fileDigest, readJson} from '../../ci/bootstrap/sdk-flow.mjs';
import {compilerProducer} from '../../ci/bootstrap/compiler_identity.mjs';
import {readNativeToolDependencies} from './native-tool-dependencies.mjs';
import {TOOL_DIRECTORIES,toolPayloads,nativeToolBuildPayloads,toolBuildProduct} from './tool-layout.mjs';
import {sha256} from '../../ci/bootstrap/sdk-io.mjs';

const execute = promisify(execFile);
const directories = TOOL_DIRECTORIES;
const recordPath = (config, name) => path.join(config.workspace,'build','tools',name,'build-inputs.json');
const dry = () => process.env.CANGJIE_BUILD_DRY_RUN === '1';
async function sourceState(root, directory, revision) {
  const query = async args => (await execute('git',['-C',root,...args],{maxBuffer:16*1024*1024})).stdout;
  const commit = (await query(['rev-parse','--verify',revision+'^{commit}'])).trim();
  // Record the actual tracked edits (e.g. the native MinGW path patch) rather
  // than silently calling a patched tree a clean object. Generated outputs are
  // not source inputs. New untracked source files are not a supported overlay.
  const diff = await query(['diff','--binary',commit,'--',directory]);
  return {commit, changes_sha256:sha256(diff)};
}
export async function sdkInputs(config, sdk) {
  // Official SDK archives expose bin/cjc and libraries, not our bootstrap
  // stage record. Preserve stage facts when present; never manufacture them.
  let stage;
  try { stage = await readJson(path.join(sdk,'STAGE-INPUTS.json')); }
  catch(error) { if(error.code!=='ENOENT')throw error; }
  const tuple = config.target.runtimeLibSubdir(config.buildType);
  const files = {compiler:stage===undefined?path.join(sdk,'bin','cjc'+config.target.spec.exeSuffix):await compilerProducer(sdk),
    stdCore:path.join(sdk,'lib',tuple,'libcangjie-std-core.a'),
    runtime:path.join(sdk,'runtime/lib',tuple,'libcangjie-runtime'+(config.target.spec.os==='windows'?'.dll':config.target.spec.os==='darwin'?'.dylib':'.so'))};
  for(const [name,rel]of Object.entries({stdProvenance:'PROVENANCE.txt',compilerEntry:'bin/cjcj-stage1'+config.target.spec.exeSuffix+'.entry',
    hleDependencies:'tools/dtsparser/DEPENDENCIES.json',nativeAst:(config.target.spec.os==='windows'?'tools/bin/libcangjie-lsp':'tools/lib/libcangjie-lsp')+(config.target.spec.os==='windows'?'.dll':config.target.spec.os==='darwin'?'.dylib':'.so'),executionRuntime:'.compiler-exec/'+path.relative(sdk,files.runtime)})){
    try{await fs.access(path.join(sdk,rel));files[name]=path.join(sdk,rel);}catch(e){if(e.code!=='ENOENT')throw e;}
  }
  return {...(stage===undefined?{}:{stage}), artifacts:Object.fromEntries(await Promise.all(Object.entries(files).map(async ([name,file])=>[name,{path:file,sdkRelative:path.relative(sdk,file).split(path.sep).join('/'),sha256:await fileDigest(file)}])))};
}
export async function beginToolBuild(config, name, {cjpmPin, argv, env, sdk}) {
  if(dry()) return null;
  const root=config.repoPath('tools'), directory=directories[name];
  if(!directory)throw new Error('TOOL_BUILD_NAME '+name);
  // Invalidate a prior success before the next attempt. Preserve it as evidence
  // so an upstream build.py returning zero after failure cannot reuse the row.
  const destination=recordPath(config,name);
  try { await fs.rename(destination,destination+'.previous-'+Date.now()); }
  catch(e){if(e.code!=='ENOENT')throw e;}
  const repository=name==='cjpm'?cjpmPin.url:config.repo('tools').url;
  const state=await sourceState(root,directory,name==='cjpm'?cjpmPin.ref:'HEAD');
  const environment=Object.fromEntries(['CC','CXX','CFLAGS','CXXFLAGS','LDFLAGS','CANGJIE_HOME','CANGJIE_STDX_PATH',
    'PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH','CANGJIE_BUILD_JOBS','CMAKE_BUILD_PARALLEL_LEVEL','MAKEFLAGS',
    'CJFMT_FRONTEND_CJO','CJFMT_FRONTEND_LIB','CJFMT_FRONTEND_NATIVE','CJFMT_FRONTEND_REF','CJFMT_SOURCE_REF',
    'cjHeapSize','JAVA_HOME','CJC_HEAP_SIZE','CJ_HEAP_SIZE','CANGJIE_HEAP_SIZE','CJ_IR_VERIFIER_MODE']
    .filter(key=>env[key]!==undefined&&env[key]!==null).map(key=>[key,String(env[key])]));
  const dependencies=['cjlint','cjprof'].includes(name)?await readNativeToolDependencies(config.toolsDependencies,[name]):{};
  for(const row of Object.values(dependencies)) {
    const actual=await sourceState(row.path,'.','HEAD');
    if(actual.commit!==row.commit||actual.changes_sha256!==sha256(''))throw Error('TOOL_DEPENDENCY_SOURCE_CHANGED '+row.path);
    Object.assign(row,actual);
  }
  return {source:{status:'resolved',repository,commit:state.commit},
    build:{directory,dependencies,source_changes_sha256:state.changes_sha256,argv,
      platform:config.target.spec.llvmPlatform,buildType:argv[argv.indexOf('-t')+1],requestedBuildType:config.buildType,
      mode:config.toolsBuildMode??'clean',version:config.cangjieVersion,environment,inputs:await sdkInputs(config,sdk)}};
}
async function nativeConfigurationInputs(config,name) {
  const nativeConfiguration={};
  if(['cjfmt','cjlint','cjprof','cjcompat','cjtrace-recover'].includes(name))for(const [part,relative]of [['native',name+(name==='cjtrace-recover'?'/cmake-build/CMakeCache.txt':'/build/build/CMakeCache.txt')],...(name==='cjprof'?[['jni','cjprof/bridge/jni/build/CMakeCache.txt']]:[])]) {
    const file=path.join(config.repoPath('tools'),relative);
    const cache=Object.fromEntries((await fs.readFile(file,'utf8')).split('\n').filter(line=>/^[A-Za-z_][^:]*:[^=]*=/.test(line)).map(line=>[line.slice(0,line.indexOf(':')),line.slice(line.indexOf('=')+1)]));
    nativeConfiguration[part]={path:file,values:Object.fromEntries(Object.entries(cache).filter(([key])=>/^(CMAKE_(BUILD_TYPE|SYSTEM_NAME|CXX_COMPILER|C_COMPILER|HOME_DIRECTORY)|CANGJIE_HOME$|CANGJIE_MANGLE_SOURCE_DIR$|CJTRACE_BUNDLE_RUNTIME$|RUNTIME_RPATH$|ZX_EXECUTABLE$|CJFMT_|CJPROF_|JAVA_|JNI_|JSON_ROOT$|GCC_TOOLCHAIN_FLAG$)/.test(key)))};
  }
  return nativeConfiguration;
}
export async function finishToolBuild(config, name, facts, product) {
  if(dry())return;
  const state=await sourceState(config.repoPath('tools'),facts.build.directory,facts.source.commit);
  if(state.changes_sha256!==facts.build.source_changes_sha256)throw new Error('TOOL_SOURCE_CHANGED_DURING_BUILD '+name);
  for(const [name,row]of Object.entries(facts.build.dependencies??{})) {
    const current=await sourceState(row.path,'.','HEAD');
    if(!isDeepStrictEqual(current,{commit:row.commit,changes_sha256:row.changes_sha256}))throw Error('TOOL_DEPENDENCY_CHANGED_DURING_BUILD '+name);
  }
  if(['cjlint','cjprof'].includes(name)) {
    const selection=await readNativeToolDependencies(config.toolsDependencies,[name]);
    const before=Object.fromEntries(Object.entries(facts.build.dependencies).map(([key,{repo,commit,path}])=>[key,{repo,commit,path}]));
    if(!isDeepStrictEqual(before,selection))throw Error('TOOL_DEPENDENCY_SELECTION_CHANGED '+name);
  }
  const landed=await sdkInputs(config,facts.build.environment.CANGJIE_HOME);
  if(!isDeepStrictEqual(landed,facts.build.inputs))throw new Error('TOOL_SDK_CHANGED_DURING_BUILD '+name);
  const nativeConfiguration=await nativeConfigurationInputs(config,name);
  if(name==='cjlint' && (config.toolsGccToolchain || 'GCC_TOOLCHAIN_FLAG' in nativeConfiguration.native.values)) {
    const actual=nativeConfiguration.native.values.GCC_TOOLCHAIN_FLAG;
    console.log('TOOLS_GCC_CONFIGURATION_ASSERTION_REACHED '+JSON.stringify({actual,expected:config.toolsGccToolchain??''}));
    if(actual!==(config.toolsGccToolchain??''))
      throw Error('TOOL_GCC_TOOLCHAIN_MISMATCH cjlint: '+actual);
  }
  const payloads={};
  for(const row of await nativeToolBuildPayloads(config,name))payloads[row.to]={source:row.from,sha256:await fileDigest(row.from)};
  await atomicJson(recordPath(config,name),{...facts,artifact:{path:product,sha256:await fileDigest(product)},build:{...facts.build,nativeConfiguration,payloads,rc:0}});
}
export async function toolBuildInputs(config, name, product, {installed=false}={}) {
  const digest=await fileDigest(product);
  let facts;
  try { facts=await readJson(recordPath(config,name)); }
  catch(e){if(e.code!=='ENOENT')throw e;
    return {source:{status:'unresolved',reason:'original producer did not record source/build inputs'},artifact:{sha256:digest}};}
  if(facts.build?.rc!==0 || (installed&&facts.install!==undefined?facts.install?.artifact:facts.artifact)?.sha256!==digest || facts.build.platform!==config.target.spec.llvmPlatform
    || !/^[0-9a-f]{40}$/.test(facts.source?.commit||'') || !facts.source?.repository)
    throw new Error('TOOL_BUILD_INPUT_MISMATCH '+name);
  if(['cjfmt','cjlint','cjprof','cjcompat','cjtrace-recover'].includes(name)&&!isDeepStrictEqual(await nativeConfigurationInputs(config,name),facts.build.nativeConfiguration))throw Error('TOOL_BUILD_CONFIGURATION_CHANGED '+name);
  if(['cjlint','cjprof'].includes(name)) {
    const current={};
    for(const row of await nativeToolBuildPayloads(config,name))current[row.to]={source:row.from,sha256:await fileDigest(row.from)};
    if(!isDeepStrictEqual(current,facts.build.payloads))throw Error('TOOL_BUILD_PAYLOAD_CHANGED '+name);
  }
  return facts;
}

// Record the normal install's complete payload only after its command succeeds.
// Existing build facts stay attached to reused bytes, never to today's selector.
export async function finishToolInstall(config,name,product,argv,{prefix}={}) {
  if(dry())return;
  const facts=await toolBuildInputs(config,name,toolBuildProduct(config,name));
  if(facts.source.status!=='resolved')throw new Error('TOOL_INSTALL_SOURCE_MISSING '+name);
  const payloads={};
  for(const row of await toolPayloads(config,name,prefix))payloads[row.to]={source:row.from,sha256:await fileDigest(row.from)};
  if(['cjlint','cjprof'].includes(name)) {
    if(!isDeepStrictEqual(Object.keys(payloads).sort(),Object.keys(facts.build.payloads).sort()))throw Error('TOOL_INSTALL_BUILD_PAYLOAD_SET '+name);
    for(const [rel,row]of Object.entries(payloads)) {
      const built=facts.build.payloads[rel];
      // CMake may normally rewrite native RPATH/install names. Keep those
      // installed bytes distinct; copied config/JNI must still be identical.
      if((rel.includes('/config/')||rel.includes('cjprof-jni'))&&row.sha256!==built.sha256)throw Error('TOOL_INSTALL_BUILD_PAYLOAD_MISMATCH '+rel);
      row.build={...built};
    }
  }
  const artifact={path:product,sha256:await fileDigest(product)};
  await atomicJson(prefix?path.join(prefix,'build-inputs.json'):recordPath(config,name),{...facts,install:{argv,rc:0,artifact,payloads}});
}
export async function installedToolBuildInputs(config,name,product) {
  const facts=await toolBuildInputs(config,name,product,{installed:true});
  // Old outputs keep their incomplete facts; the target-readiness consumer
  // refuses them. Installing bytes must not invent a successful install event.
  if(facts.install===undefined)return facts;
  if(facts.install.rc!==0)throw new Error('TOOL_INSTALL_INPUTS_MISSING '+name);
  const current={};
  for(const row of await toolPayloads(config,name))current[row.to]={source:row.from,sha256:await fileDigest(row.from),...(facts.install.payloads?.[row.to]?.build?{build:facts.install.payloads[row.to].build}:{})};
  if(!isDeepStrictEqual(current,facts.install.payloads))throw new Error('TOOL_INSTALL_PAYLOAD_CHANGED '+name);
  return facts;
}
