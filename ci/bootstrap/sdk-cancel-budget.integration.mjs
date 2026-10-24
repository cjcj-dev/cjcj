#!/usr/bin/env zx
// Public SDK/Python/Ninja lifecycle fixtures; no Cangjie stage or std build.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root]=process.argv.slice(2);
assert(source&&runtime&&root,'usage: test T-source R-source owned-output');
fs.mkdirSync(root,{recursive:true});
const cli=path.join(source,'ci/bootstrap/sdk-build.mjs');
const read=file=>fs.readFileSync(file,'utf8');
function identity(pid){try{const s=read(`/proc/${pid}/stat`),f=s.slice(s.lastIndexOf(')')+2).split(' ');return{pid,start:f[19],state:f[0],ppid:+f[1],pgrp:+f[2],cwd:fs.readlinkSync(`/proc/${pid}/cwd`),exe:fs.readlinkSync(`/proc/${pid}/exe`)};}catch(e){if(['ENOENT','ESRCH','EACCES'].includes(e.code))return null;throw e;}}
const alive=id=>{const r=identity(id.pid);return r&&r.start===id.start&&r.state!=='Z';};
function remember(pid,known){let family=new Set([pid]),changed=true;const rows=fs.readdirSync('/proc').filter(x=>/^\d+$/.test(x)).map(x=>identity(+x)).filter(Boolean);while(changed){changed=false;for(const r of rows)if(family.has(r.ppid)&&!family.has(r.pid)){family.add(r.pid);changed=true;}}for(const r of rows)if(family.has(r.pid))known.set(r.pid,r);}
function write(file,data){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,data);}
function config(dir,argv){fs.mkdirSync(dir,{recursive:true});const c={work:dir+'/work',install:dir+'/install',repos:{},test:{},finalStage:'one',stages:[{id:'one',output:dir+'/install',commands:[{argv}]}]};write(dir+'/config.json',JSON.stringify(c));return dir+'/config.json';}
async function until(fn,p,limit=10000){const end=Date.now()+limit;while(Date.now()<end){const v=fn();if(v)return v;if(p.exitCode!==null)throw Error('PUBLIC_ENTRY_EARLY_EXIT '+p.exitCode);await delay(10);}throw Error('FIXTURE_READY_TIMEOUT');}
const rows=[];
const arms=process.env.SDK_CANCEL_ARMS?.split(',') || ['three-int','three-term','exit-int','spawn-int','python-term','python-int','adapter-term','normal-native'];
for(const arm of arms){
 const dir=root+'/'+arm;fs.mkdirSync(dir);const known=new Map();
 const fifo=dir+'/parent.fifo';assert.equal(spawnSync('mkfifo',['-m','600',fifo]).status,0);
 const fd=fs.openSync(fifo,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,Buffer.from('AB'));
 const log=dir+'/pool.jsonl',marker=dir+'/ready.json',signals=dir+'/signals.jsonl';
 const leaf=dir+'/leaf.mjs';
 write(leaf,`import fs from 'node:fs';import {spawn} from 'node:child_process';\nconst marker=${JSON.stringify(marker)},signals=${JSON.stringify(signals)},arm=${JSON.stringify(arm)};\nlet token; if(!arm.startsWith('python')&&arm!=='adapter-term'){token=Buffer.alloc(1);fs.readSync(3,token,0,1,null);}\nconst child=spawn(process.execPath,['-e',"process.on('SIGTERM',()=>{});process.on('SIGINT',()=>{});process.stdout.write('READY\\\\n');setInterval(()=>{},1000)"],{stdio:['ignore','pipe','ignore']});\nlet closing=false;function finish(s){fs.appendFileSync(signals,JSON.stringify({signal:s,time:Date.now()})+'\\n');if(closing)return;closing=true;setTimeout(()=>{if(token)fs.writeSync(4,token);process.exit(0)},1300);}\nfor(const s of ['SIGINT','SIGTERM'])process.on(s,()=>finish(s));\nchild.stdout.once('data',()=>{fs.writeFileSync(marker,JSON.stringify({pid:process.pid,child:child.pid,byte:token?.toString()}));if(arm==='exit-int')setTimeout(()=>{if(token)fs.writeSync(4,token);process.exit(0)},150);});setInterval(()=>{},1000);\n`);
 let argv=['node',leaf];let native;
 if(arm.startsWith('python')||arm==='normal-native'){
  native=dir+'/native';fs.mkdirSync(native);fs.copyFileSync(runtime+'/stdlib/build.py',native+'/build.py');fs.mkdirSync(native+'/scripts');fs.copyFileSync(runtime+'/stdlib/scripts/ninja-jobserver.mjs',native+'/scripts/ninja-jobserver.mjs');fs.copyFileSync(runtime+'/stdlib/scripts/command-supervisor.mjs',native+'/scripts/command-supervisor.mjs');fs.copyFileSync(runtime+'/stdlib/scripts/command-supervisor.source.json',native+'/scripts/command-supervisor.source.json');
  write(native+'/cmake/linux_x86_64_toolchain.cmake','# bounded native fixture uses host compiler\n');
  write(native+'/value.c','#include <stdio.h>\nint main(void){puts("42");return 0;}\n');
  write(native+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.16)\nproject(CancelOwner C)\nset(CMAKE_C_COMPILER_LAUNCHER node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command --)\nadd_executable(value value.c)\nadd_custom_target(hold COMMAND node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command -- node "${leaf}" VERBATIM)\ninstall(TARGETS value RUNTIME DESTINATION bin)\n`);
  argv=['python3','-I',native+'/build.py','build','-t','release','--jobs','4','--build-target',arm==='normal-native'?'value':'hold'];
 }else if(arm==='adapter-term')argv=['node',runtime+'/stdlib/scripts/ninja-jobserver.mjs','run','--jobs','4','--','node',leaf];
 if(arm==='spawn-int'){
  const hook=dir+'/spawn-hook.mjs';write(hook,`import cp from 'node:child_process';import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';const real=cp.spawn;cp.spawn=function(...args){const c=real(...args);if(args[1]?.includes(${JSON.stringify(leaf)})){fs.writeFileSync(${JSON.stringify(dir+'/spawn.json')},JSON.stringify({owner:process.pid,child:c.pid}));cp.spawnSync('/bin/kill',['-INT',String(process.pid)]);}return c;};syncBuiltinESMExports();`);
  // Install the hook only in the deepest public SDK, at its real spawn return.
  const inner=config(dir+'/level0',argv);argv=['node','--import',hook,cli,'--config',inner,'--no-package'];
 }
 const depth=arm==='owner-lost'?2:arm.startsWith('three')?3:1;const configs=[];
 for(let n=0;n<depth;n++){const c=config(dir+'/level'+(n+1),argv);configs.push(c);argv=['node',cli,'--config',c,'--no-package'];}
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 const env={...process.env,MAKEFLAGS:'-j3 --jobserver-auth=3,4',CANGJIE_JOBSERVER_LOG:log};delete env.CARGO_MAKEFLAGS;delete env.MFLAGS;delete env.CJCJ_COMMAND_LIFETIME_FD;
 const control=spawn('node',['-e','setInterval(()=>{},1000)'],{cwd:dir,stdio:'ignore'}),controlId=await until(()=>identity(control.pid),control);
 const p=spawn(argv[0],argv.slice(1),{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});
 const end=new Promise(resolve=>p.once('close',(rc,signal)=>resolve({rc,signal})));const start=Date.now();let result,observed,timedOut=false,lostOwner;
 try{
  if(arm!=='normal-native'&&arm!=='spawn-int'){
   const ready=await until(()=>fs.existsSync(marker)&&JSON.parse(read(marker)),p);remember(p.pid,known);
   if(arm==='exit-int')await until(()=>!alive(known.get(ready.pid)),p);
   if(arm==='owner-lost'){
    const leafId=known.get(ready.pid);let parent=known.get(leafId.ppid);
    while(parent&&parent.pid!==p.pid){const args=read('/proc/'+parent.pid+'/cmdline').split('\0');if(args.includes(cli)){lostOwner=parent;break;}parent=known.get(parent.ppid);}
    assert(lostOwner&&lostOwner.pid!==p.pid&&alive(lostOwner),'exact active inner SDK owner reached');
    write(dir+'/lost-owner.json',JSON.stringify({owner:lostOwner,leaf:leafId,known:[...known.values()]},null,2));
    process.kill(lostOwner.pid,'SIGKILL');
   }else p.kill(arm.endsWith('int')?'SIGINT':'SIGTERM');
  }
  const sampling=setInterval(()=>remember(p.pid,known),25);
  const timer=setTimeout(()=>{timedOut=true;fs.writeFileSync(dir+'/timeout.json',JSON.stringify({known:[...known.values()]}));p.kill('SIGKILL');},18000);
  result=await end;clearTimeout(timer);clearInterval(sampling);fs.closeSync(out);fs.closeSync(err);
  const bytes=Buffer.alloc(32);let count=0;try{count=fs.readSync(fd,bytes,0,32,null);}catch(e){if(e.code!=='EAGAIN')throw e;}
  const live=[...known.values()].filter(alive),events=fs.existsSync(log)?read(log).trim().split('\n').filter(Boolean).map(JSON.parse):[];
  const states=configs.map(c=>{const file=path.dirname(c)+'/work/build-result.json';return arm==='owner-lost'&&!fs.existsSync(file)?{missing:file}:JSON.parse(read(file));});
  const received=fs.existsSync(signals)?read(signals).trim().split('\n').filter(Boolean).map(JSON.parse):[];
  observed={arm,argv,...result,timedOut,lostOwner,wallMs:Date.now()-start,tokens:bytes.subarray(0,count).toString(),known:[...known.values()],liveBeforeCleanup:live,unrelatedAlive:!!alive(controlId),events,states,received};
  write(dir+'/observed-before-cleanup.json',JSON.stringify(observed,null,2));rows.push(observed);write(root+'/results.json',JSON.stringify(rows,null,2));
  if(arm==='owner-lost'){
   console.log(JSON.stringify({event:'OWNER_LOSS_TARGET_ASSERTION_REACHED',timedOut,live:live.length,tokens:observed.tokens,unrelatedAlive:observed.unrelatedAlive}));
   assert.equal(live.length,0,'active inner owner lost: all owned descendants reclaimed before test cleanup');
   assert.equal(timedOut,false,'active peer exit must terminate without test timeout');
  }
  const expected=arm==='normal-native'?0:arm.endsWith('int')?130:143;
  if(arm==='owner-lost')assert(result.rc!==0&&result.rc!==null,arm+' failed public parent rc');else assert.equal(result.rc,expected,arm+' public parent rc');assert.equal([...observed.tokens].sort().join(''),'AB',arm+' original upstream bytes');assert.equal(live.length,0,arm+' owned descendants');assert(observed.unrelatedAlive,arm+' independent process control');assert(observed.wallMs<18000,arm+' bounded termination');
  if(arm.startsWith('python')||arm==='adapter-term'||arm==='normal-native'){
   assert(events.some(e=>e.event==='pool-start'&&e.borrowed===2),arm+' actual budget borrow positive');assert(events.some(e=>e.event==='parent-return'&&e.count===2),arm+' actual budget return');
  }
  if(arm==='normal-native'){
   const binary=native+'/build/build/value';const consumed=spawnSync(binary,[],{encoding:'utf8'});write(dir+'/native-consumer.json',JSON.stringify({argv:[binary],rc:consumed.status,stdout:consumed.stdout,stderr:consumed.stderr}));assert.equal(consumed.status,0);assert.equal(consumed.stdout.trim(),'42');
  }
  if(arm.startsWith('three')){assert.equal(states.length,3);assert(states.every(s=>s.status==='FAILED'));assert.equal(states[0].commands.at(-1).rc,0,'actual leaf rc retained');}
  if(arm==='spawn-int')assert(fs.existsSync(dir+'/spawn.json'),'actual spawn boundary reached');
  console.log(JSON.stringify({arm,rc:result.rc,tokens:observed.tokens,live:live.length,wallMs:observed.wallMs,pass:true}));
 }finally{
  // Observation and assertions precede cleanup. Never use cleanup as evidence.
  for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');
  if(alive(controlId))process.kill(controlId.pid,'SIGKILL');fs.closeSync(fd);await delay(100);
  write(dir+'/cleanup.json',JSON.stringify({remaining:[...known.values()].filter(alive)},null,2));
 }
}
