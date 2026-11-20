#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {archiveInstall,atomicJson,readJson} from '../../bootstrap/sdk-flow.mjs';
import {verifyInstall} from '../../bootstrap/sdk-verify-install.mjs';
import {assertSdkCompilerRuntimeAbi} from '../../../build/lib/runtime-split.mjs';
import {assertSdkPathParity} from '../../../build/lib/sdk-path-parity.mjs';
import {assertNoVerifierReportArtifacts} from '../../../scripts/verifier_artifact_gate.mjs';
import {installedInputs} from './installed-inputs.mjs';
import {writeInstalledReleaseManifest} from '../../../build/lib/release-manifest.mjs';
export function packageConsumption(target){
 const platform=target?.spec?.llvmPlatform??null;
 if(target?.spec?.crossCompile===true)return {status:'NOT_RUN',reason:'HOST_CROSS_EXEC',platform};
 return {status:'EXECUTED',platform};
}
export async function packageInstall({sdk,target,version,officialSdkRoot,archive,sourcePair}){
 assertNoVerifierReportArtifacts([sdk]);assertSdkCompilerRuntimeAbi({sdk,target});
 await assertSdkPathParity(sdk,{officialRoot:officialSdkRoot,target:target.spec.key});
 if(sourcePair){
  const {sources,selection}=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  if(sources?.runtime?.commit!==sourcePair.runtime || sources?.std?.commit!==sourcePair.runtime
    || (sources?.backend??sources?.llvm)?.commit!==sourcePair.llvm
    || (sourcePair.hostVersion && selection?.bootstrapHost?.version!==sourcePair.hostVersion))
   throw Error('SDK_PACKAGE_SOURCE_PAIR');
 }
 const work=path.join(path.dirname(archive),'package-test');
 const consumption=packageConsumption(target);
 const packageRegex=['linux-x64','linux-aarch64'].includes(target.spec.key);
 if(consumption.status==='EXECUTED'){
  await verifyInstall({sdk,work:work+'/installed',platform:target.spec.llvmPlatform,finalStd:true,precompiledStdx:true,packageRegex});
 }else await atomicJson(path.join(work,'cross-consumption.json'),consumption);
 const inputs=await installedInputs(sdk,target.spec.llvmPlatform);
 if(sourcePair){
  const components = new Map(inputs.components.map(row=>[row.component,row.source]));
  for(const [name,want] of [['runtime',sourcePair.runtime],['std',sourcePair.runtime],
    [components.has('llvm-backend')?'llvm-backend':'llvm-cjdb',sourcePair.llvm]]){
   const actual=components.get(name);
   if(actual?.status!=='resolved'||actual.commit!==want) throw Error('SDK_PACKAGE_INSTALLED_PAIR '+name);
  }
 }
 await writeInstalledReleaseManifest({stage:sdk,platform:target.spec.llvmPlatform,...inputs});
 await atomicJson(path.join(sdk,'BUILD-MANIFEST.json'),{version,target:target.spec.key,consumption,...inputs});
 const test=consumption.status==='EXECUTED'?{commands:[{argv:[process.execPath,fileURLToPath(new URL('../../bootstrap/sdk-verify-install.mjs',import.meta.url)),
  '--sdk','${install}','--work','${work}/relocated','--platform',target.spec.llvmPlatform,'--final-std','--precompiled-stdx',...(packageRegex?['--package-regex']:[])]}]}:{commands:[],consumption};
 const archived=await archiveInstall({install:sdk,archive,format:target.spec.archiveFormat,test,vars:{work},records:[]});
 return {...archived,consumption};
}
