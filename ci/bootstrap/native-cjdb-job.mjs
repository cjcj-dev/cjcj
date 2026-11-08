#!/usr/bin/env zx
// Workflow adapter for the existing platform-owned producer, not a second N
// builder. Official preparation fetches sources and receives installed dependencies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {command,readJson,atomicJson,privateRoot,relative} from './sdk-flow.mjs';
import {nativePair} from '../runtime-pin.mjs';
import {nativeSourceSelection} from './native-source-selection.mjs';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {materializeNativeSource} from './sdk-source.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';
import {selectBuildJobs} from '../build-resources.mjs';
import {receiveNativeRuntime} from './native-runtime-input.mjs';
import {readHleDependencies} from './hle-input.mjs';
import {readInstalledNativeShim} from './native-shim-inputs.mjs';
import {readInstalledNativeAst} from './installed-native-ast.mjs';
import {prepareHostSdk} from '../release/bootstrap_host_sdk.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';

// Official preparation receives installed dependencies and their original
// configuration. Project sources are fetched here, never transported in tar.
export async function prepareNativeCjdbJob({input,work,env=process.env}) {
  if(env.GITHUB_ACTIONS!=='true'||hostPlatform()!=='linux_x86_64'||env.CJCJ_SRCBUILD_TARGET!=='linux-x64')
    throw Error('NATIVE_INPUT_ONLY_OFFICIAL_LINUX_REQUIRED');
  input=await privateRoot(input);work=await privateRoot(work);
  const selected=await readJson(path.join(input,'native-cjdb.json'));
  if(selected.platform!=='linux_x86_64')throw Error('NATIVE_INPUT_ONLY_PLATFORM');
  if(Object.keys(JSON.parse(env.CJCJ_SOURCE_SELECTION||'{}')).length)throw Error('NATIVE_INPUT_ONLY_DEFAULT_SOURCES_REQUIRED');
  if(await fs.stat(path.join(input,'native-build-inputs.tar')).then(()=>true,()=>false)
    ||Object.keys(selected).some(key=>key.endsWith('Archive')&&key!=='xml2Archive'))
    throw Error('NATIVE_INPUT_ONLY_SOURCE_ARCHIVE_FORBIDDEN');
  const pair=nativePair(env,{requireHost:true}),pins=readSourcePins();
  const {selection}=nativeSourceSelection(env,pair);
  const sources={compiler:selection.ast,llvm:selection.llvm,runtime:selection.runtime,
    bounds:{repository:pins.source.BOUNDS_SRC_URL,commit:pins.source.BOUNDS_REF},
    flatbuffers:{repository:pins.llvm.FLATBUFFERS_URL,commit:pins.llvm.FLATBUFFERS_SHA}};
  const records=[];
  await fs.mkdir(work,{recursive:true});
  try {
    const config={...selected,commits:{},tools:{...selected.tools,cc:env.CC||'clang',cxx:env.CXX||'clang++',
      launcher:env.CMAKE_CXX_COMPILER_LAUNCHER},jobs:await selectBuildJobs(undefined,env),linkJobs:1};
    for(const [name,row]of Object.entries(sources)) {
      if(selected[name]&&await fs.stat(path.resolve(input,selected[name])).then(()=>true,()=>false))
        throw Error('NATIVE_INPUT_ONLY_SOURCE_PAYLOAD '+name);
      if(!/^[a-f0-9]{40}$/.test(row.commit||'')||selected.commits?.[name]&&selected.commits[name]!==row.commit)
        throw Error('NATIVE_INPUT_ONLY_SOURCE_SELECTION '+name);
      const source=path.join(work,'sources',name);
      await fs.mkdir(path.dirname(source),{recursive:true});
      await fs.mkdir(source);
      await command(['git','init',source],{env,records});
      await command(['git','-C',source,'remote','add','origin',row.repository],{env,records});
      await command(['git','-C',source,'fetch','--depth=1','origin',row.commit],{env,records});
      await command(['git','-C',source,'checkout','--detach',row.commit],{env,records});
      await materializeNativeSource({source,commit:row.commit});
      config[name]=source;config.commits[name]=row.commit;
    }
    const shim=env.GITHUB_SHA;
    if(!/^[a-f0-9]{40}$/.test(shim||'')||selected.commits?.shim&&selected.commits.shim!==shim)
      throw Error('NATIVE_INPUT_ONLY_SHIM_SELECTION');
    config.shimSource=await privateRoot(env.GITHUB_WORKSPACE);config.commits.shim=shim;
    await materializeNativeSource({source:config.shimSource,commit:shim});
    for(const key of ['python','pythonExecutable','libedit','libeditLibraryDirectory'])
      if(selected[key])config[key]=path.resolve(input,selected[key]);
    if(selected.xml2Archive)config.xml2Archive={...selected.xml2Archive,file:path.resolve(input,selected.xml2Archive.file)};
    if(selected.pythonInputs?.record)config.pythonInputs={...selected.pythonInputs,record:path.resolve(input,selected.pythonInputs.record)};
    await atomicJson(path.join(work,'prepared/native-cjdb.json'),config);
  } finally {await atomicJson(path.join(work,'prepare-commands.json'),records);}
}

