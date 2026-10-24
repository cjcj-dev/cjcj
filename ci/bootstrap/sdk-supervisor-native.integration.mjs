#!/usr/bin/env zx
// Actual bounded native compiler overlap through SDK -> build.py -> Ninja.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root]=process.argv.slice(2);assert(source&&runtime&&root);fs.mkdirSync(root,{recursive:true});
const read=f=>fs.readFileSync(f,'utf8'),write=(f,v)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');};
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
function identity(pid){try{const s=read('/proc/'+pid+'/stat'),f=s.slice(s.lastIndexOf(')')+2).split(' ');return {pid,start:f[19],state:f[0],ppid:+f[1],cwd:fs.readlinkSync('/proc/'+pid+'/cwd'),exe:fs.readlinkSync('/proc/'+pid+'/exe'),argv:read('/proc/'+pid+'/cmdline').split('\0').filter(Boolean)};}catch(e){if(['ENOENT','ESRCH','EACCES'].includes(e.code))return null;throw e;}}
const alive=id=>{const r=id&&identity(id.pid);return r&&r.start===id.start&&r.state!=='Z';};
const rows=[];
for(const jobs of [1,3]){
 const dir=root+'/j'+jobs,native=dir+'/native',prefix=dir+'/install',log=dir+'/events.jsonl';fs.mkdirSync(native,{recursive:true});
 for(const rel of ['build.py','scripts/ninja-jobserver.mjs','scripts/command-supervisor.mjs','scripts/command-supervisor.source.json']){fs.mkdirSync(path.dirname(native+'/'+rel),{recursive:true});fs.copyFileSync(runtime+'/stdlib/'+rel,native+'/'+rel);}
 write(native+'/cmake/linux_x86_64_toolchain.cmake','# finite native host compiler\n');
 const body='#include <stdio.h>\n'+Array.from({length:2500},(_,i)=>`int fn${i}(int x){return (x * ${i+1}) ^ ${i+7};}`).join('\n')+'\nint main(void){puts("42");return 0;}\n';
 for(const n of ['a','b','c'])write(native+'/'+n+'.c',body);
 write(native+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.16)\nproject(NativeBudget C)\nset(CMAKE_C_COMPILER_LAUNCHER node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command --)\nset(CMAKE_C_LINKER_LAUNCHER node "\${CMAKE_CURRENT_SOURCE_DIR}/scripts/ninja-jobserver.mjs" command --)\nforeach(n a b c)\n add_executable(\${n} \${n}.c)\n install(TARGETS \${n} RUNTIME DESTINATION bin)\nendforeach()\n`);
 const cfg=dir+'/config.json';write(cfg,{work:dir+'/work',install:prefix,repos:{},finalStage:'one',test:{required:['bin/a','bin/b','bin/c'],commands:['a','b','c'].map(n=>({argv:['${install}/bin/'+n]}))},stages:[{id:'one',output:prefix,commands:[{argv:['python3','-I',native+'/build.py','build','-t','release','--jobs',String(jobs)]},{argv:['python3','-I',native+'/build.py','install','--prefix',prefix]}]}]});
 const fifo=dir+'/parent.fifo';assert.equal(spawnSync('mkfifo',[fifo]).status,0);const fd=fs.openSync(fifo,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,'AB');
 const env={...process.env,MAKEFLAGS:'--jobserver-auth=3,4 -j3',CANGJIE_JOBSERVER_LOG:log,CCACHE_DISABLE:'1'};delete env.CARGO_MAKEFLAGS;delete env.MFLAGS;
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w'),known=new Map(),samples=[];
 const p=spawn(process.execPath,[source+'/ci/bootstrap/sdk-build.mjs','--config',cfg,'--no-package'],{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});
 const sample=()=>{const ps=fs.readdirSync('/proc').filter(x=>/^\d+$/.test(x)).map(x=>identity(+x)).filter(Boolean);const family=new Set([p.pid,...[...known.values()].filter(alive).map(x=>x.pid)]);let changed=true;while(changed){changed=false;for(const r of ps)if(family.has(r.ppid)&&!family.has(r.pid)){family.add(r.pid);changed=true;}}for(const r of ps)if(family.has(r.pid))known.set(r.pid,r);const compilers=ps.filter(r=>family.has(r.pid)&&r.cwd===native+'/build/build'&&r.argv.includes('-c')&&r.argv.some(x=>['a.c','b.c','c.c'].some(n=>x===native+'/'+n))&&/(?:clang|cc1|gcc)(?:-\d+)?$/.test(r.exe));if(compilers.length)samples.push({time:process.hrtime.bigint().toString(),compilers});};
 let timeout=false;const sampling=setInterval(sample,10),timer=setTimeout(()=>{timeout=true;p.kill('SIGKILL');},60000);
 try{
  const result=await new Promise(resolve=>p.once('exit',(rc,signal)=>resolve({rc,signal})));clearInterval(sampling);clearTimeout(timer);sample();fs.closeSync(out);fs.closeSync(err);
  const bytes=Buffer.alloc(16),n=fs.readSync(fd,bytes,0,16,null),es=read(log).trim().split('\n').filter(Boolean).map(JSON.parse);
  const binaries=['a','b','c'].map(name=>({name,path:prefix+'/bin/'+name,sha256:hash(prefix+'/bin/'+name)}));
  const observed={jobs,...result,timeout,tokens:bytes.subarray(0,n).toString(),samples,peak:Math.max(0,...samples.map(s=>s.compilers.length)),events:es,binaries,sourceSha256:hash(native+'/a.c'),liveBeforeCleanup:[...known.values()].filter(alive),identities:[...known.values()]};write(dir+'/observed-before-cleanup.json',observed);rows.push(observed);write(root+'/results.json',rows);
  console.log(JSON.stringify({event:'NATIVE_OVERLAP_TARGET_ASSERTION_REACHED',jobs,rc:result.rc,peak:observed.peak,samples:samples.length}));
  assert.equal(result.rc,0);assert(!timeout);assert.equal(observed.liveBeforeCleanup.length,0);assert.equal([...observed.tokens].sort().join(''),'AB');
  assert(samples.length>0,'actual compiler executable sampled');assert(observed.peak<=jobs,'no nested multiplication');assert.equal(observed.peak>1,jobs>1,'actual simultaneous compiler processes, not thread count');
  const pool=es.find(e=>e.event==='pool-start');assert.equal(pool.jobs,jobs);assert(es.some(e=>e.event==='pool-end'&&e.returned===jobs));
  assert.equal((read(dir+'/stdout').match(/(?:^|\n)42\n/g)||[]).length,3,'three installed consumers actually execute');
  if(jobs===3){assert.equal(rows[0].sourceSha256,observed.sourceSha256);assert.deepEqual(rows[0].binaries.map(x=>x.sha256),binaries.map(x=>x.sha256),'same input compiled output deterministic at J1/J3');}
  console.log(JSON.stringify({jobs,pass:true,peak:observed.peak,installed:binaries.length}));
 }finally{clearTimeout(timer);clearInterval(sampling);sample();for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');fs.closeSync(fd);await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});}
}
