import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {getEventListeners} from 'node:events';
import {fileURLToPath} from 'node:url';
import {streamStdProcess} from '../srcbuild/lib/assert-std-barriers.mjs';
import {stringEnvironment} from './sdk-installed-string.mjs';
import {fileDigest} from './sdk-flow.mjs';
const js=body=>[process.execPath,'-e',body];
test('consumer environment replaces injection and old search paths',()=>{
 const keys=['LD_PRELOAD','LD_AUDIT','LD_LIBRARY_PATH','CANGJIE_PATH','LIBRARY_PATH','NODE_OPTIONS','CJC_JOBS_TOKENS'];
 const before=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
 try {for(const k of keys)process.env[k]='/poison';
  const env=stringEnvironment({sdk:'/sdk',std:'/std',runtime:'/runtime',platform:'linux_x86_64',work:'/work'});
  assert.equal(env.CANGJIE_PATH,'/std/modules/linux_x86_64_cjnative');
  assert.equal(env.LIBRARY_PATH,'/std/lib/linux_x86_64_cjnative:/runtime/runtime/lib/linux_x86_64_cjnative:/runtime/lib/linux_x86_64_cjnative');
  assert.ok(!JSON.stringify(env).includes('/poison'));assert.equal(env.LD_PRELOAD,undefined);
 }finally{for(const k of keys)if(before[k]===undefined)delete process.env[k];else process.env[k]=before[k];}
});
for(const [name,body,pattern] of [
 ['no-newline','process.stdout.write("x".repeat(70000))',/LINE_LIMIT/],
 ['stderr','process.stderr.write("e".repeat(10000))',/OUTPUT_LIMIT/]
])test('bounded output '+name,async()=>{
 await assert.rejects(streamStdProcess(js(body),{limit:name==='stderr'?4096:100000}),pattern);
});
test('retains actual nonzero and signal after output',async()=>{
 const r=await streamStdProcess(js('process.stdout.write("claimed PASS");process.exitCode=7'));
 assert.equal(r.code,7);assert.equal(r.stdout,'claimed PASS');
 const killed=await streamStdProcess(js('process.kill(process.pid,"SIGKILL")'));
 assert.equal(killed.code,null);assert.equal(killed.signal,'SIGKILL');
});
test('start error rejects without a successful close',async()=>{
 await assert.rejects(streamStdProcess(['/missing-installed-string-tool']),/ENOENT/);
});
for(const mode of ['zero','ignore'])test('sticky cancellation '+mode,async()=>{
 const controller=new AbortController();let ready;
 const observed=new Promise(r=>ready=r);
 const result=streamStdProcess(js('process.on("SIGTERM",()=>{'+(mode==='zero'?'process.exit(0);':'')+'});console.log("READY");setInterval(()=>{},10)'),
  {signal:controller.signal,onLine:l=>{if(l==='READY')ready();}});
 await observed;controller.abort();await assert.rejects(result,/CANCELLED/);
 assert.equal(getEventListeners(controller.signal,'abort').length,0);
});

for(const mode of ['cancel-zero','signal'])test('public entry records child and wrapper status '+mode,{timeout:10000},async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'string-cli-'));
 const sdk=path.join(root,'sdk'),std=path.join(root,'std'),runtime=path.join(root,'runtime'),work=path.join(root,'work');
 const tuple='linux_x86_64_cjnative',pidFile=path.join(root,'child.pid');
 async function put(rel,text){const f=path.join(root,rel);await fs.mkdir(path.dirname(f),{recursive:true});await fs.writeFile(f,text);return f;}
 const cjc=await put('sdk/bin/cjc','#!'+process.execPath+'\nconst fs=require("fs");process.on("SIGTERM",()=>process.exit(0));fs.writeFileSync('+JSON.stringify(pidFile)+',String(process.pid));setInterval(()=>{},20);\n');
 await fs.chmod(cjc,0o755);
 const compiler=await put('sdk/libexec/compiler/cjcj-stage1','compiler fixture');
 await put('sdk/bin/cjc.entry','cjcj-sdk-entry-v1\nlinux\nlibexec/compiler/cjcj-stage1\n\n\nruntime/lib/'+tuple+'\n');
 await put('sdk/compiler-inputs.json',JSON.stringify({compilerSha256:await fileDigest(compiler)}));
 await put('std/lib/'+tuple+'/libcangjie-std-core.a','archive fixture');
 await put('std/modules/'+tuple+'/std/std.core.cjo','module fixture');
 const r=await put('runtime/runtime/lib/'+tuple+'/libcangjie-runtime.so','runtime fixture');
 const b=await put('runtime/runtime/lib/'+tuple+'/libboundscheck.so','bounds fixture');
 const cli=fileURLToPath(new URL('./sdk-installed-string.mjs',import.meta.url));
 const child=spawn(process.execPath,[cli,'--sdk',sdk,'--std',std,'--runtime',runtime,'--work',work,'--platform','linux_x86_64'],{stdio:['ignore','pipe','pipe']});
 let stdout='',stderr='';child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);
 const closed=new Promise(resolve=>child.once('close',(rc,signal)=>resolve({rc,signal})));
 let pid;
 try {
  const deadline=Date.now()+5000;
  while(!pid){pid=Number(await fs.readFile(pidFile,'utf8').catch(()=>''));if(pid)break;
   if(Date.now()>deadline)throw new Error('compiler not reached '+stdout+stderr);await new Promise(r=>setTimeout(r,20));}
  if(mode==='signal')process.kill(pid,'SIGKILL');else child.kill('SIGTERM');
  const result=await closed;assert.notEqual(result.rc,0);assert.match(stderr,mode==='signal'?/rc=null signal=SIGKILL/:/CANCELLED/);
  assert.throws(()=>process.kill(pid,0),/ESRCH/);
  const dirs=await fs.readdir(work);const report=JSON.parse(await fs.readFile(path.join(work,dirs.find(d=>d.startsWith('string-')),'string-result.json')));
  assert.equal(report.status,'FAILED');
  const command=report.commands[0];assert.equal(command.wrapperRc,1);
  if(mode==='signal'){assert.equal(command.rc,null);assert.equal(command.signal,'SIGKILL');}
  else {assert.equal(command.rc,0);assert.equal(command.childRc,0);}
  assert.doesNotMatch(stdout,/INSTALLED_STRING_PASS/);
 } finally {child.kill('SIGTERM');if(pid){try{process.kill(pid,'SIGKILL');}catch{}}await closed;}
});
