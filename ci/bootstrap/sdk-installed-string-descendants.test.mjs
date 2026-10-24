import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {getEventListeners} from 'node:events';
import {fileDigest} from './sdk-flow.mjs';
import {streamStdProcess,streamBarrierObjdump} from '../srcbuild/lib/assert-std-barriers.mjs';
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function fixture(mode){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'string-desc-'));
 async function put(rel,text){const f=path.join(root,rel);await fs.mkdir(path.dirname(f),{recursive:true});await fs.writeFile(f,text);return f;}
 const leaf=await put('leaf.cjs','const fs=require("fs");process.on("SIGTERM",()=>{});fs.writeFileSync('+JSON.stringify(root+'/leaf.pid')+',String(process.pid));setInterval(()=>{},50);');
 const worker=await put('worker.cjs','const fs=require("fs");const {spawn}=require("child_process");process.on("SIGTERM",()=>{});fs.writeFileSync('+JSON.stringify(root+'/worker.pid')+',String(process.pid));spawn(process.execPath,['+JSON.stringify(leaf)+'],{stdio:["ignore","inherit","inherit"]});setInterval(()=>{},50);');
 const driver=await put('sdk/bin/cjc','#!'+process.execPath+'\nconst fs=require("fs");const {spawn}=require("child_process");fs.writeFileSync('+JSON.stringify(root+'/driver.pid')+',String(process.pid));process.on("SIGTERM",()=>process.exit(0));spawn(process.execPath,['+JSON.stringify(worker)+'],{stdio:'+JSON.stringify(mode==='closed-pipes'?['ignore','ignore','ignore']:['ignore','inherit','inherit'])+'});const t=setInterval(()=>{if(fs.existsSync('+JSON.stringify(root+'/leaf.pid')+')){clearInterval(t);console.log("DESCENDANTS_READY");'+(['parent-exit','closed-pipes'].includes(mode)?'process.exit(0);':'setInterval(()=>{},50);')+'}},10);\n');
 await fs.chmod(driver,0o755);
 const compiler=await put('sdk/libexec/compiler/cjcj-stage1','compiler fixture');
 await put('sdk/bin/cjc.entry','cjcj-sdk-entry-v1\n1\nlibexec/compiler/cjcj-stage1\nlinux\nnative-target:x64\nruntime/lib/linux_x86_64_cjnative\n');
 await put('sdk/compiler-inputs.json',JSON.stringify({compilerSha256:await fileDigest(compiler)}));
 const tuple='linux_x86_64_cjnative';
 await put('std/lib/'+tuple+'/libcangjie-std-core.a','archive fixture');await put('std/modules/'+tuple+'/std/std.core.cjo','module fixture');
 const r=await put('runtime/runtime/lib/'+tuple+'/libcangjie-runtime.so','runtime fixture');
 const b=await put('runtime/runtime/lib/'+tuple+'/libboundscheck.so','bounds fixture');
 async function pids(){return Promise.all(['driver','worker','leaf'].map(async n=>Number(await fs.readFile(root+'/'+n+'.pid','utf8').catch(()=>''))));}
 async function cleanup(){
  for(const pid of (await pids()).reverse())if(pid){
   const cmd=await fs.readFile('/proc/'+pid+'/cmdline','utf8').catch(()=>'');
   if(cmd.includes(root+'/')){try{process.kill(pid,'SIGKILL');}catch{}}
  }
 }
 async function gone(){
  const ids=await pids();assert.ok(ids.every(Boolean),'TARGET_DESCENDANTS_NOT_REACHED');
  // Require PID disappearance, not merely pipes closing or a bounded report.
  for(let i=0;i<60;i++){if((await Promise.all(ids.map(pid=>fs.stat('/proc/'+pid).then(()=>false,()=>true)))).every(Boolean))return;await pause(25);}
  assert.fail('TARGET_DESCENDANTS_STILL_PRESENT '+ids.join(','));
 }
 return {root,driver,pids,cleanup,gone};
}
async function bounded(promise,ms=3500){
 let timer;try{return await Promise.race([promise,new Promise((_,reject)=>timer=setTimeout(()=>reject(Error('TARGET_REPORT_NOT_BOUNDED')),ms))]);}finally{clearTimeout(timer);}
}
test('normal independent child process tree completes with original rc',async()=>{
 const outside=spawn(process.execPath,['-e','setInterval(()=>{},100)'],{detached:true,stdio:'ignore'});
 try{
  const r=await streamStdProcess([process.execPath,'-e','const {spawn}=require("child_process");const c=spawn(process.execPath,["-e","console.log(42)"],{stdio:["ignore","inherit","inherit"]});c.on("exit",()=>process.exit(7));']);
  assert.equal(r.code,7);assert.match(r.stdout,/42/);assert.doesNotThrow(()=>process.kill(outside.pid,0));
 }finally{outside.kill('SIGKILL');await new Promise(r=>outside.once('close',r));}
});
for(const mode of ['cancel','parent-exit','closed-pipes'])test('public CLI owns complete descendants '+mode,{timeout:10000},async()=>{
 const f=await fixture(mode),work=f.root+'/work';
 const outside=spawn(process.execPath,['-e','setInterval(()=>{},100)'],{detached:true,stdio:'ignore'});
 const cli=fileURLToPath(new URL('./sdk-installed-string.mjs',import.meta.url));
 const c=spawn(process.execPath,[cli,'--sdk',f.root+'/sdk','--std',f.root+'/std','--runtime',f.root+'/runtime','--platform','linux_x86_64','--work',work],{stdio:['ignore','pipe','pipe']});
 let out='',err='';c.stdout.on('data',x=>out+=x);c.stderr.on('data',x=>err+=x);const closed=new Promise(r=>c.once('close',(rc,signal)=>r({rc,signal})));
 try{
  for(let i=0;i<100;i++){if((await f.pids()).every(Boolean))break;await pause(20);}
  assert.ok((await f.pids()).every(Boolean),'TARGET_DESCENDANTS_NOT_REACHED');
  console.log('TARGET_DESCENDANTS_REACHED '+mode+' '+JSON.stringify(await f.pids()));
  if(mode==='cancel')c.kill('SIGTERM');
  const result=await bounded(closed);assert.notEqual(result.rc,0);
  await f.gone();assert.doesNotThrow(()=>process.kill(outside.pid,0));
  const dirs=await fs.readdir(work),record=JSON.parse(await fs.readFile(path.join(work,dirs.find(x=>x.startsWith('string-')),'string-result.json')));
  assert.equal(record.commands[0].rc,0);assert.equal(record.commands[0].cleanupComplete,true);
  assert.match(record.error,mode==='cancel'?/CANCELLED/:/DESCENDANTS_AFTER/);
  assert.ok(record.commands[0].ended);assert.doesNotMatch(out,/INSTALLED_STRING_PASS/);
  console.log('TARGET_CLEANED_REPORT_FINISHED '+mode);
 }finally{await f.cleanup();c.kill('SIGKILL');await closed;outside.kill('SIGKILL');await new Promise(r=>outside.once('close',r));}
});
test('timeout cleans TERM-ignoring descendant tree and removes listener',{timeout:10000},async()=>{
 const f=await fixture('timeout'),controller=new AbortController();let ready=false;
 const result=streamStdProcess([f.driver],{signal:controller.signal,timeout:250,onLine:line=>{if(line==='DESCENDANTS_READY')ready=true;}});
 try{
  await assert.rejects(bounded(result),error=>{assert.equal(ready,true,'TARGET_DESCENDANTS_NOT_REACHED');assert.match(error.message,/TIMEOUT/);assert.equal(error.childRc,0);assert.equal(error.cleanupComplete,true);return true;});
  await f.gone();assert.equal(getEventListeners(controller.signal,'abort').length,0);console.log('TARGET_TIMEOUT_CLEANED');
 }finally{await f.cleanup();await result.catch(()=>{});}
});

