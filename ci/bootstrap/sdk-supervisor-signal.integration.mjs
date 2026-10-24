#!/usr/bin/env zx
// Public SDK and the vendored build.py launcher; observe before exact cleanup.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root]=process.argv.slice(2);
assert(source&&runtime&&root);fs.mkdirSync(root,{recursive:true});
const read=f=>fs.readFileSync(f,'utf8');
const write=(f,v)=>fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');
const events=f=>fs.existsSync(f)?read(f).trim().split('\n').filter(Boolean).map(JSON.parse):[];
function identity(pid){try{const t=read('/proc/'+pid+'/stat'),v=t.slice(t.lastIndexOf(')')+2).split(' ');return{pid,start:v[19],state:v[0],ppid:+v[1],cwd:fs.readlinkSync('/proc/'+pid+'/cwd')};}catch(e){if(['ENOENT','ESRCH'].includes(e.code))return null;throw e;}}
const alive=id=>{const now=id&&identity(id.pid);return now&&now.start===id.start&&now.state!=='Z';};
async function until(fn,label,ms=10000){const end=Date.now()+ms;while(Date.now()<end){const x=fn();if(x)return x;await delay(10);}throw Error('FIXTURE_TIMEOUT '+label);}
const probe=spawnSync('python3',['-I','-c',`import signal,json
values=[signal.SIGRTMIN+1,signal.SIGRTMAX-1]
print(json.dumps({'unnamed':values,'names':{int(x):x.name for x in signal.Signals},'valid':[int(x) for x in signal.valid_signals()]}))`],{encoding:'utf8'});
assert.equal(probe.status,0);const signals=JSON.parse(probe.stdout);for(const n of signals.unnamed){assert(signals.valid.includes(n));assert(!signals.names[n]);}write(root+'/signals.json',signals);
const arms=process.env.SDK_SIGNAL_ARMS?.split(',')||['sdk-rtlow','sdk-rthigh','sdk-normal','sdk-int','sdk-term','vendor-rtlow','vendor-normal','vendor-term'];
const rows=[];
for(const arm of arms){
 const dir=root+'/'+arm;fs.mkdirSync(dir);const marker=dir+'/payload.json',release=dir+'/release',log=dir+'/events.jsonl',pool=dir+'/pool';
 assert.equal(spawnSync('mkfifo',[pool]).status,0);const fd=fs.openSync(pool,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,'AB');
 const drain=()=>{const b=Buffer.alloc(32);try{return b.subarray(0,fs.readSync(fd,b,0,b.length,null)).toString();}catch(e){if(e.code==='EAGAIN')return '';throw e;}};
 const kind=arm.split('-')[1],sig=kind==='rtlow'?signals.unnamed[0]:kind==='rthigh'?signals.unnamed[1]:kind==='int'?2:kind==='term'?15:null;
 const childCode="import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);signal.signal(signal.SIGINT,signal.SIG_IGN);print('ready',flush=True);time.sleep(60)";
 const payload=['python3','-I','-c',`import os,json,time,subprocess,signal
from pathlib import Path
signal.signal(signal.SIGINT,signal.SIG_DFL)
p=subprocess.Popen(['python3','-I','-c',${JSON.stringify(childCode)}],stdout=subprocess.PIPE,start_new_session=True)
assert p.stdout.readline()==b'ready\\n'
Path(${JSON.stringify(marker)}).write_text(json.dumps({'pid':os.getpid(),'child':p.pid}))
while not Path(${JSON.stringify(release)}).exists():time.sleep(.01)
`];
 const env={...process.env,MAKEFLAGS:'-j3 --jobserver-auth=3,4',CANGJIE_JOBSERVER_LOG:log,CJCJ_SUPERVISOR_WORK:dir+'/supervisor-work'};
 for(const key of ['CARGO_MAKEFLAGS','MFLAGS','CJCJ_COMMAND_LIFETIME_FD','CJCJ_SUPERVISOR_OWNER_FD'])delete env[key];
 const cfg=dir+'/config.json';write(cfg,{work:dir+'/work',install:dir+'/install',repos:{},test:{},finalStage:'one',stages:[{id:'one',output:dir+'/install',commands:[{argv:payload}]}]});
 const argv=arm.startsWith('sdk-')?[process.execPath,source+'/ci/bootstrap/sdk-build.mjs','--config',cfg,'--no-package']:[process.execPath,runtime+'/stdlib/scripts/command-supervisor.mjs','--',...payload];
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 const control=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'}),independent=await until(()=>identity(control.pid),'independent');
 const p=spawn(argv[0],argv.slice(1),{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});let result; p.once('exit',(rc,signal)=>{result={rc,signal};});
 const known=new Map(),capture=pid=>{const id=identity(pid);if(id)known.set(pid,id);return id;};capture(p.pid);
 try{
  const ready=await until(()=>fs.existsSync(marker)&&JSON.parse(read(marker)),'payload ready');capture(ready.pid);capture(ready.child);
  const g=await until(()=>events(log).find(e=>e.event==='supervisor-ready'),'guardian');capture(g.pid);
  assert(alive(known.get(ready.child)),'independent-session descendant really running');
  if(sig===null)write(release,'go');else process.kill(ready.pid,sig);
  await until(()=>events(log).some(e=>e.event==='parent-return'),'original bytes returned');
  const end=Date.now()+1500;while(!result&&Date.now()<end)await delay(10);
  const es=events(log),finished=es.find(e=>e.event==='supervisor-finished'),exit=es.find(e=>e.event==='supervisor-payload-exit');
  const first=drain();await delay(50);const extra=drain();
  const observation={arm,argv,signalNumber:sig,result:result||null,childExit:exit,finished:finished||null,tokens:first,extraTokens:extra,events:es,liveBeforeCleanup:[...known.values()].filter(alive),identities:[...known.values()],unrelatedAlive:!!alive(independent)};
  write(dir+'/observed-before-cleanup.json',observation);rows.push(observation);write(root+'/results.json',rows);
  console.log(JSON.stringify({event:'SIGNAL_FINISH_TARGET_ASSERTION_REACHED',arm,rc:result?.rc??null,childRc:exit?.childRc,signal:sig,tokens:first,extraTokens:extra,live:observation.liveBeforeCleanup.map(x=>x.pid)}));
  assert(observation.unrelatedAlive);assert.equal(exit.childRc,sig===null?0:-sig,'kernel child status retained');
  assert.equal(first,'AB');assert.equal(extra,'');assert.equal(es.filter(e=>e.event==='parent-return').length,1);
  assert(result,'public entry and guardian must actually terminate after settled ledger');
  assert.equal(result.rc,sig===null?0:128+sig);assert.equal(result.signal,null);
  assert.equal(observation.liveBeforeCleanup.length,0,'no guardian or payload survivor before cleanup');
  assert(finished.reaped&&finished.ledgerReturned);assert.equal(finished.childRc,sig===null?0:-sig);
  assert.equal(finished.childSignalNumber,sig);assert.equal(finished.childSignal,sig===null?null:signals.names[sig]||null);
  console.log(JSON.stringify({arm,pass:true}));
 }finally{
  for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');
  if(alive(independent))process.kill(independent.pid,'SIGKILL');
  await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});
  fs.closeSync(out);fs.closeSync(err);fs.closeSync(fd);
 }
}
