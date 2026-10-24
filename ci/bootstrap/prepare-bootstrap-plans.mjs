#!/usr/bin/env zx
// Compatibility filename used by existing job launchers; no plan freezing.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {readJson,atomicJson,targetOrder} from './sdk-flow.mjs';
import {prepareNativeInputs} from './sdk-inputs.mjs';
import {createBootstrapTargets,validateBootstrapTargets,bootstrapPhases} from './sdk-targets.mjs';
export async function prepareBootstrapEnvironment(env=process.env){
 let config=env.CJCJ_SDK_TARGETS;
 if(!config){
  if(!env.CJCJ_SDK_INPUTS&&env.CJCJ_NATIVE_INPUTS)env.CJCJ_SDK_INPUTS=await prepareNativeInputs(await readJson(env.CJCJ_NATIVE_INPUTS),env);
  if(!env.CJCJ_SDK_INPUTS||!env.CANGJIE_WORKSPACE)throw new Error('CJCJ_SDK_TARGETS or CJCJ_SDK_INPUTS with workspace required');
  const targets=createBootstrapTargets({...await readJson(env.CJCJ_SDK_INPUTS),finalStd:path.join(env.CANGJIE_WORKSPACE,'software/final-std-stage2')});
  config=path.join(env.CANGJIE_WORKSPACE,'build-targets.json');await atomicJson(config,targets);
 }
 const targets=await readJson(config);targetOrder(targets.stages,targets.finalStage);
 for(const phase of bootstrapPhases(targets.bootstrapInputs||{}))if(!targets.stages.some(s=>s.id===phase))throw new Error('BOOTSTRAP_PHASE_MISSING '+phase);
 validateBootstrapTargets(targets);
 if(env.GITHUB_ENV)await fs.appendFile(env.GITHUB_ENV,`CJCJ_SDK_TARGETS=${path.resolve(config)}\n`);
 return {config:path.resolve(config),phases:bootstrapPhases(targets.bootstrapInputs)};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(await prepareBootstrapEnvironment()));}catch(e){console.error(e.message);process.exitCode=1;}
}