// locations.json remains the SDK consumer's location map. The tar contains
// only installed N/R and deployed dependency entities, preserving executable bits.
export async function packageNativeInputs({input,work,env=process.env}) {
  input=await privateRoot(input);work=await privateRoot(work);
  const locations=await readJson(path.join(input,'locations.json'));
  if(locations.platform!=='linux_x86_64'||locations.host)throw Error('NATIVE_INPUT_ONLY_LOCATIONS');
  const install=await privateRoot(env.CJCJ_NATIVE_CJDB_INSTALL),facts=await readJson(path.join(install,'BUILD-INPUTS.json'));
  const pair=nativePair(env,{requireHost:true}),{selection}=nativeSourceSelection(env,pair);
  if(facts.platform!==locations.platform||facts.commits?.llvm!==pair.llvm||facts.commits?.runtime!==pair.runtime
    ||facts.commits?.compiler!==selection.ast.commit)throw Error('NATIVE_INPUT_ONLY_INSTALL_PAIR');
  await readInstalledNativeShim({install,facts});
  await readInstalledNativeAst({install,facts,platform:locations.platform,commit:selection.ast.commit,llvmCommit:pair.llvm});
  const runtime=await receiveNativeRuntime({root:env.CJCJ_NATIVE_RUNTIME_INSTALL,sourceRepository:selection.runtime.repository,
    platform:locations.platform,llvmCommit:pair.llvm,runtimeCommit:pair.runtime,hostVersion:pair.hostVersion,work:path.join(work,'runtime-check')});
  const output=path.join(work,'native-inputs'),payload=path.join(output,'.native-inputs'),records=[];
  await fs.mkdir(payload,{recursive:true});
  const copy=async name=>{
    relative(name);const from=await fs.realpath(path.join(input,name));
    if(!from.startsWith(input+path.sep))throw Error('NATIVE_INPUT_ONLY_DEPENDENCY_PATH '+name);
    const to=path.join(payload,name);await fs.mkdir(path.dirname(to),{recursive:true});
    await fs.cp(from,to,{recursive:true,verbatimSymlinks:true,filter:file=>{
      if(path.basename(file)==='.git')throw Error('NATIVE_INPUT_ONLY_GIT_PAYLOAD '+file);return true;
    }});
  };
  const privateTools=locations.tools?.privateRoot;await copy(privateTools);
  await fs.access(path.join(payload,privateTools,'ts/src/sharedbuild/cjcj-stage1.sh'));
  const descriptor=locations.hleDependencies;relative(descriptor);
  const hle=await readHleDependencies(path.join(input,descriptor),locations.platform);await copy(descriptor);
  for(const name of ['node','modules','cjbind'])await copy(path.relative(input,hle[name].path));
  if(!locations.nativeToolDependencies)throw Error('NATIVE_INPUT_ONLY_TOOL_DEPENDENCIES');
  await copy(locations.nativeToolDependencies); // source facts only; each SDK job fetches JSON itself.
  await fs.cp(install,path.join(payload,'native'),{recursive:true,verbatimSymlinks:true});
  await fs.cp(runtime.install,path.join(payload,'runtime'),{recursive:true,verbatimSymlinks:true});
  if(readHostToolchainPin(locations.platform)!=='nightly-'+pair.hostVersion)throw Error('NATIVE_INPUT_ONLY_HOST_SELECTION');
  const host=await prepareHostSdk(locations.platform,path.join(work,'official-host'));
  await fs.mkdir(path.join(payload,'host'));
  await fs.cp(host.path,path.join(payload,'host/sdk'),{recursive:true,verbatimSymlinks:true});
  await fs.copyFile(host.archive,path.join(payload,'host',path.basename(host.archive)));
  const prefix=name=>'.native-inputs/'+name;
  const native={install:prefix('native'),buildResult:prefix('native/BUILD-INPUTS.json'),configuration:facts.configuration};
  const python=facts.pythonInstallationInput??{record:'share/cjcj/build-inputs/python-original.json',sha256:facts.pythonSource?.build?.originalInputs?.sha256};
  await fs.access(path.join(payload,'native',python.record));
  await atomicJson(path.join(output,'locations.json'),{...locations,
    host:{version:pair.hostVersion,install:prefix('host/sdk'),archive:prefix('host/'+path.basename(host.archive))},
    tools:{...locations.tools,privateRoot:prefix(privateTools)},hleDependencies:prefix(descriptor),
    nativeToolDependencies:prefix(locations.nativeToolDependencies),installations:{
      llvm:{...native,verification:{python:{record:prefix('native/'+python.record),sha256:python.sha256}}},ast:native,
      runtime:{install:prefix('runtime'),buildResult:prefix('runtime/NATIVE-INPUTS.json'),configuration:runtime.configuration}}});
  try {await command(['tar','-cf',path.join(output,'native-inputs.tar'),'-C',output,'.native-inputs'],{env,records});}
  finally {await atomicJson(path.join(work,'package-inputs-commands.json'),records);}
  return output;
}

