#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const [mode,out] = process.argv.slice(2);
if(mode!=='dump'||!out)throw Error('mode/output');
fs.mkdirSync(out,{recursive:false});
const root='/mnt/cjcj-data/impl_full_sdk_sol_1108/integrated-llvm-1115';
const sdk=root+'/final/install',src=root+'/sources/interop-5985/java';
const args=['-Woff','unused','-Woff','parser','-Woff','deprecated','--import-path='+src+'/dist',
 '--output-dir='+out,'--int-overflow=wrapping','--disable-reflection','--link-options','-z relro',
 '--link-options','-z now','--target=x86_64-linux-gnu','--strip-all','-O2','--output-type=staticlib',
 '--dump-chir',...fs.readdirSync(src+'/src/interoplib/javalib').filter(x=>x.endsWith('.cj')).sort().map(x=>src+'/src/interoplib/javalib/'+x)];
const env={...process.env,CANGJIE_HOME:sdk,PATH:sdk+'/bin:/usr/local/bin:/usr/bin:/bin',TMPDIR:out};
for(const k of ['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT','CANGJIE_PATH','cjHeapSize'])delete env[k];
const record={mode,argv:[sdk+'/bin/cjc',...args],cwd:out,env,start:new Date().toISOString()};
fs.writeFileSync(out+'/command.json',JSON.stringify(record,null,2));
const stdout=fs.openSync(out+'/stdout','wx'),stderr=fs.openSync(out+'/stderr','wx');
const p=spawn(record.argv[0],args,{cwd:out,env,stdio:['ignore',stdout,stderr]});record.pid=p.pid;
Object.assign(record,await new Promise((r,j)=>{p.on('error',j);p.on('close',(rc,signal)=>r({rc,signal}));}),{end:new Date().toISOString()});
fs.closeSync(stdout);fs.closeSync(stderr);fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
console.log(JSON.stringify({rc:record.rc,signal:record.signal}));process.exitCode=record.rc??1;
