#!/usr/bin/env zx
// Fixed-input build/installation regression; does not run performance samples.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [mode,root]=process.argv.slice(2);
if(!['default','development','tests'].includes(mode)||!path.isAbsolute(root||''))throw Error('mode absolute-new-output');
const source=path.resolve(import.meta.dirname,'../..');
const commit=spawnSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim();
fs.mkdirSync(root,{recursive:true});
const rows=[];
const cg='/sys/fs/cgroup'+fs.readFileSync('/proc/self/cgroup','utf8').trim().split('::').at(-1);
const resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,fs.readFileSync(cg+'/'+k,'utf8').trim()]));
const limits=fs.readFileSync('/proc/self/limits','utf8');
fs.writeFileSync(root+'/input.json',JSON.stringify({mode,commit,source,resources,limits},null,2),{flag:'wx'});
if(resources['memory.swap.max']!=='0'||!limits.match(/Max core file size\s+0\s+0/))throw Error('RESOURCE_CONTRACT');
const run=(tag,args)=>{
 const row={tag,argv:[process.execPath,...args],cwd:source,start:new Date().toISOString()};rows.push(row);
 const save=()=>fs.writeFileSync(root+'/commands.json',JSON.stringify(rows,null,2));save();
 const out=fs.openSync(root+'/'+tag+'.stdout','wx'),err=fs.openSync(root+'/'+tag+'.stderr','wx');
 const result=spawnSync(process.execPath,args,{cwd:source,env:{...process.env,HOME:'/root',RELEASE_EVIDENCE_TEST_ROOT:root},stdio:['ignore',out,err]});
 fs.closeSync(out);fs.closeSync(err);Object.assign(row,{rc:result.status,signal:result.signal,error:result.error?.message,end:new Date().toISOString()});save();
 if(result.status!==0)process.exit(result.status??1);
};
if(mode==='tests') {
 run('tests',['--test','ci/bootstrap/compiler-option-visibility.test.mjs','ci/bootstrap/sdk-targets.test.mjs','ci/bootstrap/sdk-stage2-input.test.mjs']);
} else {
 run('h1',[source+'/ci/bootstrap/sdk-native-stage.mjs','--kind','h1','--source',source,'--commit',commit,
  '--sdk','/root/opus_std_size_1114/outdbg/native-components','--host','/root/opus_std_size_1114/outdbg/host-sdk',
  '--output',root+'/h1','--platform','linux_x86_64','--jobs','32','--heap','32GB','--visible-options-only',String(mode==='default')]);
}