// Package an installation produced by the normal native target, including its
// original Python input. This also serves producers that build on kkk2 first.
export async function packageNativeCjdb({install,work,env=process.env,records=[]}) {
  install=await privateRoot(install);work=await privateRoot(work);
  const facts=await readJson(path.join(install,'BUILD-INPUTS.json'));
  if(!facts.pythonInstallationInput) {
    const record=facts.configuration?.pythonInputs?.record;
    if(!record||!facts.pythonSource?.build?.originalInputs)throw Error('NATIVE_JOB_PYTHON_SOURCE_REQUIRED');
    const destination=path.join(install,'share/cjcj/build-inputs/python-original.json');
    await fs.mkdir(path.dirname(destination),{recursive:true});
    await fs.copyFile(record,destination);
  }
  await fs.mkdir(work,{recursive:true});
  const archive=path.join(work,'native-install.tar');
  await command(['tar','-cf',archive,'-C',install,'.'],{env,records});
  return {archive,install};
}

export async function buildNativeCjdbJob({input,work,env=process.env}) {
  input=await privateRoot(input);work=await privateRoot(work);
  const selected=await readJson(path.join(input,'native-cjdb.json'));
  const pair=nativePair(env,{requireHost:false}),platform=hostPlatform();
  if(!pair)throw Error('NATIVE_JOB_PAIR_REQUIRED');
  const {selection}=nativeSourceSelection(env,pair,{ast:{
    repository:path.resolve(input,selected.compiler || '.'),commit:selected.commits?.compiler}});
  if(selected.platform!==platform||selected.commits?.llvm!==pair.llvm
    ||selected.commits?.runtime!==pair.runtime||selected.commits?.compiler!==selection.ast.commit)
    throw Error('NATIVE_JOB_SOURCE_PAIR');
  const source=value=>path.resolve(input,value);
  const config={...selected,build:path.join(work,'build'),install:path.join(work,'install'),
    tools:{...selected.tools,launcher:selected.tools?.launcher||env.CMAKE_CXX_COMPILER_LAUNCHER}};
  if(platform==='windows_x86_64'&&env.CJCJ_WINDOWS_TOOLCHAIN) {
    const bin=path.join(await privateRoot(env.CJCJ_WINDOWS_TOOLCHAIN),'bin');
    config.tools={...config.tools,cc:await fs.realpath(path.join(bin,'clang.exe')),cxx:await fs.realpath(path.join(bin,'clang++.exe'))};
  }
  for(const name of ['compiler','llvm','runtime','bounds','flatbuffers','shimSource','libedit','python','pythonExecutable','toolchain','libeditLibraryDirectory'])
    if(selected[name])config[name]=source(selected[name]);
  for(const name of ['compilerArchive','shimArchive','xml2Archive'])
    if(selected[name])config[name]={...selected[name],file:source(selected[name].file)};
  if(selected.pythonInputs?.record)config.pythonInputs={...selected.pythonInputs,record:source(selected.pythonInputs.record)};
  if(selected.pythonProducer)config.pythonProducer={...selected.pythonProducer,
    archive:source(selected.pythonProducer.archive),work:path.join(work,'python'),
    tools:{...selected.pythonProducer.tools}};
  if(config.pythonProducer) {
    const executable=async value=>{
      if(!value)throw Error('NATIVE_JOB_PYTHON_TOOL');
      if(path.isAbsolute(value)||/[\\/]/.test(value))return fs.realpath(source(value));
      for(const dir of (env.PATH||'').split(path.delimiter)) {
        for(const suffix of process.platform==='win32'?['','.exe']:['']) {
          const file=path.join(dir,value+suffix);
          if(await fs.stat(file).then(s=>s.isFile(),()=>false))return fs.realpath(file);
        }
      }
      throw Error('NATIVE_JOB_PYTHON_TOOL '+value);
    };
    for(const key of ['bootstrapPython','msbuild'])config.pythonProducer.tools[key]=await executable(config.pythonProducer.tools[key]);
  }
  // Normal one-time Git HEAD selection for dependencies consumed directly by
  // CMake. Compiler/shim archives retain their existing materialization check.
  const records=[];
  await fs.mkdir(work,{recursive:true});
  try {
  for(const name of ['llvm','runtime','bounds','flatbuffers']) {
    if((!config[name]&&!selected[name+'Archive'])||!/^[0-9a-f]{40}$/.test(config.commits?.[name]||''))throw Error('NATIVE_JOB_SOURCE '+name);
    const archive=selected[name+'Archive'];
    if(archive)config[name]=path.join(work,'sources',name);
    await materializeNativeSource({source:config[name],commit:config.commits[name],
      ...(archive?{'source-archive':source(archive.file),'source-archive-sha256':archive.sha256}:{})},
      argv=>command(argv,{env,records}));
  }
  await fs.mkdir(work,{recursive:true});
  const file=path.join(work,'native-cjdb.json');
  await atomicJson(file,config);
    await command([process.execPath,fileURLToPath(new URL('./native-cjdb.mjs',import.meta.url)),file],{env,records});
    return await packageNativeCjdb({install:config.install,work,env,records});
  } finally {await atomicJson(path.join(work,'commands.json'),records);}
}

