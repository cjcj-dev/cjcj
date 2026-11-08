#!/usr/bin/env zx
// Source locations are checked out at fixed commits; native installation facts
// arrive in an explicitly selected build artifact, never as default empty SDKs.
import fs from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const capture=promisify(execFile);
import {configureNativeToolInput} from './native-tool-input.mjs';
import {configureHleInput} from './hle-input.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {command, readJson, privateRoot, fileDigest} from './sdk-flow.mjs';
import {prepareNativeInputs} from './sdk-inputs.mjs';
import {nativePair} from './native-runtime-input.mjs';
import {hostPlatform, readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {nativeInstallationLocations,unpackNativeInstallations} from './native-installation-locations.mjs';
import {buildConfig} from '../../build/lib/config.mjs';
import {nativeSourceSelection} from './native-source-selection.mjs';
import {stdDependencySources} from './stdlib-build.mjs';
export {NATIVE_REPOSITORIES} from './native-source-selection.mjs';
export async function nativeVerifierTools(tools,env=process.env) {
  const selected={cmake:tools.cmake||'cmake','clang++':tools.cxx,ninja:tools.ninja||'ninja',
    ...(tools.launcher?{launcher:tools.launcher}:{})};
  const result={};
  for(const [name,program] of Object.entries(selected)) {
    if(typeof program!=='string'||!program)throw Error('GHA_NATIVE_VERIFIER_TOOL '+name);
    const located=path.isAbsolute(program)?program:(await capture(process.platform==='win32'?'where':'which',[program],{env})).stdout.trim().split(/\r?\n/)[0];
    const executable=path.resolve(located);
    await fs.access(executable,fs.constants.X_OK);
    // clang++ and clang can resolve to the same bytes. Preserve the selected
    // executable name: argv[0] chooses the C++ linker driver.
    result[name]={path:executable,sha256:await fileDigest(executable)};
  }
  return result;
}
export async function configureGhaInputs(env=process.env) {
  if(!env.CANGJIE_WORKSPACE||!env.GITHUB_WORKSPACE||!env.CJCJ_NATIVE_INPUT_ROOT||!env.CJCJ_BOOTSTRAP_BASE)
    throw new Error('GHA_NATIVE_LOCATIONS_REQUIRED');
  const root=await privateRoot(env.CJCJ_NATIVE_INPUT_ROOT), workspace=await privateRoot(env.CANGJIE_WORKSPACE);
  await unpackNativeInstallations(root);
  const locations=await readJson(path.join(root,'locations.json'));
  const platform=hostPlatform(), sourcePair=nativePair(env,{requireHost:Boolean(env.CJCJ_NATIVE_RUNTIME_INSTALL)}),
    pair=env.CJCJ_NATIVE_RUNTIME_INSTALL?sourcePair:null;
  const config=buildConfig({workspace:env.CANGJIE_WORKSPACE || env.GITHUB_WORKSPACE,env});
  const compiler=config.repos.compiler;
  const {selection,explicitAst}=nativeSourceSelection(env,sourcePair,
    config.sourceSelection.compiler?{ast:{repository:compiler.url,commit:compiler.tag}}:{});
  if (Boolean(env.CJCJ_NATIVE_RUNTIME_INSTALL) !== Boolean(pair)) throw new Error('GHA_NATIVE_RUNTIME_PAIR_INSTALL_REQUIRED');
  if(locations.platform!==platform)throw new Error('GHA_NATIVE_ARTIFACT_PLATFORM');
  if(locations.hleDependencies)await configureHleInput(root,platform,env.GITHUB_ENV);
  await configureNativeToolInput({root,workspace,platform,envFile:env.GITHUB_ENV});
  const sources={compiler:path.resolve(env.GITHUB_WORKSPACE)};
  const stdDependencies=stdDependencySources();
  for(const [name,{repository:url,commit}] of Object.entries({...selection,...stdDependencies})) {
    const source=path.join(workspace,'native-sources',name);
    await fs.mkdir(path.dirname(source),{recursive:true});
    if(await fs.stat(source).catch(error=>{if(error.code==='ENOENT')return null;throw error;})) {
      const head=await capture('git',['-C',source,'rev-parse','HEAD']);
      const origin=await capture('git',['-C',source,'config','--get','remote.origin.url']);
      const dirty=await capture('git',['-C',source,'status','--porcelain']);
      if(head.stdout.trim()!==commit||origin.stdout.trim()!==url||dirty.stdout.trim())throw new Error('GHA_NATIVE_SOURCE_REUSE_CHANGED '+name);
    } else {
      await command(['git','init',source]);
      await command(['git','-C',source,'remote','add','origin',url]);
      await command(['git','-C',source,'fetch','--depth=1','origin',commit]);
      await command(['git','-C',source,'checkout','--detach',commit]);
    }
    sources[name]=source;
  }
  const member=rel=>{
    if(typeof rel!=='string'||path.isAbsolute(rel)||rel.split(/[\\/]/).includes('..'))throw new Error('GHA_NATIVE_ARTIFACT_PATH');
    return path.join(root,rel);
  };
  const resolved=await nativeInstallationLocations(root,locations,env);
  const installations=Object.fromEntries(['llvm','runtime','ast'].map(name=>{
    if (name === 'runtime' && pair) return [name, {install:path.resolve(env.CJCJ_NATIVE_RUNTIME_INSTALL),
      ...(env.CJCJ_NATIVE_RUNTIME_SOURCE ? {sourceRoot:path.resolve(env.CJCJ_NATIVE_RUNTIME_SOURCE)} : {})}];
    const row=resolved[name];
    if(!row)throw Error('GHA_NATIVE_INSTALLATION_REQUIRED '+name);
    return [name,row];
  }));
  const selectedHost = pair && locations.host ? {...locations.host, install:member(locations.host.install),
    ...(locations.host.archive ? {archive:member(locations.host.archive)} : {})} : {install:env.CJCJ_BOOTSTRAP_BASE,
    archive:env.CJCJ_BOOTSTRAP_BASE_ARCHIVE, version:readHostToolchainPin(platform).replace(/^nightly-/,'')};
  if (pair && (path.resolve(selectedHost.install) !== path.resolve(env.CJCJ_BOOTSTRAP_BASE)
    || !selectedHost.archive || path.resolve(selectedHost.archive) !== path.resolve(env.CJCJ_BOOTSTRAP_BASE_ARCHIVE || '')))
    throw new Error('GHA_NATIVE_SELECTED_HOST_CHANGED');
  const tools={...locations.tools,
    cc:env.CC||'clang',cxx:env.CXX||'clang++',launcher:env.CMAKE_CXX_COMPILER_LAUNCHER||'sccache',zx:'zx'};
  installations.llvm.verification={...installations.llvm.verification,tools:await nativeVerifierTools(tools,env)};
  if(env.GITHUB_ENV)await fs.appendFile(env.GITHUB_ENV,'CJCJ_BOOTSTRAP_WORK='+path.join(workspace,'native-bootstrap')+'\n');
  return prepareNativeInputs({platform,sources,installations,tools,sourceSelection:selection,
    stdDependencies:Object.fromEntries(Object.entries(stdDependencies).map(([name,row])=>[name,{...row,root:sources[name]}])),
    ...(explicitAst?{astCommit:selection.ast.commit}:{}),
    ...(pair?{nativePair:pair,llvmCommit:pair.llvm,runtimeCommit:pair.runtime}:{}),
    work:path.join(workspace,'native-bootstrap'),install:path.join(workspace,'software','cangjie'),
    host:selectedHost},env);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{await configureGhaInputs();}catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
