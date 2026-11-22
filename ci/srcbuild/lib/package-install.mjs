#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {archiveInstall,atomicJson} from '../../bootstrap/sdk-flow.mjs';
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
export async function packageInstall({sdk,target,version,officialSdkRoot,archive}){
 assertNoVerifierReportArtifacts([sdk]);assertSdkCompilerRuntimeAbi({sdk,target});
 await assertSdkPathParity(sdk,{officialRoot:officialSdkRoot,target:target.spec.key});
 const work=path.join(path.dirname(archive),'package-test');
 const consumption=packageConsumption(target);
 const java=target.spec.key==='linux-x64';
 const packageRegex=['linux-x64','linux-aarch64'].includes(target.spec.key);
 if(consumption.status==='EXECUTED'){
  await verifyInstall({sdk,work:work+'/installed',platform:target.spec.llvmPlatform,finalStd:true,precompiledStdx:true,packageRegex,java});
 }else await atomicJson(path.join(work,'cross-consumption.json'),consumption);
 const inputs=await installedInputs(sdk,target.spec.llvmPlatform);
 for(const name of ['runtime','std','llvm-cjdb',...(java?['java-interop']:[])]){
   if(!inputs.components.some(row=>row.component===name && row.source?.status==='resolved' && (row.artifact||row.artifacts?.length)))
     throw Error('SDK_PACKAGE_ORIGINAL_REQUIRED '+name);
 }
 await writeInstalledReleaseManifest({stage:sdk,platform:target.spec.llvmPlatform,...inputs});
 await atomicJson(path.join(sdk,'BUILD-MANIFEST.json'),{version,target:target.spec.key,consumption,...inputs});
 const test=consumption.status==='EXECUTED'?{commands:[{argv:[process.execPath,fileURLToPath(new URL('../../bootstrap/sdk-verify-install.mjs',import.meta.url)),
  '--sdk','${install}','--work','${work}/relocated','--platform',target.spec.llvmPlatform,'--final-std','--precompiled-stdx',...(java?['--java']:[]),...(packageRegex?['--package-regex']:[])]}]}:{commands:[],consumption};
 const archived=await archiveInstall({install:sdk,archive,format:target.spec.archiveFormat,test,vars:{work},records:[]});
 return {...archived,consumption};
}
