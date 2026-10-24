#!/usr/bin/env zx
// Finite public-entry FD/byte/error controls; no compiler stage or shared state.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root]=process.argv.slice(2);assert(source&&runtime&&root);fs.mkdirSync(root,{recursive:true});
const cli=source+'/ci/bootstrap/sdk-build.mjs',adapter=runtime+'/stdlib/scripts/ninja-jobserver.mjs';
const read=f=>fs.readFileSync(f,'utf8'),write=(f,v)=>fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');
const events=f=>fs.existsSync(f)?read(f).trim().split('\n').filter(Boolean).map(JSON.parse):[];
function identity(pid){try{const s=read('/proc/'+pid+'/stat'),f=s.slice(s.lastIndexOf(')')+2).split(' ');return {pid,start:f[19],state:f[0],ppid:+f[1],cwd:fs.readlinkSync('/proc/'+pid+'/cwd'),exe:fs.readlinkSync('/proc/'+pid+'/exe')};}catch(e){if(['ENOENT','ESRCH','EACCES'].includes(e.code))return null;throw e;}}
const alive=id=>{const now=id&&identity(id.pid);return now&&now.start===id.start&&now.state!=='Z';};
function remember(pid,known){const rows=fs.readdirSync('/proc').filter(x=>/^\d+$/.test(x)).map(x=>identity(+x)).filter(Boolean);const owners=new Set([pid,...[...known.values()].filter(alive).map(x=>x.pid)]);let changed=true;while(changed){changed=false;for(const row of rows)if(owners.has(row.ppid)&&!owners.has(row.pid)){owners.add(row.pid);changed=true;}}for(const row of rows)if(owners.has(row.pid))known.set(row.pid,row);}
async function until(fn,label){for(let i=0;i<1200;i++){const v=fn();if(v)return v;await delay(10);}throw Error('FIXTURE_TIMEOUT '+label);}
const arms=process.env.SDK_PROTOCOL_ARMS?.split(',')||['numeric','fifo','same-fd','precedence','single','partial','empty','disabled','noauth','adapter-cap','adapter-noauth','adapter-disabled','bad-fd','spawn-fail','imbalance','missing-python','api-fail','status-invalid','return-blocked','make-pipe','adapter-failure','direct-int','direct-term','vendor-missing'];
const rows=[];
for(const arm of arms){
 const dir=root+'/'+arm;fs.mkdirSync(dir);const known=new Map(),log=dir+'/events.jsonl',marker=dir+'/payload.json';
 const fifo=dir+'/parent.fifo';assert.equal(spawnSync('mkfifo',[fifo]).status,0);const fd=fs.openSync(fifo,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);
 const seed=arm==='partial'?'A':arm==='empty'?'':'AB';if(seed)fs.writeSync(fd,seed);
 const flags=read('/proc/self/fdinfo/'+fd).match(/^flags:\s*(\S+)/m)[1];
 const probe=dir+'/probe.mjs';write(probe,`import fs from 'node:fs';const auth=process.env.MAKEFLAGS?.match(/--jobserver-auth=(\\d+),(\\d+)/);const bytes=[];if(auth){for(;;){try{const b=Buffer.alloc(1),n=fs.readSync(+auth[1],b,0,1,null);if(!n)throw Error('EOF');bytes.push(b[0]);}catch(e){if(e.code==='EAGAIN')break;throw e;}}if(${JSON.stringify(arm)}!=='imbalance')for(const b of bytes)fs.writeSync(+auth[2],Buffer.from([b]));}fs.writeFileSync(${JSON.stringify(marker)},JSON.stringify({pid:process.pid,parent:process.ppid,auth:auth?.[0],extra:bytes.length,flags:process.env.MAKEFLAGS}));console.log('ACTUAL_FD_CONSUMER '+bytes.length);${['return-blocked','direct-int','direct-term'].includes(arm)?'setInterval(()=>{},1000);':''}`);
 let argv=[process.execPath,probe];if(arm.startsWith('adapter-')||arm.startsWith('direct-'))argv=[process.execPath,adapter,'run','--jobs',arm==='adapter-cap'?'1':'4','--',process.execPath,adapter,'command','--',...argv];
 if(arm==='spawn-fail')argv=[dir+'/missing-executable'];
 if(arm==='vendor-missing'){fs.mkdirSync(dir+'/native/scripts',{recursive:true});fs.copyFileSync(runtime+'/stdlib/build.py',dir+'/native/build.py');argv=['python3','-I',dir+'/native/build.py','build','-t','release','--jobs','1'];}
 if(arm==='adapter-failure')argv=[process.execPath,adapter,'run','--jobs','4','--',process.execPath,adapter,'command','--',process.execPath,'-e','console.error("FIRST_COMMAND_ERROR_7");process.exit(7)'];
 const cfg=dir+'/config.json';write(cfg,{work:dir+'/work',install:dir+'/install',repos:{},test:{},finalStage:'one',stages:[{id:'one',output:dir+'/install',commands:[{argv}]}]});
 const env={...process.env,CANGJIE_JOBSERVER_LOG:log};for(const k of ['MAKEFLAGS','CARGO_MAKEFLAGS','MFLAGS','CJCJ_COMMAND_LIFETIME_FD','CJCJ_SUPERVISOR_OWNER_FD'])delete env[k];
 env.MAKEFLAGS='--jobserver-auth=3,4 -j'+(arm==='single'?'1':'3');
 if(arm==='fifo')env.MAKEFLAGS='--jobserver-auth=fifo:'+fifo+' -j3';
 if(arm==='same-fd')env.MAKEFLAGS='--jobserver-auth=3,3 -j3';
 if(arm==='precedence'){env.CARGO_MAKEFLAGS=env.MAKEFLAGS;env.MAKEFLAGS='--jobserver-auth=998,999 -j16';}
 if(arm==='disabled'||arm==='adapter-disabled')env.MAKEFLAGS='--jobserver-auth=-1,-1 -j64';
 if(arm==='noauth'||arm==='adapter-noauth')delete env.MAKEFLAGS;
 if(arm==='bad-fd')env.MAKEFLAGS='--jobserver-auth=998,999 -j3';
 if(arm==='missing-python'){fs.mkdirSync(dir+'/empty-path');env.PATH=dir+'/empty-path';}
 let prefix=[];
 if(arm==='api-fail'||arm==='status-invalid'){
  const hook=dir+'/hook.mjs';const from=arm==='api-fail'?'libc.prctl(36,1,0,0,0)':"data=(json.dumps(row)+'\\n').encode()";
  const to=arm==='api-fail'?'libc.prctl(999999,1,0,0,0)':"data=(('not-json' if row.get('type')=='ready' else json.dumps(row))+'\\n').encode()";
  write(hook,`import cp from 'node:child_process';import {syncBuiltinESMExports}from'node:module';import assert from 'node:assert/strict';const original=cp.spawn;cp.spawn=function(...a){if(a[0]==='python3'&&a[1]?.[1]==='-c'){assert(a[1][2].includes(${JSON.stringify(from)}));a[1]=[...a[1]];a[1][2]=a[1][2].replace(${JSON.stringify(from)},${JSON.stringify(to)});}return original(...a);};syncBuiltinESMExports();`);prefix=['--import',hook];
 }
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 let executable=process.execPath,args=[...prefix,cli,'--config',cfg,'--no-package'];
 if(arm.startsWith('direct-')){executable=argv[0];args=argv.slice(1);}
 if(arm==='make-pipe'){write(dir+'/Makefile','all:\n\t+'+process.execPath+' '+cli+' --config '+cfg+' --no-package\n');executable='make';args=['-s','-j3','-f',dir+'/Makefile'];delete env.MAKEFLAGS;}
 const p=spawn(executable,args,{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});
 const done=new Promise(resolve=>p.once('exit',(rc,signal)=>resolve({rc,signal}))),sampler=setInterval(()=>remember(p.pid,known),15);
 let timeout=false,filler=0,incomplete;const timer=setTimeout(()=>{timeout=true;p.kill('SIGKILL');},20000);
 let returned=Buffer.alloc(0);const drain=()=>{for(;;){try{const b=Buffer.alloc(65536),n=fs.readSync(fd,b,0,b.length,null);if(!n)break;returned=Buffer.concat([returned,b.subarray(0,n)]);}catch(e){if(e.code==='EAGAIN')break;throw e;}}};
 try{
  if(arm.startsWith('direct-')){await until(()=>fs.existsSync(marker),'actual-direct-payload');remember(p.pid,known);p.kill(arm.endsWith('int')?'SIGINT':'SIGTERM');}
  if(arm==='return-blocked'){
   await until(()=>fs.existsSync(marker),'live-payload');remember(p.pid,known);
   for(;;){try{filler+=fs.writeSync(fd,Buffer.alloc(4096,90));}catch(e){if(e.code==='EAGAIN')break;throw e;}}
   assert(filler>0);p.kill('SIGTERM');
   incomplete=await until(()=>events(log).find(e=>e.event==='supervisor-incomplete'),'real-return-block');
   const g=known.get(incomplete.pid);assert(alive(g),'ledger owner remains alive after incomplete');
   const status=JSON.parse(read(events(log).find(e=>e.event==='supervisor-ready').directory+'/status.json'));
   write(dir+'/blocked-ledger.json',{status,identity:g,filler});assert.equal(status.unreturnedHex,'4142');
   assert.equal(status.returned,0);assert.equal(status.reaped,true);drain();
   await until(()=>events(log).some(e=>e.event==='supervisor-finished'),'real-return-recovered');
   await until(()=>!alive(g),'guardian-exit-after-recovery');
  }
  const result=await done;clearTimeout(timer);clearInterval(sampler);remember(p.pid,known);drain();fs.closeSync(out);fs.closeSync(err);
  const es=events(log),probeResult=fs.existsSync(marker)?JSON.parse(read(marker)):null;
  const observed={arm,...result,timeout,seed,filler,tokens:returned.toString(),probe:probeResult,events:es,liveBeforeCleanup:[...known.values()].filter(alive),identities:[...known.values()],flagsBefore:flags,flagsAfter:read('/proc/self/fdinfo/'+fd).match(/^flags:\s*(\S+)/m)[1]};
  write(dir+'/observed-before-cleanup.json',observed);rows.push(observed);write(root+'/results.json',rows);
  console.log(JSON.stringify({event:'PROTOCOL_TARGET_ASSERTION_REACHED',arm,rc:result.rc,timeout,live:observed.liveBeforeCleanup.length}));
  assert(!timeout);assert.equal(observed.liveBeforeCleanup.length,0);assert.equal(observed.flagsAfter,flags);
  assert.equal([...returned].filter(x=>x!==90).sort().map(x=>String.fromCharCode(x)).join(''),[...seed].sort().join(''),'actual original bytes');
  const negative=['bad-fd','spawn-fail','imbalance','missing-python','api-fail','status-invalid','return-blocked','adapter-failure','direct-int','direct-term','vendor-missing'].includes(arm);
  assert.equal(result.rc===0,!negative);if(negative)assert(result.rc!==null);
  if(['bad-fd','spawn-fail','missing-python','api-fail','status-invalid'].includes(arm))assert.equal(probeResult,null,'no payload on failed preflight/spawn/GO');
  if(['api-fail','missing-python','bad-fd'].includes(arm))assert(!es.some(x=>x.event==='scope-budget'),'no borrow on unavailable API/FD');
  if(!negative){
   const extra=['single','empty','disabled','noauth','adapter-cap','adapter-disabled'].includes(arm)?0:arm==='partial'?1:arm==='adapter-noauth'?3:2;
   assert.equal(probeResult.extra,extra,'actual implicit-plus-bytes budget');
   if(arm==='noauth')assert.equal(probeResult.auth,undefined);
  }
  if(arm==='vendor-missing'){assert.equal(probeResult,null);assert.match(read(dir+'/stderr'),/Cannot find module.*command-supervisor/);assert(!fs.existsSync(dir+'/native/build/build/CMakeCache.txt'));}
  if(arm==='adapter-failure'){assert.equal(result.rc,7);assert.match(read(dir+'/stderr'),/FIRST_COMMAND_ERROR_7/);assert(es.some(e=>e.event==='command-end'&&e.rc===7));}
  if(arm.startsWith('direct-'))assert.equal(result.rc,arm.endsWith('int')?130:143);
  if(arm==='make-pipe')assert(es.some(e=>e.event==='parent-return'&&e.count===2));
  if(arm==='imbalance')assert.match(read(dir+'/stdout'),/JOBSERVER_TOKEN_IMBALANCE/);
  if(arm==='spawn-fail')assert.match(read(dir+'/stdout'),/SUPERVISOR_SPAWN/);
  if(arm==='api-fail')assert.match(read(dir+'/stdout'),/SUPERVISOR_API/);
  if(arm==='missing-python')assert.match(read(dir+'/stderr'),/SUPERVISOR_DEPENDENCY python3/);
  if(arm==='return-blocked'){assert.equal([...returned].filter(x=>x===90).length,filler);assert(es.some(x=>x.event==='parent-return'&&x.originalHex==='4142'));}
  console.log(JSON.stringify({arm,pass:true,rc:result.rc,extra:probeResult?.extra}));
 }finally{
  clearTimeout(timer);clearInterval(sampler);remember(p.pid,known);for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');fs.closeSync(fd);await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});
 }
}
