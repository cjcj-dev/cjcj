#!/usr/bin/env zx
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {buildFlow,readJson,targetOrder} from './sdk-flow.mjs';
import {bootstrapPhases,validateBootstrapTargets} from './sdk-targets.mjs';
export const BOOTSTRAP_JOBS=Object.freeze({stage0:'stage0-run','stage1-initial-std':'stage1-initial','stage1-std':'stage1-std',
 'stage1-compiler':'stage2',stage1:'stage2','stage2-target-sdk':'stage2-target-sdk',all:'stage3'});
export async function bootstrap({config,stage='all',dryRun=false,from,packageOutput=true}){
 if(!config||!BOOTSTRAP_JOBS[stage])throw new Error('BOOTSTRAP_TARGET_CONFIG_REQUIRED');
 const targets=typeof config==='string'?await readJson(config):config;
 for(const phase of bootstrapPhases(targets.bootstrapInputs||{}))if(!targets.stages.some(s=>s.id===phase))throw new Error('BOOTSTRAP_PHASE_MISSING '+phase);
 validateBootstrapTargets(targets);
 const through=stage==='all'?targets.finalStage:BOOTSTRAP_JOBS[stage];
 if(dryRun)return targetOrder(targets.stages,through).map(s=>({id:s.id,commands:s.commands,copies:s.copies}));
 return buildFlow(targets,{through,from,packageOutput:packageOutput&&(stage==='all'||through===targets.finalStage)});
}
export async function main(args=process.argv.slice(2)){
 const {values}=parseArgs({args,options:{config:{type:'string'},stage:{type:'string',default:'all'},from:{type:'string'},'dry-run':{type:'boolean'}}});
 return bootstrap({config:values.config,stage:values.stage,from:values.from,dryRun:values['dry-run']});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(await main()));}catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
