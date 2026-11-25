#!/usr/bin/env zx
// Compatibility filename used by existing job launchers; no plan freezing.
import fs from 'node:fs/promises';
import path from 'node:path';
import {isDeepStrictEqual} from 'node:util';
import {fileURLToPath} from 'node:url';
import {readJson,atomicJson,targetOrder} from './sdk-flow.mjs';
import {prepareNativeInputs} from './sdk-inputs.mjs';
import {createBootstrapTargets,validateBootstrapTargets,bootstrapPhases} from './sdk-targets.mjs';
export async function prepareBootstrapEnvironment(env=process.env){
 const workspace=env.CANGJIE_WORKSPACE;
 if(!workspace&&!env.CJCJ_SDK_TARGETS)throw new Error('CJCJ_SDK_TARGETS or workspace required');
 const config=env.CJCJ_SDK_TARGETS || path.join(workspace,'build-targets.json');
 if(!env.CJCJ_SDK_TARGETS){
  const explicit=env.CJCJ_SDK_INPUTS || env.CJCJ_NATIVE_INPUTS;
  const existing=await fs.lstat(config).catch(error=>{if(error.code!=='ENOENT')throw error;});
  if(!explicit && existing){
   const inputs=await readJson(path.join(workspace,'native-bootstrap','sdk-inputs.json'));
   const targets=await readJson(config);
   if(!isDeepStrictEqual(targets.bootstrapInputs,{...inputs,finalStd:path.join(workspace,'software/final-std-stage2')}))throw Error('BOOTSTRAP_TARGET_INPUT_MISMATCH');
  }else{
   const file=env.CJCJ_SDK_INPUTS || (env.CJCJ_NATIVE_INPUTS
    ? await prepareNativeInputs(await readJson(env.CJCJ_NATIVE_INPUTS),env)
    : path.join(workspace,'native-bootstrap','sdk-inputs.json'));
   const targets=createBootstrapTargets({...await readJson(file),finalStd:path.join(workspace,'software/final-std-stage2')});
   await atomicJson(config,targets);
  }
 }
 const targets=await readJson(config);targetOrder(targets.stages,targets.finalStage);
 for(const phase of bootstrapPhases(targets.bootstrapInputs||{}))if(!targets.stages.some(s=>s.id===phase))throw new Error('BOOTSTRAP_PHASE_MISSING '+phase);
 validateBootstrapTargets(targets);
 return {config:path.resolve(config),phases:bootstrapPhases(targets.bootstrapInputs)};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(await prepareBootstrapEnvironment()));}catch(e){console.error(e.message);process.exitCode=1;}
}
