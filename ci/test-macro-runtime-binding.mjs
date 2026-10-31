#!/usr/bin/env zx
// Finite native ELF admission gate. The public CJ macro relocation consumer is
// separate: this does not stand in for a rebuilt compiler or a paired SDK.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [llvm,work]=process.argv.slice(2);
if(!llvm||!work)throw Error('usage: test-macro-runtime-binding.mjs LLVM_PREFIX EMPTY_PRIVATE_WORK');
fs.mkdirSync(work);const records=[];
function run(name,args,want=0){const p=spawnSync(args[0],args.slice(1),{cwd:work,encoding:'utf8',env:args[0]===path.join(work,'checker')?{...process.env,LD_LIBRARY_PATH:path.join(llvm,'lib')}:Object.fromEntries(Object.entries(process.env).filter(([key])=>!['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT'].includes(key)))});const r={name,args,rc:p.status,signal:p.signal,error:p.error?.message??null,stdout:p.stdout,stderr:p.stderr};records.push(r);fs.writeFileSync(path.join(work,'commands.json'),JSON.stringify(records,null,2));assert.equal(p.signal,null);assert.equal(p.error,undefined);assert.equal(p.status,want);return p.stdout;}
const repo=path.resolve(import.meta.dirname,'..');
fs.writeFileSync(path.join(work,'checker.cpp'),`#include "${repo}/runtime_shim/macro_runtime_binding.inc"\n#include <cstdio>\nint main(int argc,char**argv){if(argc!=3)return 64;int r=CJSelfhostCheckMacroRuntimeBinding(argv[1],argv[2]);std::printf("BINDING_REACHED %d\\n",r);return r==0?0:2;}\n`);
fs.writeFileSync(path.join(work,'macro.c'),'int macro_value(void){return 42;}\n');
for(const dir of ['sdk-a/runtime','sdk-b/runtime','relocated/runtime','relocated/macros'])fs.mkdirSync(path.join(work,dir),{recursive:true});
const checker=path.join(work,'checker');
run('compile-checker',['clang++-15','-std=c++17','-O2','-I'+path.join(llvm,'include'),path.join(work,'checker.cpp'),'-L'+path.join(llvm,'lib'),'-lLLVM-15','-o',checker]);
function build(name,flags){const output=path.join(work,name);run('link-'+name,['clang-15','-shared','-fPIC',path.join(work,'macro.c'),...flags,'-o',output]);return output;}
const a=path.join(work,'sdk-a/runtime'),b=path.join(work,'sdk-b/runtime');
const old=build('macro-old.so',['-Wl,--disable-new-dtags,-rpath,'+a]);
assert.match(run('same-sdk',[checker,old,a]),/BINDING_REACHED 0/);
assert.match(run('changed-sdk-old-still-present',[checker,old,b],2),/BINDING_REACHED -1/);
fs.renameSync(path.join(work,'sdk-a'),path.join(work,'sdk-a-hidden'));
try { assert.match(run('changed-sdk-old-hidden',[checker,old,b],2),/BINDING_REACHED -1/); }
finally { fs.renameSync(path.join(work,'sdk-a-hidden'),path.join(work,'sdk-a')); }
const relink=build('macro-relinked.so',['-Wl,--disable-new-dtags,-rpath,'+b]);
assert.match(run('normal-relink-recovery',[checker,relink,b]),/BINDING_REACHED 0/);
const runpath=build('macro-runpath.so',['-Wl,--enable-new-dtags,-rpath,'+b]);
run('runpath-refused',[checker,runpath,b],2);
const missing=build('macro-no-rpath.so',[]);run('missing-refused',[checker,missing,b],2);
const origin=build('relocated/macros/macro-origin.so',['-Wl,--disable-new-dtags,-rpath,$ORIGIN/../runtime']);
run('normal-origin',[checker,origin,path.join(work,'relocated/runtime')]);
fs.renameSync(path.join(work,'relocated'),path.join(work,'moved'));
run('moved-origin',[checker,path.join(work,'moved/macros/macro-origin.so'),path.join(work,'moved/runtime')]);
fs.writeFileSync(path.join(work,'not-elf'),'not ELF');run('malformed-refused',[checker,path.join(work,'not-elf'),b],2);
console.log('MACRO_BINDING_NATIVE_PASS cases=9; public CJ producer/load NOT_COVERED');
