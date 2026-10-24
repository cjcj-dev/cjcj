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
const source=path.join(path.dirname(fileURLToPath(import.meta.url)),'main.cj');
const cases={'raw-call':['raw-call-ctor','raw-call-mut'],'raw-invoke':['raw-invoke-ctor','raw-invoke-mut'],reference:['ref-ctor','ref-mut'],field:['field-ctor','field-mut','field-invoke'],'field-reference':['field-ref-ctor','field-ref-mut','field-ref-invoke'],unwind:['unwind-control']};
const selected=(process.env.COPYBACK_CONFIGS||'O0-plain,O0-g,O2-plain,O2-g').split(',');
assert(selected.length&&selected.every(x=>['O0-plain','O0-g','O2-plain','O2-g'].includes(x)));
const rows=[];let failed=false;
function run(name,argv,env){const prefix=path.join(output,name),stdout=fs.openSync(prefix+'.stdout','wx'),stderr=fs.openSync(prefix+'.stderr','wx');const start=new Date().toISOString();const r=spawnSync(argv[0],argv.slice(1),{env,cwd:output,stdio:['ignore',stdout,stderr]});fs.closeSync(stdout);fs.closeSync(stderr);const row={name,argv,start,end:new Date().toISOString(),pid:r.pid,rc:r.status,signal:r.signal,error:r.error?.message};rows.push(row);fs.writeFileSync(output+'/commands.json',JSON.stringify(rows,null,2));return {...row,text:fs.readFileSync(prefix+'.stdout','utf8')};}
for(const opt of ['-O0','-O2'])for(const debug of [false,true]){
 const name=opt.slice(1)+(debug?'-g':'-plain'),exe=output+'/'+name;
 if(!selected.includes(name))continue;
 const c=run(name+'-compile',[compiler,source,'-j4',opt,...(debug?['-g']:[]),'--dump-ir','--dump-to-screen','-o',exe],process.env);
 if(c.rc!==0||c.signal){failed=true;continue;}
 const env={...process.env};if(process.env.PAYLOAD_RUN_LD)env.LD_LIBRARY_PATH=process.env.PAYLOAD_RUN_LD;
 for(const [testCase,expected] of Object.entries(cases)){
 const r=run(name+'-'+testCase+'-run',[exe,testCase],env);const assertions=expected.map(test=>({test,pass:r.text.split('\n').includes('PASS '+test),fail:r.text.split('\n').includes('FAIL '+test)}));
 fs.writeFileSync(exe+'-'+testCase+'.checks.json',JSON.stringify({phase,opt,debug,rc:r.rc,signal:r.signal,assertions},null,2));
 if(r.rc!==0||r.signal||assertions.some(a=>!a.pass))failed=true;
 }
}
fs.writeFileSync(output+'/result.json',JSON.stringify({phase,pass:!failed,rows},null,2));process.exitCode=failed?1:0;
