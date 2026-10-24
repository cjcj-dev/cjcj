#!/usr/bin/env zx
// The package describes the directory it archives, never the current checkout
// or a CI-provided expected tuple. Existing producer fields stay intact.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest,readJson,relative} from '../../bootstrap/sdk-flow.mjs';
import {sdkPlatform} from '../../bootstrap/sdk-platform.mjs';
import {runtimeInputsForArtifact,RUNTIME_INPUTS} from '../../../build/lib/runtime-source-inputs.mjs';
import {embeddedStamp} from '../../../build/lib/toolchain-identity.mjs';
import {readInstalledStdxInputs} from '../../../build/lib/installed-stdx-inputs.mjs';
import {STDX_BUILD_INPUTS} from '../../../build/srcbuild/stdx-build-inputs.mjs';
import {reconcileStdArtifacts} from '../../../build/lib/release-manifest.mjs';
import {readInstalledNativeAst} from '../../bootstrap/installed-native-ast.mjs';
import {readWindowsPythonInstallation} from '../../bootstrap/native-python-install.mjs';
const optional=async file=>{try{return await readJson(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}};
const unresolved=reason=>({status:'unresolved',reason});
const source=row=>row?.repository&&/^[0-9a-f]{40}$/.test(row.commit||'')?{status:'resolved',repository:row.repository,commit:row.commit}:unresolved('producer source repository/commit not recorded');
async function artifact(sdk,rel,expected){
  relative(rel);
  const sha256=await fileDigest(path.join(sdk,rel));
  if(expected&&sha256!==expected)throw new Error('INSTALLED_INPUT_BYTES '+rel);
  return {path:rel,sha256};
}
async function installedPython(sdk,platform,llvm,loaded){
  const facts=llvm.pythonSource;
  if(!facts||facts.source?.status==='unresolved')return {component:'python',
    source:facts?.source??unresolved('original Python producer source inputs missing'),
    build:{configuration:llvm.pythonConfiguration,observed:llvm.pythonInstallation?.observed},artifacts:loaded};
  const {source:origin,build,artifacts}=facts,selected=llvm.pythonConfiguration?.selected;
  const sha=value=>/^[0-9a-f]{64}$/.test(value||'');
  if(origin?.status!=='resolved'||origin.kind!=='archive'||!/^https?:\/\//.test(origin.url||'')
    ||!/^3\.11\.\d+$/.test(origin.version||'')||!sha(origin.sha256)
    ||selected?.version?.split(/\s/)[0]!==origin.version
    ||llvm.pythonInstallation?.observed?.version?.split(/\s/)[0]!==origin.version)
    throw new Error('INSTALLED_PYTHON_SOURCE');
  if(!build?.producer?.repository||!/^[0-9a-f]{40}$/.test(build.producer.commit||'')
    ||!sha(build.originalInputs?.sha256)||!build.originalInputs.path
    ||build.configuration?.target!==platform||!build.configuration.host
    ||(platform==='windows_x86_64'
      ? ![null,''].includes(build.configuration.configure)&&typeof build.configuration.configure!=='string'
      : typeof build.configuration.configure!=='string'||!build.configuration.configure)
    ||build.configuration.configure!==(selected.configure??null))
    throw new Error('INSTALLED_PYTHON_CONFIGURATION');
  const native=sdkPlatform(platform),names=artifacts?.map(row=>row.path);
  const interpreter='third_party/llvm/'+(native.os==='win32'?'python.exe':'bin/python3.11');
  if(!Array.isArray(artifacts)||artifacts.length!==3||new Set(names).size!==3
    ||!names.includes(interpreter)||names.filter(name=>name?.endsWith('/Python.h')).length!==1
    ||names.filter(name=>/\/(?:libpython3\.11[^/]*|python311\.lib)$/.test(name||'')).length!==1)
    throw new Error('INSTALLED_PYTHON_ARTIFACTS');
  const products=[];
  for(const row of artifacts){
    if(!row.path.startsWith('third_party/llvm/')||!sha(row.sha256))throw new Error('INSTALLED_PYTHON_ARTIFACTS');
    relative(row.path);
    const root=await fs.realpath(sdk),actual=await fs.realpath(path.join(root,row.path));
    if(!actual.startsWith(root+path.sep))throw new Error('INSTALLED_PYTHON_ESCAPE '+row.path);
    products.push(await artifact(sdk,row.path,row.sha256));
  }
  let installation;
  if(platform==='windows_x86_64'){
    const record=facts.installation?.record;
    if(record?.path!=='third_party/llvm/PYTHON-BUILD-INPUTS.json'||!sha(record.sha256))throw Error('INSTALLED_PYTHON_ORIGINAL');
    const actual=await readWindowsPythonInstallation(path.join(sdk,'third_party/llvm'),{sha256:record.sha256});
    if(actual.facts.source.url!==origin.url||actual.facts.source.sha256!==origin.sha256||actual.facts.source.version!==origin.version)throw Error('INSTALLED_PYTHON_SOURCE');
    installation={record,entries:actual.entries,artifacts:actual.artifacts.map(row=>({...row,path:'third_party/llvm/'+row.path}))};
  }
  return {component:'python',source:origin,build:{...build,observed:llvm.pythonInstallation.observed},
    ...(installation?{installation}:{}),
    artifacts:products,loadedArtifacts:loaded};
}
export async function installedInputs(sdk,platform){
  const native=sdkPlatform(platform),stage=await optional(path.join(sdk,'STAGE-INPUTS.json')),
    compiler=await optional(path.join(sdk,'compiler-inputs.json')),tools=await optional(path.join(sdk,'TOOLS-INPUTS.json'));
  const rows=[];
  const nativeRecord='share/cjcj/build-inputs/native-build.json';
  const nativeFacts=await optional(path.join(sdk,nativeRecord));
  const astRecord='share/cjcj/build-inputs/native-ast.json',astFacts=await optional(path.join(sdk,astRecord))??nativeFacts;
  if(astFacts){
    const selected=stage?.sources?.ast;
    if(!selected?.repository||!/^[a-f0-9]{40}$/.test(selected.commit||''))throw Error('INSTALLED_AST_SOURCE');
    const ast=await readInstalledNativeAst({install:sdk,facts:astFacts,platform,commit:selected.commit,llvmCommit:stage.sources.llvm?.commit});
    rows.push({component:'ast-support',source:source(selected),build:ast.build,
      artifacts:await Promise.all(Object.entries(ast.files).map(([rel,row])=>artifact(sdk,rel,row.sha256)))});
  }else if(stage?.sources?.ast) {
    // Ordinary build.py installation records its own commands and sources. It
    // does not pretend to be a native-cjdb producer or synthesize its facts.
    const production=stage.configuration?.layout==='native-output'?stage.production:null;
    if(!production?.commands?.length)throw Error('INSTALLED_AST_ORIGINAL_RECORD');
    const build=production.commands.filter(row=>row.stage?.startsWith('compiler.'));
    if(!build.some(row=>row.stage.startsWith('compiler.install'))||build.some(row=>row.exitCode!==0||row.error))throw Error('INSTALLED_NATIVE_PRODUCTION');
    rows.push({component:'ast-support',source:source(stage.sources.ast),build:{commands:build},
      artifacts:await Promise.all(['lib/'+native.tuple+'/libcangjie-ast-support.a','schema/StdAstFormat.fbs',
        'include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc'+native.exe].map(rel=>artifact(sdk,rel)))});
    rows.push({component:'llvm-cjdb',source:source(stage.sources.llvm),build:{commands:build},
      artifacts:await Promise.all(['third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary,
        ...['llc','llvm-as','llvm-dis','opt'].map(name=>'.native-tools/third_party/llvm/bin/'+name+native.exe)].map(rel=>artifact(sdk,rel)))});
  }
  if(stage?.compilerFile){
    if(compiler?.commit&&compiler.commit!==stage.compilerCommit)throw new Error('INSTALLED_COMPILER_SOURCE');
    rows.push({component:'compiler',source:source(stage.sources?.compiler),
      artifact:await artifact(sdk,stage.compilerFile,compiler?.compilerSha256??stage.compilerSha256),
      build:{...compiler,configuration:stage.configuration},
      entry:await artifact(sdk,'bin/cjcj-stage1'+native.exe,stage.compilerEntrySha256)});
  }else rows.push({component:'compiler',source:unresolved('STAGE-INPUTS compiler missing')});
  const runtime=await optional(path.join(sdk,RUNTIME_INPUTS));
  if(runtime){
    if(!Array.isArray(runtime.artifacts)||runtime.artifacts.length<2)throw new Error('INSTALLED_RUNTIME_PAIR');
    const products=[];
    for(const row of runtime.artifacts){
      const value=await artifact(sdk,row.path,row.sha256);
      const stamps=embeddedStamp(await fs.readFile(path.join(sdk,row.path)),'CJRT-COMMIT');
      if(stamps.length!==1||'CJRT-COMMIT:'+stamps[0]!==runtime.embedded_stamp)throw new Error('INSTALLED_RUNTIME_STAMP');
      if(/^src-/.test(stamps[0]))await runtimeInputsForArtifact(sdk,value,{repository:runtime.source.repository,commit:runtime.source.commit,stamp:runtime.embedded_stamp});
      else if(stamps[0]!==runtime.source.commit)throw new Error('INSTALLED_RUNTIME_SOURCE');
      products.push(value);
    }
    rows.push({component:'runtime',...runtime,artifacts:products});
  }else rows.push({component:'runtime',source:source(stage?.sources?.runtime),build:{status:'unresolved',reason:'original runtime inputs missing'}});
  const stdProvenance=path.join(sdk,'PROVENANCE.txt');
  try{
    const text=await fs.readFile(stdProvenance,'utf8'),commit=text.match(/^STD_SOURCE_COMMIT\s*=\s*([0-9a-f]{40})$/m)?.[1];
    if(stage?.sources?.std?.commit&&stage.sources.std.commit!==commit)throw new Error('INSTALLED_STD_SOURCE');
    rows.push({component:'std',source:source({...stage?.sources?.std,commit}),
      artifact:await artifact(sdk,'PROVENANCE.txt'),build:{provenance:text,...await reconcileStdArtifacts(sdk,text)}});
  }catch(e){if(e.code!=='ENOENT')throw e;rows.push({component:'std',source:unresolved('original std provenance missing')});}
  const llvm=await optional(path.join(sdk,'share/cjcj/build-inputs/native-llvm.json'));
  if(llvm){
    if(llvm.rc!==0||llvm.platform!==platform)throw new Error('INSTALLED_NATIVE_INPUT');
    if(!Array.isArray(llvm.artifacts)||llvm.artifacts.length<2)throw new Error('INSTALLED_NATIVE_ARTIFACTS');
    const products=[];
    for(const product of llvm.artifacts??[]){
      const rel=product.path.startsWith('tools/bin/')?'.native-tools/'+product.path:product.path;
      products.push(await artifact(sdk,rel,product.sha256));
    }
    const python=[];
    for(const [original,sha]of Object.entries(llvm.pythonInstallation?.loaded??{})){
      const nativePath=native.os==='win32'?path.win32:path.posix;
      const rel=nativePath.relative(llvm.install,original).split(nativePath.sep).join('/');
      python.push(await artifact(sdk,rel,sha));
    }
    let windowsToolchain;
    if(llvm.windowsToolchain) {
      const input=llvm.windowsToolchain;
      const original=await artifact(sdk,input.original.path,input.original.sha256);
      const installedFiles=await Promise.all(input.installedFiles.map(row=>artifact(sdk,row.path,row.sha256)));
      windowsToolchain={...input,original,installedFiles};
    }
    rows.push({component:'llvm-cjdb',source:source(llvm.source),build:{configuration:llvm.configuration,python:llvm.pythonConfiguration,...(windowsToolchain?{windowsToolchain}:{})},artifacts:products});
    rows.push(await installedPython(sdk,platform,llvm,python));
  }
  for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat']){
    const rel='tools/bin/'+name+native.exe,row=tools?.files?.[rel];
    if(!row){rows.push({component:name,source:unresolved('original tool producer inputs missing')});continue;}
    const retained='.target-tools/'+rel;
    const product=await artifact(sdk,retained,row.sha256);
    const install=row.producer?.install;
    const installedArtifact=install===undefined?row.producer?.artifact:install?.artifact;
    if(install!==undefined&&(install?.rc!==0||!installedArtifact?.sha256))throw new Error('INSTALLED_TOOL_PRODUCER '+name);
    if(installedArtifact?.sha256&&installedArtifact.sha256!==product.sha256)throw new Error('INSTALLED_TOOL_PRODUCER '+name);
    const recipe=(await fs.readFile(path.join(sdk,rel+'.entry'),'utf8')).trimEnd().split('\n');
    if(recipe[0]!=='cjcj-sdk-entry-v1'||recipe[2]!==retained)throw new Error('INSTALLED_TOOL_ENTRY '+name);
    rows.push({component:name,source:row.producer?.source??unresolved('original tool source missing'),
      build:row.producer?.build,artifact:product,entry:{...await artifact(sdk,rel,row.entry?.sha256),
        recipe:await artifact(sdk,rel+'.entry',row.entry?.recipe?.sha256)}});
  }
  for(const [rel,row]of Object.entries(tools?.payloadFiles??{}))await artifact(sdk,rel,row.sha256);
  // Native LLVM/cjdb/Python installation and HLE dependencies keep their own
  // real consumer checks. Carry their original records without claiming those
  // checks were rerun by this inventory reader.
  if(await optional(path.join(sdk,STDX_BUILD_INPUTS))) rows.push(await readInstalledStdxInputs({sdk,platform}));
  const records={};

  for(const rel of ['STAGE-INPUTS.json','compiler-inputs.json',RUNTIME_INPUTS,'TOOLS-INPUTS.json','tools/dtsparser/DEPENDENCIES.json','share/cjcj/build-inputs/native-llvm.json',nativeRecord,astRecord,STDX_BUILD_INPUTS])
    if(await optional(path.join(sdk,rel)))records[rel]=await artifact(sdk,rel);
  return {components:rows,inputs:records};
}
