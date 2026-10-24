#!/usr/bin/env zx
// Public-entry ownership controls. Observe first, then clean only exact test identities.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root]=process.argv.slice(2);
assert(source&&runtime&&root,'usage: T-source R-source owned-output');fs.mkdirSync(root,{recursive:true});
const cli=path.join(source,'ci/bootstrap/sdk-build.mjs'),read=f=>fs.readFileSync(f,'utf8');
const write=(f,v)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');};
const argvOf=pid=>{try{return read('/proc/'+pid+'/cmdline').split('\0').filter(Boolean);}catch{return [];}};
function identity(pid){try{const text=read('/proc/'+pid+'/stat'),f=text.slice(text.lastIndexOf(')')+2).split(' ');return {pid,start:f[19],state:f[0],ppid:+f[1],pgrp:+f[2],cwd:fs.readlinkSync('/proc/'+pid+'/cwd'),exe:fs.readlinkSync('/proc/'+pid+'/exe'),argv:argvOf(pid).map(x=>x.length>500?'<sha256:'+crypto.createHash('sha256').update(x).digest('hex')+'>':x)};}catch(e){if(['ENOENT','ESRCH','EACCES'].includes(e.code))return null;throw e;}}
const alive=id=>{const now=id&&identity(id.pid);return now&&now.start===id.start&&now.state!=='Z';};
function remember(pid,known){const rows=fs.readdirSync('/proc').filter(x=>/^\d+$/.test(x)).map(x=>identity(+x)).filter(Boolean);const family=new Set([pid,...[...known.values()].filter(alive).map(x=>x.pid)]);let changed=true;while(changed){changed=false;for(const row of rows)if(family.has(row.ppid)&&!family.has(row.pid)){family.add(row.pid);changed=true;}}for(const row of rows)if(family.has(row.pid))known.set(row.pid,row);}
async function until(fn,label,limit=12000){const end=Date.now()+limit;while(Date.now()<end){const value=fn();if(value)return value;await delay(10);}throw new Error('FIXTURE_TIMEOUT '+label);}
function config(dir,commands,extra={}){const file=dir+'/config.json';write(file,{work:dir+'/work',install:dir+'/install',repos:{},finalStage:'one',test:{},stages:[{id:'one',output:dir+'/install',commands:commands.map(argv=>({argv}))}],...extra});return file;}
function events(file){return fs.existsSync(file)?read(file).trim().split('\n').filter(Boolean).map(JSON.parse):[];}
const arms=process.env.SDK_SUPERVISOR_ARMS?.split(',')||['normal-install','python-worker-lost','python-front-lost','adapter-worker-lost','adapter-front-lost','middle-guardian-lost','root-guardian-lost','ready-int','ready-owner-lost','status-close','output-close','output-backpressure','exit-int','three-int','three-term','sdk-owner-lost','child-int','configure-int','configure-term','reconfigure-int','reconfigure-term'];
const rows=[];
for(const arm of arms){
 const dir=path.join(root,arm);fs.mkdirSync(dir);const known=new Map(),pool=dir+'/parent.fifo';assert.equal(spawnSync('mkfifo',['-m','600',pool]).status,0);
 const fd=fs.openSync(pool,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,Buffer.from('AB'));
 const beforeFlags=read('/proc/self/fdinfo/'+fd).match(/^flags:\s*(\S+)/m)[1];
 const log=dir+'/events.jsonl',marker=dir+'/ready.json',signalFile=dir+'/signals.jsonl',leaf=dir+'/leaf.mjs';
 write(leaf,`import fs from 'node:fs';import {spawn} from 'node:child_process';
const marker=${JSON.stringify(marker)},signals=${JSON.stringify(signalFile)},arm=${JSON.stringify(arm)};
const child=spawn(process.execPath,['-e',"process.on('SIGINT',()=>{});process.on('SIGTERM',()=>{});process.stdout.write('ready');setInterval(()=>{},1000)"],{stdio:['ignore','pipe','ignore']});
let closing=false;for(const s of ['SIGINT','SIGTERM'])process.on(s,()=>{fs.appendFileSync(signals,JSON.stringify({signal:s,pid:process.pid})+'\\n');if(!closing){closing=true;setTimeout(()=>process.exit(0),arm.startsWith('three')?1300:80);}});
child.stdout.once('data',()=>{fs.writeFileSync(marker,JSON.stringify({pid:process.pid,child:child.pid}));if(arm==='exit-int')setTimeout(()=>process.exit(0),100);if(arm.startsWith('output-')){const block='x'.repeat(4096);function flood(){if(process.stdout.write(block))setImmediate(flood);else process.stdout.once('drain',flood);}flood();}});setInterval(()=>{},1000);
`);
 let payload=[process.execPath,leaf],native;
 const nativeArm=arm==='normal-install'||arm.startsWith('python-')||arm.startsWith('adapter-')||arm==='middle-guardian-lost'||arm.startsWith('configure-')||arm.startsWith('reconfigure-');
 if(nativeArm){
  native=dir+'/native';fs.mkdirSync(native);fs.mkdirSync(native+'/scripts');
  for(const rel of ['build.py','scripts/ninja-jobserver.mjs','scripts/command-supervisor.mjs','scripts/command-supervisor.source.json'])fs.copyFileSync(runtime+'/stdlib/'+rel,native+'/'+rel);
  write(native+'/cmake/linux_x86_64_toolchain.cmake','# native fixture host compiler\n');write(native+'/value.c','#include <stdio.h>\nint main(void){puts("42");return 0;}\n');
  write(native+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.16)\nproject(SupervisorFixture C)\nset(CMAKE_C_COMPILER_LAUNCHER node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command --)\nadd_executable(value value.c)\nadd_custom_target(hold COMMAND node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command -- node "${leaf}" VERBATIM)\ninstall(TARGETS value RUNTIME DESTINATION bin)\n`);
  if(arm.startsWith('configure-')||arm.startsWith('reconfigure-'))fs.appendFileSync(native+'/CMakeLists.txt',`\nif(CANGJIE_CPU_JOBS GREATER 1)\n execute_process(COMMAND node "${leaf}" COMMAND_ERROR_IS_FATAL ANY)\nendif()\n`);
  payload=['python3','-I',native+'/build.py','build','-t','release','--jobs','4','--build-target',arm==='normal-install'?'value':'hold'];
 }
 let cfg;
 if(arm==='normal-install'){
  const verify=dir+'/verify.mjs';write(verify,`import fs from 'node:fs';import assert from 'node:assert/strict';import {spawnSync}from'node:child_process';const r=spawnSync(process.argv[2],[],{encoding:'utf8'});const row={argv:[process.argv[2]],rc:r.status,stdout:r.stdout};fs.appendFileSync(${JSON.stringify(dir+'/consumers.jsonl')},JSON.stringify(row)+'\\n');assert.equal(r.status,0);assert.equal(r.stdout.trim(),'42');console.log('INSTALLED_VALUE_TARGET_ASSERTION_REACHED '+JSON.stringify(row));`);
  cfg=config(dir+'/sdk',[payload,['python3','-I',native+'/build.py','install','--prefix',dir+'/sdk/install']],{test:{required:['bin/value'],commands:[{argv:[process.execPath,verify,'${install}/bin/value']}]},archive:dir+'/sdk.tar.gz'});
 }else if(arm.startsWith('reconfigure-')){
  const initial=[...payload];initial[initial.indexOf('--jobs')+1]='1';initial[initial.indexOf('--build-target')+1]='value';cfg=config(dir+'/sdk',[initial,payload]);
 }else{
  const depth=arm.startsWith('three')||arm==='root-guardian-lost'?3:arm==='sdk-owner-lost'?2:1;
  for(let i=0;i<depth;i++){cfg=config(dir+'/level'+i,[payload]);payload=[process.execPath,cli,'--config',cfg,'--no-package'];}
 }
 const hooks=new Set(['ready-int','ready-owner-lost','status-close','child-int']);let prefix=[];
 if(hooks.has(arm)){
  const hook=dir+'/hook.mjs';write(hook,`import cp from 'node:child_process';import fs from 'node:fs';import {syncBuiltinESMExports}from'node:module';const original=cp.spawn;cp.spawn=function(...args){const child=original(...args);if(args[0]==='python3'&&args[1]?.[1]==='-c'){
if(${JSON.stringify(arm)}==='child-int'){let sent=false,buffer='';child.stdio[4].on('data',chunk=>{buffer+=chunk;for(const line of buffer.split('\\n').slice(0,-1)){const row=JSON.parse(line);if(row.type==='child'&&!sent){sent=true;fs.writeFileSync(${JSON.stringify(dir+'/boundary.json')},JSON.stringify({owner:process.pid,guardian:child.pid,child:row.child}));process.kill(process.pid,'SIGINT');}}});}
const write=child.stdio[3].write.bind(child.stdio[3]);child.stdio[3].write=(data,...rest)=>{if(String(data).includes('"go":true')){fs.writeFileSync(${JSON.stringify(dir+'/boundary.json')},JSON.stringify({owner:process.pid,guardian:child.pid}));if(${JSON.stringify(arm)}==='ready-owner-lost'){process.kill(process.pid,'SIGKILL');return true;}if(${JSON.stringify(arm)}==='ready-int'){process.kill(process.pid,'SIGINT');return true;}if(${JSON.stringify(arm)}==='status-close'){child.stdio[4].destroy();return true;}}return write(data,...rest);};}return child;};syncBuiltinESMExports();`);prefix=['--import',hook];
 }
 const argv=[process.execPath,...prefix,cli,'--config',cfg,...(arm==='normal-install'?[]:['--no-package'])];
 const outputPipe=arm.startsWith('output-'),out=outputPipe?null:fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 const env={...process.env,MAKEFLAGS:'-j3 --jobserver-auth=3,4',CANGJIE_JOBSERVER_LOG:log};delete env.CARGO_MAKEFLAGS;delete env.MFLAGS;delete env.CJCJ_COMMAND_LIFETIME_FD;
 const control=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{cwd:dir,stdio:'ignore'}),independent=await until(()=>identity(control.pid),'unrelated');
 const p=spawn(argv[0],argv.slice(1),{cwd:dir,env,stdio:['ignore',outputPipe?'pipe':out,err,fd,fd]});
 let result,timeout=false,killed;const finished=new Promise(resolve=>p.once('exit',(rc,signal)=>resolve({rc,signal}))),start=Date.now();
 const sampling=setInterval(()=>remember(p.pid,known),20),timer=setTimeout(()=>{timeout=true;const id=identity(p.pid);if(id&&alive(id))process.kill(id.pid,'SIGKILL');},18000);
 try{
  if(arm!=='normal-install'&&!hooks.has(arm)){
   const ready=await until(()=>fs.existsSync(marker)&&JSON.parse(read(marker)),'payload-ready');remember(p.pid,known);
   if(arm.startsWith('configure-')||arm.startsWith('reconfigure-')){const parent=identity(identity(ready.pid).ppid);assert(parent&&path.basename(parent.exe)==='cmake','actual CMake configure child reached');write(dir+'/configure-boundary.json',{parent,ready,reconfigure:arm.startsWith('reconfigure-')});if(arm.startsWith('reconfigure-'))assert(events(log).some(e=>e.event==='pool-end'&&e.jobs===1&&e.rc===0),'same directory first build completed before reconfiguration');}
   const es=events(log),rootG=es.find(x=>x.event==='supervisor-ready');assert(rootG,'real root guardian ready');
   const choose=predicate=>[...known.values()].find(id=>predicate(argvOf(id.pid),id));
   if(arm==='sdk-owner-lost')killed=choose((args,id)=>id.pid!==p.pid&&args.includes(cli));
   else if(arm==='root-guardian-lost')killed=known.get(rootG.pid);
   else if(arm==='middle-guardian-lost')killed=known.get(es.find(x=>x.event==='supervisor-ready'&&x.mode==='ninja').pid);
   else if(arm==='python-worker-lost')killed=choose(args=>args.includes(native+'/build.py')&&args.includes('--supervised-build'));
   else if(arm==='python-front-lost')killed=choose(args=>args.includes(native+'/build.py')&&!args.includes('--supervised-build'));
   else if(arm==='adapter-worker-lost')killed=choose(args=>args.includes(native+'/scripts/ninja-jobserver.mjs')&&args.includes('worker'));
   else if(arm==='adapter-front-lost')killed=choose(args=>args.includes(native+'/scripts/ninja-jobserver.mjs')&&args.includes('run'));
   if(arm.endsWith('-lost')){assert(killed&&alive(killed),'exact lost role identified');write(dir+'/killed.json',killed);process.kill(killed.pid,'SIGKILL');}
   else if(arm==='exit-int'){await until(()=>!alive(known.get(ready.pid)),'actual-payload-exit');p.kill('SIGINT');}
   else if(arm==='output-close')p.stdout.destroy();
   else p.kill(arm.endsWith('int')?'SIGINT':'SIGTERM');
  }
  result=await finished;
  if(['ready-owner-lost','status-close','output-close'].includes(arm)){
   await until(()=>events(log).some(x=>x.event==='supervisor-finished'),'guardian-finish-after-observer-loss');
   if(fs.existsSync(dir+'/boundary.json')){const b=JSON.parse(read(dir+'/boundary.json')),id=identity(b.guardian);if(id)known.set(id.pid,id);}
  }
  clearTimeout(timer);clearInterval(sampling);remember(p.pid,known);
  if(outputPipe)p.stdout.destroy();else fs.closeSync(out);fs.closeSync(err);
  const bytes=Buffer.alloc(32);let n=0;try{n=fs.readSync(fd,bytes,0,bytes.length,null);}catch(e){if(e.code!=='EAGAIN')throw e;}
  const afterFlags=read('/proc/self/fdinfo/'+fd).match(/^flags:\s*(\S+)/m)[1],es=events(log),live=[...known.values()].filter(alive),publicState=path.dirname(cfg)+'/work/build-result.json';
  const observed={arm,argv,...result,timeout,wallMs:Date.now()-start,tokens:bytes.subarray(0,n).toString(),killed,identities:[...known.values()],liveBeforeCleanup:live,unrelatedAlive:!!alive(independent),beforeFlags,afterFlags,events:es,publicState:fs.existsSync(publicState)?JSON.parse(read(publicState)):null,signals:events(signalFile)};
  write(dir+'/observed-before-cleanup.json',observed);rows.push(observed);write(root+'/results.json',rows);
  console.log(JSON.stringify({event:'SUPERVISOR_TARGET_ASSERTION_REACHED',arm,rc:result.rc,signal:result.signal,live:live.length,tokens:observed.tokens,timeout}));
  assert(!timeout,'bounded termination');assert(observed.unrelatedAlive,'unrelated process survives');assert.equal(afterFlags,beforeFlags,'original parent OFD flags unchanged');
  if(arm==='root-guardian-lost'){
   assert.notEqual(result.rc,0,'last guardian loss is not success');assert.equal(observed.publicState?.status,'FAILED');assert(es.every(x=>x.event!=='parent-return'||x.pid!==killed.pid),'dead true ledger owner cannot return bytes');assert.notEqual(observed.tokens,'AB','no fabricated original bytes after true owner loss');assert(live.length>0,'unrecoverable residual observed before cleanup');assert.match(read(dir+'/stdout'),/SUPERVISOR_LOST|SUPERVISOR_STATUS_CLOSED/,'explicit incomplete result');
  }else{
   assert.equal(live.length,0,'all owned descendants gone before test cleanup');assert.equal([...observed.tokens].sort().join(''),'AB','actual original upstream bytes');assert(es.some(x=>x.event==='scope-budget'&&x.borrowed===2),'real nonzero upstream borrow');assert(es.some(x=>x.event==='parent-return'&&x.count===2&&x.originalHex==='4142'),'actual original-byte return');
   if(arm==='normal-install'){assert.equal(result.rc,0);const consumers=events(dir+'/consumers.jsonl');assert.equal(consumers.length,2,'install and unpack consumers');assert(consumers.every(x=>x.rc===0&&x.stdout.trim()==='42'));assert(consumers.some(x=>x.argv[0].includes('.unpacked/')));}
   else if(arm==='ready-owner-lost')assert.equal(result.signal,'SIGKILL');
   else if(arm==='output-close')assert(result.rc!==0||result.signal,'closed output must not pretend success');
   else if(arm==='status-close'||arm.endsWith('-lost'))assert.notEqual(result.rc,0);
   else assert.equal(result.rc,arm.endsWith('int')?130:143,'first public cancellation identity');
   if(arm.startsWith('ready-'))assert(!es.some(x=>x.event==='supervisor-child'),'no work before GO');
   if(arm==='child-int')assert(fs.existsSync(dir+'/boundary.json'),'actual fork/child boundary reached');
   if(arm==='exit-int'||arm.startsWith('three'))assert(es.some(x=>x.event==='supervisor-payload-exit'&&x.childRc===0),'actual zero child rc persisted before orphan drain');
  }
  console.log(JSON.stringify({arm,pass:true,rc:result.rc,tokens:observed.tokens,live:live.length}));
 }finally{
  clearTimeout(timer);clearInterval(sampling);remember(p.pid,known);for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');if(alive(independent))process.kill(independent.pid,'SIGKILL');fs.closeSync(fd);await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});
 }
}
