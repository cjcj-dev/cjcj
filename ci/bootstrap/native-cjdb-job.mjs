#!/usr/bin/env zx
// Workflow adapter for the existing platform-owned producer, not a second N
// builder. The input tar contains normal native-cjdb configuration/dependencies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {command,readJson,atomicJson,privateRoot,relative} from './sdk-flow.mjs';
import {nativePair} from '../runtime-pin.mjs';
import {nativeSourceSelection} from './native-source-selection.mjs';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {materializeNativeSource} from './sdk-source.mjs';

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
    const facts=await readJson(path.join(config.install,'BUILD-INPUTS.json'));
    if(!facts.pythonInstallationInput) {
      const record=config.pythonInputs?.record;
      if(!record||!facts.pythonSource?.build?.originalInputs)throw Error('NATIVE_JOB_PYTHON_SOURCE_REQUIRED');
      const destination=path.join(config.install,'share/cjcj/build-inputs/python-original.json');
      await fs.mkdir(path.dirname(destination),{recursive:true});
      await fs.copyFile(record,destination);
    }
    const archive=path.join(work,'native-install.tar');
    await command(['tar','-cf',archive,'-C',config.install,'.'],{env,records});
    return {archive,install:config.install};
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
    else if(mode==='build')await buildNativeCjdbJob({input,work});
    else if(mode==='unpack')await unpackNativeCjdb({archive:input,install:work});
    else throw Error('usage: native-cjdb-job.mjs materialize ARTIFACT INPUT | build INPUT WORK | unpack ARCHIVE INSTALL');
  }catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
