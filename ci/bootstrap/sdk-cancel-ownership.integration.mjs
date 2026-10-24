#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source, root, mode='old'] = process.argv.slice(2);
fs.mkdirSync(root,{recursive:true});
const cli=path.join(source,'ci/bootstrap/sdk-build.mjs');
function identity(pid) {try {const s=fs.readFileSync(`/proc/${pid}/stat`,'utf8');const f=s.slice(s.lastIndexOf(')')+2).split(' ');return {pid,start:f[19],state:f[0],ppid:+f[1],pgrp:+f[2],cwd:fs.readlinkSync(`/proc/${pid}/cwd`),exe:fs.readlinkSync(`/proc/${pid}/exe`)};}catch(e){if(['ENOENT','ESRCH','EACCES'].includes(e.code))return null;throw e;}}
const alive=id=>{const now=identity(id.pid);return now&&now.start===id.start&&now.state!=='Z';};
async function waitFile(file,p){for(let i=0;i<400;i++){if(fs.existsSync(file))return JSON.parse(fs.readFileSync(file));if(p.exitCode!==null)break;await delay(20);}throw Error('READY_NOT_REACHED '+file);}
function config(dir,argv){fs.mkdirSync(dir,{recursive:true});const c={work:dir+'/work',install:dir+'/install',repos:{},test:{},finalStage:'one',stages:[{id:'one',output:dir+'/install',commands:[{argv}]}]};fs.writeFileSync(dir+'/config.json',JSON.stringify(c));return dir+'/config.json';}
const rows=[];
for(const arm of ['normal','int','term','nested-term']){
 const dir=root+'/'+arm;fs.mkdirSync(dir);const marker=dir+'/ready.json',signals=dir+'/signals.jsonl';
 const leaf=dir+'/leaf.mjs';fs.writeFileSync(leaf,`import fs from 'node:fs';import {spawn} from 'node:child_process';\nconst arm=${JSON.stringify(arm)},marker=${JSON.stringify(marker)},signals=${JSON.stringify(signals)};\nif(arm==='normal')process.exit(0);\nlet closing=false;for(const s of ['SIGINT','SIGTERM'])process.on(s,()=>{fs.appendFileSync(signals,JSON.stringify({signal:s,time:Date.now()})+'\\n');if(!closing){closing=true;setTimeout(()=>process.exit(0),arm==='nested-term'?1300:100);}});\nlet child;if(arm==='nested-term')child=spawn(process.execPath,['-e',"process.on('SIGTERM',()=>{});process.on('SIGINT',()=>{});process.stdout.write('ready\\\\n');setInterval(()=>{},1000)"],{stdio:['ignore','pipe','ignore']});\nfunction ready(){fs.writeFileSync(marker,JSON.stringify({pid:process.pid,child:child?.pid}));}\nif(child)child.stdout.once('data',ready);else ready();setInterval(()=>{},1000);\n`);
 let cfg=config(dir+'/inner',['node',leaf]);if(arm==='nested-term')cfg=config(dir+'/outer',['node',cli,'--config',cfg,'--no-package']);
 const argv=['node',cli,'--config',cfg,'--no-package'],out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 const p=spawn(argv[0],argv.slice(1),{cwd:dir,stdio:['ignore',out,err]});const end=new Promise(resolve=>p.once('close',(rc,signal)=>resolve({rc,signal})));
 let ids=[],result;
 try{
  if(arm!=='normal'){const ready=await waitFile(marker,p);ids=Object.values(ready).filter(Number.isInteger).map(identity).filter(Boolean);fs.writeFileSync(dir+'/identities-before.json',JSON.stringify(ids,null,2));p.kill(arm==='int'?'SIGINT':'SIGTERM');}
  const timer=setTimeout(()=>p.kill('SIGKILL'),15000);result=await end;clearTimeout(timer);fs.closeSync(out);fs.closeSync(err);
  const live=ids.filter(alive);const received=fs.existsSync(signals)?fs.readFileSync(signals,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];
  const states={};for(const name of ['inner','outer']){const f=dir+'/'+name+'/work/build-result.json';if(fs.existsSync(f))states[name]=JSON.parse(fs.readFileSync(f));}
  const row={arm,argv,...result,identities:ids,liveBeforeCleanup:live,received,states};rows.push(row);fs.writeFileSync(dir+'/observed-before-cleanup.json',JSON.stringify(row,null,2));
 } finally {
  // Preserve observations first, then recover only exact identities created here.
  for(const id of ids.filter(alive)) {if(alive(id))process.kill(id.pid,'SIGKILL');}
  await delay(100);fs.writeFileSync(dir+'/cleanup.json',JSON.stringify({remaining:ids.filter(alive)},null,2));
 }
}
fs.writeFileSync(root+'/results.json',JSON.stringify(rows,null,2));
let failures=0;for(const r of rows){const expected=r.arm==='normal'?0:r.arm==='int'?130:143;const signalOK=r.arm==='normal'||(r.received.length>0&&r.received.every(x=>x.signal===(r.arm==='int'?'SIGINT':'SIGTERM')));const pass=r.rc===expected&&signalOK&&r.liveBeforeCleanup.length===0;console.log(JSON.stringify({arm:r.arm,rc:r.rc,expected,signalOK,live:r.liveBeforeCleanup.length,pass}));if(!pass)failures++;}process.exitCode=failures?1:0;
