#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {$} from 'zx';
const [compiler,sdk,fixtures,checker,bounds,output]=process.argv.slice(2);
if(!output)throw Error('public-cjc sdk fixtures abi-checker bounds-checker output required');
fs.mkdirSync(output);
const env={...process.env,CANGJIE_HOME:sdk,PATH:sdk+'/bin:/usr/local/bin:/usr/bin:/bin',
 LD_LIBRARY_PATH:sdk+'/runtime/lib/linux_x86_64_cjnative:'+sdk+'/third_party/llvm/lib',LD_DEBUG:'libs'};
const records=[];
async function step(name,argv){const start=new Date().toISOString();const r=await $({cwd:output,env,nothrow:true,quiet:true,timeout:300000})`${argv}`;
 fs.writeFileSync(output+'/'+name+'.stdout',r.stdout);fs.writeFileSync(output+'/'+name+'.stderr',r.stderr);
 records.push({name,argv,start,end:new Date().toISOString(),rc:r.exitCode,signal:r.signal});fs.writeFileSync(output+'/results.json',JSON.stringify(records,null,2));console.log(name+' rc='+r.exitCode);return r.exitCode;}
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.writeFileSync(output+'/inputs.json',JSON.stringify({compiler,sdk,fixtures,checker,bounds,compilerSha256:hash(sdk+'/libexec/compiler/cjcj-stage1'),checkerSha256:hash(checker),
 target:'aarch64-unknown-linux-gnu',semanticImports:sdk+'/modules/linux_x86_64_cjnative',nativeExecution:'NOT_RUN'},null,2));
const c=await step('c-cross',['/usr/bin/clang','--target=aarch64-unknown-linux-gnu','-std=gnu11','-O0','-c',fixtures+'/hfa.c','-o',output+'/c.o']);
const oracle=await step('c-oracle',['/usr/bin/clang','--target=aarch64-unknown-linux-gnu','-std=gnu11','-O0','-emit-llvm','-S',fixtures+'/hfa.c','-o',output+'/c.ll']);
const cj=await step('cj-cross',[compiler,fixtures+'/hfa.cj','--experimental','--target=aarch64-unknown-linux-gnu','--import-path',sdk+'/modules/linux_x86_64_cjnative',
 '--output-type=obj','--compile-target','staticlib','-O0','--verbose','--apc-split-num=1','--save-temps='+output,'-o',output+'/cj.o']);
if(c||oracle||cj)process.exit(1);
for(const file of ['c.o','cj.o']){const elf=fs.readFileSync(output+'/'+file);if(elf.readUInt32BE(0)!==0x7f454c46||elf[5]!==1||elf.readUInt16LE(18)!==183)throw Error('not AArch64 ELF '+file);}
let failed=false;
for(const group of ['target','control'])if(await step(group+'-abi',[checker,output+'/c.ll',output+'/hfa.opt.bc',fixtures+'/'+group+'.txt']))failed=true;
for(const [name,prefix] of [['return','cj_ret_'],['incoming','cj_echo_'],['outgoing','cj_call_'],['values','cj_values_']])
 if(await step(name+'-bounds',[bounds,output+'/hfa.opt.bc',prefix]))failed=true;
process.exitCode=failed?1:0;