// The fixed raw tar remains immutable. A later source handoff may accompany
// it as a normal config plus its compiler archive, without repacking the tar.
export async function materializeNativeJob({artifact,input}) {
  artifact=await privateRoot(artifact);input=await privateRoot(input);
  await fs.mkdir(input);const records=[];
  try {
    await command(['tar','-xf',path.join(artifact,'native-build-inputs.tar'),'-C',input],{records});
    const file=path.join(artifact,'native-cjdb.json');
    const next=await readJson(file).catch(e=>{if(e.code==='ENOENT')return null;throw e;});
    if(next) {
      const name=relative(next.compilerArchive?.file);
      const from=await fs.realpath(path.join(artifact,name));
      if(!from.startsWith(artifact+path.sep))throw Error('NATIVE_JOB_SOURCE_ARCHIVE_PATH');
      const to=path.join(input,name);await fs.mkdir(path.dirname(to),{recursive:true});
      await fs.copyFile(from,to);await fs.copyFile(file,path.join(input,'native-cjdb.json'));
    }
  } finally {await atomicJson(path.join(input,'materialize-commands.json'),records);}
}
export async function unpackNativeCjdb({archive,install}) {
  install=await privateRoot(install);
  await fs.mkdir(install); // New destination; never overlay an old installation.
  await command(['tar','-xf',archive,'-C',install]);
  await fs.access(path.join(install,'BUILD-INPUTS.json'));
  return install;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const [mode,input,work]=process.argv.slice(2);
    if(mode==='materialize')await materializeNativeJob({artifact:input,input:work});
    else if(mode==='prepare-inputs')await prepareNativeCjdbJob({input,work});
    else if(mode==='package-inputs')await packageNativeInputs({input,work});
    else if(mode==='build')await buildNativeCjdbJob({input,work});
    else if(mode==='package') {
      const records=[];
      try {await packageNativeCjdb({install:input,work,records});}
      finally {await atomicJson(path.join(work,'commands.json'),records);}
    }
    else if(mode==='unpack')await unpackNativeCjdb({archive:input,install:work});
    else throw Error('usage: native-cjdb-job.mjs prepare-inputs DEPENDENCIES WORK | package-inputs DEPENDENCIES WORK | materialize ARTIFACT INPUT | build INPUT WORK | package INSTALL WORK | unpack ARCHIVE INSTALL');
  }catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
