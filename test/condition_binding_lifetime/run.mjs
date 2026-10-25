#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const [compiler,output,phase='candidate']=process.argv.slice(2);
assert(compiler&&path.isAbsolute(compiler)&&output&&path.isAbsolute(output));
assert(['baseline','candidate','cut','restored'].includes(phase));
assert(!fs.existsSync(output));fs.mkdirSync(output,{recursive:true});
const source=path.dirname(fileURLToPath(import.meta.url)),rows=[],checks=[];
function run(name,argv,env=process.env){
 const prefix=output+'/'+name,a=fs.openSync(prefix+'.stdout','wx'),b=fs.openSync(prefix+'.stderr','wx'),start=new Date().toISOString();
 const r=spawnSync(argv[0],argv.slice(1),{cwd:output,env,stdio:['ignore',a,b]});fs.closeSync(a);fs.closeSync(b);
 const row={name,argv,start,end:new Date().toISOString(),pid:r.pid,rc:r.status,signal:r.signal,error:r.error?.message};rows.push(row);
 fs.writeFileSync(output+'/commands.json',JSON.stringify(rows,null,2));
 return {...row,out:fs.readFileSync(prefix+'.stdout','utf8'),err:fs.readFileSync(prefix+'.stderr','utf8')};
}
for(const [name,marker] of [['if-target','IF'],['while-target','WHILE'],['ordinary-control','CONTROL']]){
 const exe=output+'/'+name,c=run(name+'-compile',[compiler,source+'/'+name+'.cj','-O2','-o',exe]);
 const expectRed=(phase==='baseline'&&name!=='ordinary-control')||(phase==='cut'&&name==='if-target');
 if(expectRed){checks.push({name,pass:c.rc===1&&!c.signal&&/undeclared identifier 'tk'/.test(c.err)});continue;}
 if(c.rc!==0||c.signal){checks.push({name,pass:false});continue;}
 const env={...process.env};if(process.env.CONDITION_RUN_LD)env.LD_LIBRARY_PATH=process.env.CONDITION_RUN_LD;
 const r=run(name+'-run',[exe],env);checks.push({name,pass:r.rc===0&&!r.signal&&r.out.trim()==='CONDITION_BINDING_'+marker+'_PASS'});
}
for(const name of ['else-reject','after-if-reject','after-while-reject','self-initializer-reject']){
 const r=run(name,[compiler,source+'/'+name+'.cj','-O2','-o',output+'/'+name]);
 checks.push({name,pass:r.rc===1&&!r.signal&&/undeclared identifier 'hidden'/.test(r.err)});
}
const pass=checks.every(c=>c.pass);fs.writeFileSync(output+'/result.json',JSON.stringify({phase,pass,checks,rows},null,2));process.exitCode=pass?0:1;
