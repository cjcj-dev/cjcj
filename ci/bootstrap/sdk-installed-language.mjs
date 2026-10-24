#!/usr/bin/env zx
// Keep the existing gc_unit language gate on the final native installation.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {buildConfig} from '../../build/lib/config.mjs';
import {runGcUnitLanguageTests,gcUnitLanguageGateEnabled} from '../../build/srcbuild/gc-unit-gate.mjs';
import {cleanSdkEnvironment} from './sdk-platform.mjs';

export function installedLanguageConfig({sdk,platform,host,work}) {
  const targetKey={linux_x86_64:'linux-x64',linux_aarch64:'linux-aarch64'}[platform];
  if(!targetKey||!sdk||!host||!work)throw new Error('INSTALLED_LANGUAGE_INPUT_REQUIRED');
  const config=buildConfig({workspace:work,consumerSdk:sdk,targetKey,officialSdkRoot:host});
  const env={...cleanSdkEnvironment(sdk,platform),CJCJ_SRCBUILD_HOST_SDK:host,
    GC_UNIT_OUT:path.join(work,'gc-unit'),cjHeapSize:process.env.cjHeapSize||'2GB'};
  if(!gcUnitLanguageGateEnabled(config,env))throw new Error('INSTALLED_LANGUAGE_DISABLED');
  return {config,env};
}
export async function verifyInstalledLanguage(options) {
  const {config,env}=installedLanguageConfig(options);
  await runGcUnitLanguageTests(config,options.sdk,{env,source:options.runtimeSource});
}
export async function installedLanguage({source,sdk,platform,host,work,runtimeSource}) {
  // Default and explicit inputs use one execution path; even a completed
  // previous run must execute this invocation's language consumers again.
  await verifyInstalledLanguage({sdk,platform,host,work,runtimeSource});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const {values}=parseArgs({options:Object.fromEntries(
      ['source','sdk','platform','host','work','runtime-source'].map(name=>[name,{type:'string'}]))});
    await installedLanguage({...values, runtimeSource: values['runtime-source']});
  }catch(error){console.error(error.stack);process.exitCode=error.rc||error.exitCode||1;}
}
