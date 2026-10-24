#!/usr/bin/env zx
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {prepareBootstrapEnvironment} from './prepare-bootstrap-plans.mjs';
import {bootstrap} from './bootstrap.mjs';
export async function runBootstrapJob(stage,env=process.env){
 const {config}=await prepareBootstrapEnvironment(env);
 const from=env.CJCJ_SDK_FROM || { 'stage1-initial-std':'std-bootstrap','stage1-std':'stage1-std','stage1-compiler':'stage2',all:'stage3-std'}[stage];
 return bootstrap({config,stage,from,packageOutput:false});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{await runBootstrapJob(process.argv[2]);}catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
