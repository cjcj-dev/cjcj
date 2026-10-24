#!/usr/bin/env zx
// Public first/resume/dirty/failure/cancellation obligations live in the
// registered native-wiring matrix. Here keep current linkage and process tests;
// retired instruction-shape predicates are not a language semantic contract.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {getEventListeners} from 'node:events';
import {assertStdBarriers, streamStdProcess} from '../srcbuild/lib/assert-std-barriers.mjs';
import {prepareRuntimeInputs} from './sdk-native-stage.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {copyOutputs, inventory} from './sdk-flow.mjs';
const base=process.env.STD_BARRIER_TEST_ROOT;
if(!base)throw new Error('STD_BARRIER_TEST_ROOT required');
await fs.mkdir(base,{recursive:true});
const root=await fs.mkdtemp(path.join(base,'current-'));
const run=(exe,args)=>{const p=spawnSync(exe,args,{encoding:'utf8'});assert.equal(p.status,0,p.stderr);};
const write=async(file,body)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,body);};
const native=sdkPlatform('linux_x86_64');
test('runtime snapshot first/equal/changed/partial/aborted preserves complete inputs and old evidence',async()=>{
 const runtime=root+'/runtime',link=root+'/runtime-input';
 await write(runtime+'/lib/'+native.tuple+'/cjld.lds','first');
 await write(runtime+'/runtime/lib/'+native.tuple+'/runtime.so','fixture');
 const args={runtime,link,native};
 await prepareRuntimeInputs(args);
 const old=await inventory(link),stat=await fs.stat(link);
 await prepareRuntimeInputs(args);assert.equal((await fs.stat(link)).ino,stat.ino);
 await prepareRuntimeInputs({...args,resume:true});
 await write(runtime+'/lib/'+native.tuple+'/cjld.lds','changed');
 await assert.rejects(prepareRuntimeInputs({...args,resume:true}),/STD_RESUME_RUNTIME_INPUT_CHANGED/);
 assert.deepEqual(await inventory(link),old);
 await assert.rejects(prepareRuntimeInputs({...args,signal:AbortSignal.abort(new Error('fixture cancel'))}),/fixture cancel/);
 assert.deepEqual(await inventory(link),old);
 await prepareRuntimeInputs(args);
 const retained=(await fs.readdir(root)).find(n=>n.startsWith('runtime-input.previous-'));
 assert(retained);assert.deepEqual(await inventory(root+'/'+retained),old);
 assert.equal(await fs.readFile(link+'/common/linux_relwithdebinfo_x86_64/lib/'+native.tuple+'/cjld.lds','utf8'),'changed');
 await write(link+'/stale','old extra');
 await prepareRuntimeInputs(args);assert.equal((await inventory(link)).stale,undefined);
 const partial=root+'/partial';await write(partial+'/incomplete','preserved');
 await prepareRuntimeInputs({...args,link:partial});
 assert((await fs.readdir(root)).some(n=>n.startsWith('partial.previous-')));
 const bad=root+'/bad-link';await fs.symlink(link,bad);
 await assert.rejects(prepareRuntimeInputs({...args,link:bad}),/INSTALL_LINK/);
});
test('ordinary install collisions remain rejected, including equal bytes',async()=>{
 const input=root+'/install-source';await write(input,'same');
 const output=root+'/install';await copyOutputs(output,[{from:input,to:'file',owner:'one'}]);
 await assert.rejects(copyOutputs(output,[{from:input,to:'file',owner:'two'}]),/INSTALL_CONFLICT/);
});
test('linkage definitions and runtime references: missing definition red, restore green',async()=>{
 const dir=root+'/linkage';await fs.mkdir(dir);
 const symbols=['_CNat6String7indexOfHRNatY0_E','_CNat6String7toArrayHv','_CNak12ParserHelper12doLongParserHRNat5ArrayIRNat6StringEEY3_l','_CNacXCNac7HashMapIG_G0_E8toStringHv'];
 await write(dir+'/runtime.c','int EXTRA(void){return 1;} int CJ_MCC_ReadRefField(void){return 2;}');
 await write(dir+'/host.c','int CJ_MCC_ReadRefField(void){return 2;}');
 for(const name of ['runtime','host'])run('cc',['-shared','-fPIC',dir+'/'+name+'.c','-o',dir+'/'+name+'.so']);
 async function archive(name,names){
  const body='.text\n'+names.map(s=>'.globl '+s+'\n'+s+':\n call EXTRA\n call CJ_MCC_ReadRefField\n ret\n').join('');
  await write(dir+'/'+name+'.s',body);run('cc',['-c',dir+'/'+name+'.s','-o',dir+'/'+name+'.o']);run('ar',['rcs',dir+'/'+name+'.a',dir+'/'+name+'.o']);return dir+'/'+name+'.a';
 }
 const args={coreLib:await archive('core',symbols.slice(0,2)),argoptLib:await archive('argopt',[symbols[2]]),collectionLib:await archive('collection',[symbols[3]]),runtime:dir+'/runtime.so',hostRuntime:dir+'/host.so',target:{spec:{os:'linux',arch:'x86_64',key:'linux_x86_64'}}};
 assert.equal((await assertStdBarriers(args)).rc,0);
 const bad=await archive('missing',[symbols[0]]);
 await assert.rejects(assertStdBarriers({...args,coreLib:bad}),/STD_BARRIER_DEFINITION_MISSING _CNat6String7toArrayHv/);
 assert.equal((await assertStdBarriers(args)).rc,0);
 await assert.rejects(assertStdBarriers({...args,hostRuntime:args.runtime}),/empty colour-only/);
});
test('stream errors, bounded output, nonzero and cancellation retain child responsibility',async()=>{
 assert.equal((await streamStdProcess([process.execPath,'-e','process.exit(7)'])).code,7);
 await assert.rejects(streamStdProcess(['/missing/sdk-fixture-executable']),/ENOENT/);
 await assert.rejects(streamStdProcess([process.execPath,'-e','process.stdout.write("x".repeat(200000))'],{limit:1024}),/OUTPUT_LIMIT/);
 for(const mode of ['exit-zero','ignore']){
  const ready=root+'/stream-'+mode;
  const controller=new AbortController();
  const body='const fs=require("fs");process.on("SIGTERM",()=>{'+(mode==='exit-zero'?'process.exit(0);':'')+'});fs.writeFileSync('+JSON.stringify(ready)+',String(process.pid));setInterval(()=>{},100);';
  const pending=assert.rejects(streamStdProcess([process.execPath,'-e',body],{signal:controller.signal}),/CANCELLED/);
  const deadline=Date.now()+5000;
  while(!await fs.stat(ready).catch(()=>null)){if(Date.now()>deadline){controller.abort();await pending;assert.fail('stream fixture not ready');}await new Promise(r=>setTimeout(r,20));}
  const pid=Number(await fs.readFile(ready,'utf8'));controller.abort();await pending;
  assert.equal(getEventListeners(controller.signal,'abort').length,0);assert.throws(()=>process.kill(pid,0),/ESRCH/);
 }
});