// Preserve the shared scanner lifecycle controls without importing the retired
// instruction-model fixture used by the old SDK integration suite.
for(const mode of ['exit-zero','ignore','long-line','stderr','nonzero','signal'])test('shared scanner lifecycle '+mode,{timeout:8000},async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'string-scanner-')),ready=dir+'/ready';
 const header='0000 <_CNat6String7indexOfHRNatY0_E>:\n';
 const body=mode==='long-line'?'process.on("SIGTERM",()=>{});setInterval(()=>process.stdout.write("x".repeat(8192)),1);':
  mode==='stderr'?'process.stderr.write("e".repeat(2000000));process.stdout.write('+JSON.stringify(header)+');':
  mode==='nonzero'?'process.stdout.write('+JSON.stringify(header)+');process.exitCode=7;':
  mode==='signal'?'process.kill(process.pid,"SIGKILL");':
  'process.on("SIGTERM",()=>{'+(mode==='exit-zero'?'process.exit(0);':'')+'});require("fs").writeFileSync('+JSON.stringify(ready)+',String(process.pid));setInterval(()=>{},10);';
 await fs.writeFile(dir+'/objdump','#!'+process.execPath+'\n'+body);await fs.chmod(dir+'/objdump',0o755);
 const old=process.env.PATH,controller=new AbortController();process.env.PATH=dir+':'+old;
 try{
  const result=streamBarrierObjdump([],{signal:controller.signal});
  if(['exit-zero','ignore'].includes(mode)){
   for(let i=0;i<100&&!await fs.stat(ready).catch(()=>null);i++)await pause(10);
   assert.ok(await fs.stat(ready));controller.abort();await assert.rejects(result,/STD_BARRIER_CANCELLED/);
   const pid=Number(await fs.readFile(ready,'utf8'));assert.throws(()=>process.kill(pid,0),/ESRCH/);
  }else if(mode==='long-line')await assert.rejects(result,/STD_BARRIER_LINE_LIMIT/);
  else{const r=await result;assert.equal(r.cleanupComplete,true);if(mode==='stderr'){assert.ok(r.stderr.length<=65536);assert.ok(r.states[0].found);}if(mode==='nonzero')assert.equal(r.code,7);if(mode==='signal'){assert.equal(r.code,null);assert.equal(r.signal,'SIGKILL');}}
  assert.equal(getEventListeners(controller.signal,'abort').length,0);
 }finally{process.env.PATH=old;controller.abort();}
});
