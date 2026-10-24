import {hostPlatform,readHostToolchainPin} from '../host-toolchain-pin.mjs';
import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import path from'node:path';import {spawnSync}from'node:child_process';import {prepareBootstrapEnvironment}from'../bootstrap/prepare-bootstrap-plans.mjs';import {BOOTSTRAP_PHASES,createBootstrapTargets,FIXED_INPUTS}from'../bootstrap/sdk-targets.mjs';import {targetOrder}from'../bootstrap/sdk-flow.mjs';import {remoteCommand}from'../../tools/srcbuild-kkk2.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');await fs.mkdir(parent,{recursive:true});
const stages=BOOTSTRAP_PHASES.map((id,index)=>({id,depends:index?[BOOTSTRAP_PHASES[index-1]]:[],commands:[]}));
function nativeConfig(root) {
 const platform=hostPlatform(),row=(commit,name)=>({commit,tree:'a'.repeat(40),repository:root+'/'+name+'.git',install:root+'/'+name,configuration:{fixture:true},buildResult:root+'/'+name+'/result.json'}),runtime=row(FIXED_INPUTS.runtime,'runtime');
 return createBootstrapTargets({platform,work:root+'/work',install:root+'/sdk',host:{install:root+'/host',version:readHostToolchainPin(platform).replace(/^nightly-/,'')},llvm:row(FIXED_INPUTS.llvm,'llvm'),runtime,ast:row(FIXED_INPUTS.compiler,'ast'),h1:row(FIXED_INPUTS.h1,'h1'),compiler:row('b'.repeat(40),'compiler'),stdlib:{...runtime},tools:{privateRoot:root+'/tools'}});
}
test('GHA preparation and controlled native launcher select the same target configuration',async()=>{
 const root=await fs.mkdtemp(path.join(parent,'target-entry-')),config=path.join(root,'targets.json'),environment=path.join(root,'env');const targets=nativeConfig(root);await fs.writeFile(config,JSON.stringify(targets));
 const prepared=await prepareBootstrapEnvironment({CJCJ_SDK_TARGETS:config,GITHUB_ENV:environment});assert.equal(prepared.config,config);assert.deepEqual(prepared.phases,BOOTSTRAP_PHASES);assert.match(await fs.readFile(environment,'utf8'),/CJCJ_SDK_TARGETS=/);
 const result=spawnSync(process.execPath,[new URL('../bootstrap/bootstrap.mjs',import.meta.url).pathname,'--config',config,'--stage','all','--dry-run'],{encoding:'utf8'});assert.equal(result.status,0,result.stderr);assert.deepEqual(JSON.parse(result.stdout).map(s=>s.id),targetOrder(targets.stages,'stage3').map(s=>s.id));
 const command=remoteCommand({source:'/root/lane/source',config:'/root/lane/targets.json',through:'stage3'});assert.match(command,/'--config' '\/root\/lane\/targets.json'/);assert.match(command,/'--through' 'stage3'/);
});
test('missing phase, invalid dependencies and absent configuration refuse before native execution',async()=>{
 const root=await fs.mkdtemp(path.join(parent,'target-reject-')),config=path.join(root,'targets.json');
 await assert.rejects(prepareBootstrapEnvironment({}),/CJCJ_SDK_TARGETS/);
 await fs.writeFile(config,JSON.stringify({stages:stages.slice(0,-1),finalStage:'stage3-std'}));await assert.rejects(prepareBootstrapEnvironment({CJCJ_SDK_TARGETS:config}),/BOOTSTRAP_PHASE_MISSING/);
 await fs.writeFile(config,JSON.stringify({stages:[...stages.slice(0,-1),{id:'stage3',depends:['missing']}],finalStage:'stage3'}));await assert.rejects(prepareBootstrapEnvironment({CJCJ_SDK_TARGETS:config}),/TARGET_DEPENDENCY/);
});
