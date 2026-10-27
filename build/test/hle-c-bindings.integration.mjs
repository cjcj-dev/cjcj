#!/usr/bin/env zx
// Real installed HLE -> acquired cjbind -> generated CJ -> native C -> program.
// No downloads, replacement generator, or hand-written binding declarations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [prefix,sdk,out,mode='normal']=process.argv.slice(2);
if(!prefix||!sdk||!out)throw Error('usage: hle-c-bindings.integration.mjs prefix sdk fresh-evidence [normal|failure|control]');
fs.mkdirSync(out,{recursive:true});
const caller=path.join(out,'unrelated cwd');fs.mkdirSync(caller);
const hle=path.join(prefix,'tools/bin/hle'),cjbind=path.join(prefix,'tools/dtsparser/node_modules/.bin/cjbind');
const env={...process.env,CANGJIE_HOME:sdk,PATH:'/usr/bin:/bin',LD_LIBRARY_PATH:'',LD_PRELOAD:'',LD_AUDIT:''};
const rows=[];
function run(name,argv,{compiler=false,expect=0}={}) {
 const started=new Date().toISOString(),stdout=fs.openSync(path.join(out,name+'.stdout'),'wx'),stderr=fs.openSync(path.join(out,name+'.stderr'),'wx');
 const e={...env,...(compiler?{PATH:sdk+'/bin:/usr/bin:/bin',LD_LIBRARY_PATH:sdk+'/runtime/lib/linux_x86_64_cjnative:'+sdk+'/tools/lib'}:{})};
 const r=spawnSync(argv[0],argv.slice(1),{cwd:caller,env:e,stdio:['ignore',stdout,stderr]});fs.closeSync(stdout);fs.closeSync(stderr);
 rows.push({name,argv,cwd:caller,started,ended:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message??null});fs.writeFileSync(path.join(out,'commands.json'),JSON.stringify(rows,null,2));
 assert.equal(r.signal,null,name);assert.equal(r.error,undefined,name);
 if(expect==='nonzero')assert(r.status!==0,name+' HLE_CHILD_FAILURE_TARGET');else assert.equal(r.status,expect,name);
 return fs.readFileSync(path.join(out,name+'.stdout'),'utf8');
}
const input=path.join(out,'headers');fs.mkdirSync(input);
fs.writeFileSync(path.join(input,'api.h'),'struct HlePoint { long x; long y; };\nint hle_answer(int x);\nstruct HlePoint hle_point(long x, long y);\nint *hle_pointer(void);\n');
fs.writeFileSync(path.join(input,'extra.h'),'int hle_extra(void);\n');
const generated=path.join(out,'generated');fs.mkdirSync(generated);
if(mode==='failure') {
 const bad=path.join(out,'bad');fs.mkdirSync(bad);fs.writeFileSync(path.join(bad,'broken.h'),'struct Broken { syntax ???; };\n');
 run('single-child-failure',[hle,'-c','-i',bad+'/broken.h','-o',generated,'--module-name','hle_case'],{expect:'nonzero'});
 run('directory-child-failure',[hle,'-c','-d',bad,'-o',generated,'--module-name','hle_case'],{expect:'nonzero'});
 console.log('HLE_CHILD_FAILURE_TARGET_PASS');
} else {
 run('default-bindings',[hle,'-c','-i',input+'/api.h','-o',generated,'--module-name','hle_case']);
 if(mode==='normal') {
  const explicit=path.join(out,'explicit'),directory=path.join(out,'directory');fs.mkdirSync(explicit);fs.mkdirSync(directory);
  run('explicit-bindings',[hle,'-c','-i',input+'/api.h','-o',explicit,'--module-name','hle_case','-b',cjbind]);
  assert.equal(fs.readFileSync(explicit+'/api.cj','utf8'),fs.readFileSync(generated+'/api.cj','utf8'));
  run('directory-bindings',[hle,'-c','-d',input,'-o',directory,'--module-name','hle_case']);
  for(const name of ['api.cj','extra.cj'])assert(fs.statSync(directory+'/'+name).size>0);
  run('missing-generator',[hle,'-c','-i',input+'/api.h','-o',generated,'--module-name','hle_case','-b',out+'/missing-cjbind'],{expect:'nonzero'});
 }
 fs.writeFileSync(path.join(out,'api.c'),'#include "headers/api.h"\nstatic int value=43; int hle_answer(int x){return x+1;} struct HlePoint hle_point(long x,long y){struct HlePoint p={x,y};return p;} int *hle_pointer(void){return &value;}\n');
 fs.writeFileSync(path.join(generated,'consumer.cj'),'package hle_case\nmain() {\n unsafe {\n  if (hle_answer(41) != 42) { return 41 }\n  let p = hle_point(17, 25)\n  if (p.x + p.y != 42) { return 42 }\n  if (hle_pointer().read() != 43) { return 43 }\n }\n println("HLE_REAL_C_TARGET scalar=42 struct=42 pointer=43")\n return 0\n}\n');
 run('c-compile',['cc','-c',out+'/api.c','-o',out+'/api.o']);
 run('generated-cj-compile',[sdk+'/bin/cjc','-p',generated,out+'/api.o','-o',out+'/consumer'],{compiler:true});
 const result=run('target-run',[out+'/consumer'],{compiler:true});assert.match(result,/HLE_REAL_C_TARGET scalar=42 struct=42 pointer=43/);
 console.log('HLE_REAL_C_TARGET_PASS');
}
