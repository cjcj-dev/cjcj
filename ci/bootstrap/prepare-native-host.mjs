#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectNativeHost} from './select-native-host.mjs';
import {generateFreeze} from '../generate-freeze.mjs';
import {withProcessCancellation} from './sdk-flow.mjs';
try {
 await withProcessCancellation(async signal=>{
  try {
  const env=process.env;
  for(const name of ['GITHUB_WORKSPACE','GITHUB_ENV','CJCJ_NATIVE_INPUT_ROOT','RUNNER_TEMP'])
    if(!env[name])throw new Error(name+' required');
  const selected=await selectNativeHost(env.CJCJ_NATIVE_INPUT_ROOT,path.join(env.GITHUB_WORKSPACE,'.srcbuild/host-execution'),env,signal);
  signal.throwIfAborted();
  const output={CJCJ_BOOTSTRAP_BASE:selected.host.install,CJCJ_BOOTSTRAP_BASE_ARCHIVE:selected.host.archive,
    CJCJ_OFFICIAL_SDK_ROOT:selected.host.install,CJCJ_SRCBUILD_BOOTSTRAP_SDK:selected.host.install,
    CANGJIE_HOME:selected.host.install,CANGJIE_STDX_PATH:'',
    CJCJ_TOOLCHAIN:'nightly-'+selected.host.version,CJCJ_ACTUAL_HOST_TOOLCHAIN:'nightly-'+selected.host.version};
  if(env.CJCJ_SRCBUILD_TARGET==='linux-x64') {
    const frozen=await generateFreeze({repo:env.GITHUB_WORKSPACE,baseSdk:selected.host.archive,
      workflowRef:env.GITHUB_SHA,evidenceRoot:path.join(env.GITHUB_WORKSPACE,'.srcbuild/g2-campaigns'),selectedInputs:selected});
    output.G2_IDENTITY=frozen.g2IdentityFile;output.G2_CAMPAIGN_DIR=frozen.campaignDir;
  }
  signal.throwIfAborted();
  await fs.appendFile(env.GITHUB_ENV,Object.entries(output).map(([key,value])=>key+'='+value).join('\n')+'\n');
  if(env.GITHUB_PATH)await fs.appendFile(env.GITHUB_PATH,[path.join(selected.host.install,'bin'),path.join(selected.host.install,'tools/bin')].join('\n')+'\n');
  } catch(error) {
    // The selector awaits collector cleanup before propagating cancellation.
    // Preserve the process cancellation rc, without hiding native child facts.
    signal.throwIfAborted();throw error;
  }
 });
}catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
