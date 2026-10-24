#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const input=process.env.CAPI_RESOURCE_REQUEST,evidence=process.env.CAPI_RESOURCE_EVIDENCE;
if(!input||!evidence)throw Error('CAPI_RESOURCE_REQUEST and CAPI_RESOURCE_EVIDENCE required');
const base=JSON.parse(await fs.readFile(input,'utf8'));
await fs.mkdir(evidence,{recursive:true});
const root=await fs.mkdtemp(path.join(evidence,'capi-resources-'));
const product=path.resolve(import.meta.dirname,'sdk-native-input-check.mjs');
const wrapper=path.join(root,'cmake-observe.mjs'),trace=path.join(root,'cmake-argv.jsonl');
await fs.writeFile(wrapper,'#!'+process.execPath+'\n'+
 "import fs from 'node:fs';import {spawnSync} from 'node:child_process';\n"+
 'const args=process.argv.slice(2);fs.appendFileSync('+JSON.stringify(trace)+',JSON.stringify(args)+"\\n");\n'+
 'const r=spawnSync('+JSON.stringify(base.tools.cmake.path)+',args,{stdio:"inherit"});process.exit(r.status??1);\n',{mode:0o755});
const wrapperSha=crypto.createHash('sha256').update(await fs.readFile(wrapper)).digest('hex');
const env={...process.env,CMAKE_BUILD_PARALLEL_LEVEL:'1'};
for(const key of ['CANGJIE_BUILD_JOBS','KKK2_JOBS'])delete env[key];
const records=[];
async function run(label,changes={}) {
 const request={...base,work:path.join(root,label),tools:{...base.tools,cmake:{path:wrapper,sha256:wrapperSha}},...changes};
 const argv=[product,JSON.stringify(request)],log=await fs.open(path.join(root,label+'.log'),'w');
 let r;try{r=spawnSync(process.execPath,argv,{env,stdio:['ignore',log.fd,log.fd],timeout:120000});}finally{await log.close();}
 records.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 await fs.writeFile(path.join(root,'commands.json'),JSON.stringify(records,null,2));
 assert.ifError(r.error);assert.equal(r.signal,null);
 return {...r,text:await fs.readFile(path.join(root,label+'.log'),'utf8')};
}
test('formal native input checker carries parent jobs to actual CMake and N C API',async()=>{
 const r=await run('parent-jobs');
 console.log('FORMAL_N_CAPI_RESULT '+JSON.stringify({root,rc:r.status}));
 assert.match(r.text,/LLVM_NATIVE_CAPI_VERIFIED/,'real library C API must execute');
 const calls=(await fs.readFile(trace,'utf8')).trim().split('\n').map(JSON.parse);
 const build=calls.find(argv=>argv.includes('--build'));
 assert.ok(build);assert.equal(build[build.indexOf('--parallel')+1],'1');
 assert.equal(r.status,0,r.text);
});
test('formal native input checker preserves original N bad-byte rejection',async()=>{
 const r=await run('bad-bytes',{librarySha256:'0'.repeat(64)});
 assert.equal(r.status,1);assert.match(r.text,/LLVM_DYLIB_SHA256_MISMATCH/);
 assert.doesNotMatch(r.text,/LLVM_NATIVE_CAPI_VERIFIED/);
});
