#!/usr/bin/env zx
// The actual frozen production plan and CLI, without builds or model copies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import assert from 'node:assert/strict';
const root=process.env.STAGE1_PLAN_EVIDENCE,planFile=process.env.STAGE1_FROZEN_PLAN;
assert.ok(root&&planFile,'actual frozen plan and explicit evidence root required');
await fs.mkdir(root,{recursive:true});
const entry=fileURLToPath(new URL('./toolchain-sdk.mjs',import.meta.url));
const plan=JSON.parse(await fs.readFile(planFile,'utf8'));
async function invoke(name,change=()=>{}){const input=structuredClone(plan);change(input);const file=path.join(root,`${name}.plan.json`);await fs.writeFile(file,JSON.stringify(input)+'\n');const argv=[entry,'--plan',file,'--dry-run'],start=performance.now(),r=spawnSync(process.execPath,argv,{encoding:'utf8',maxBuffer:8*1024*1024});await fs.writeFile(path.join(root,`${name}.log`),r.stdout+r.stderr);await fs.writeFile(path.join(root,`${name}.json`),JSON.stringify({argv,rc:r.status,signal:r.signal,wall:(performance.now()-start)/1000})+'\n');console.log(`TARGET_ASSERTION_EXECUTED formal-plan-${name} rc=${r.status}`);return r;}
test('formal frozen plan requires shim and libLLVM to select the same native producer',async()=>{
 const normal=await invoke('normal');assert.equal(normal.status,0,normal.stderr);
 const wrong=await invoke('wrong-shim',p=>{p.components.find(c=>c.id==='compiler').config.options.inputBindings['llvm-shim.o'].dependency='ast';});
 assert.equal(wrong.status,1);assert.match(wrong.stderr,/rule=STAGE1_LLVM component=compiler/);
 const restored=await invoke('restored');assert.equal(restored.status,0,restored.stderr);
});
test('formal plan reserves the authenticated original official host lock input', async () => {
 const normal=await invoke('host-lock-normal');assert.equal(normal.status,0,normal.stderr);
 const wrong=await invoke('host-lock-override',p=>{p.components.find(c=>c.id==='compiler').config.options.inputBindings['official-host-lock.json']={dependency:'ast',artifact:'arbitrary.json'};});
 assert.equal(wrong.status,1);assert.match(wrong.stderr,/rule=PRODUCER_RECIPE component=compiler.*reserved/);
 const restored=await invoke('host-lock-restored');assert.equal(restored.status,0,restored.stderr);
});
