#!/usr/bin/env node
// Public tuple/Git consumer regression. Requires the real fixed runtime mirror;
// the first CMake invocation returns 86, so this never builds LLVM.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readSourcePins} from './native-llvm-inputs.mjs';
const repo=path.resolve(import.meta.dirname,'..'), options={};
for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i];if(!['--work','--runtime-mirror','--only','--skip'].includes(key)||!process.argv[i+1])throw Error('expected --work DIR --runtime-mirror GIT [--only CASE|--skip CASE]');options[key.slice(2)]=process.argv[i+1];}
assert.ok(options.work&&options['runtime-mirror'],'explicit work and runtime mirror required');
const work=path.resolve(options.work),mirror=fs.realpathSync(options['runtime-mirror']);
fs.mkdirSync(work);const records=[];
function command(argv,env=process.env,cwd=work,label='prepare'){
 const started=new Date().toISOString(),r=spawnSync(argv[0],argv.slice(1),{env,cwd,encoding:'utf8',maxBuffer:16*1024**2});
 const stem=String(records.length).padStart(3,'0')+'-'+label;
 fs.writeFileSync(path.join(work,stem+'.stdout'),r.stdout||'');fs.writeFileSync(path.join(work,stem+'.stderr'),r.stderr||'');
 records.push({label,argv,cwd,started,ended:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message});fs.writeFileSync(path.join(work,'commands.json'),JSON.stringify(records,null,2));
 assert.equal(r.error,undefined);assert.equal(r.signal,null);return r;
}
function git(...args){const r=command(['git',...args]);assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
const source=path.join(work,'other-source');fs.mkdirSync(source);
for(const [name,bytes] of Object.entries({'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h':'enum EnumReflectionType {\n ERT_NONE,\n};\n','schema/CjoFormat.fbs':'table Fixture {}\n','CMakeLists.txt':'cmake_minimum_required(VERSION 3.16)\n'})){
 const file=path.join(source,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);
}
git('init',source);git('-C',source,'add','.');git('-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: local transport input');
const other=git('-C',source,'rev-parse','HEAD'),pins=readSourcePins(),pin=pins.runtime.RUNTIME_REF,url=pins.runtime.RUNTIME_SRC_URL,privateRef='4909b2dec1af7f522133c6401e2ce960b0ef511d';
const env={...process.env};
for(const key of ['CJCJ_NATIVE_LLVM_REF','CJCJ_NATIVE_RUNTIME_REF','NATIVE_LLVM_REF','NATIVE_RUNTIME_REF','LLVM_SHA','RUNTIME_REF','CJCJ_LLVM_RUNTIME_MODE','CJCJ_LLVM_RUNTIME_URL','CJCJ_LLVM_RUNTIME_SHA','CJCJ_NATIVE_SOURCE_SELECTION'])delete env[key];
Object.assign(env,{CJCJ_NATIVE_LLVM_REF:other,CJCJ_NATIVE_RUNTIME_REF:pin,LLVM_URL:'file://'+source,
 CANGJIE_COMPILER_URL:'file://'+source,CANGJIE_COMPILER_SHA:other,FLATBUFFERS_URL:'file://'+source,FLATBUFFERS_SHA:other,
 CJCJ_SRCBUILD_SOURCE_MIRRORS:`${url}=file://${mirror};file://${source}=file://${source}`,CJCJ_SRCBUILD_REQUIRE_MIRRORS:'1',TUPLE_PLATFORM:'linux_x86_64',LLVM_TARGETS:'X86',LC_ALL:'C'});
const explicit={CJCJ_NATIVE_RUNTIME_REF:privateRef};
function run(label,script,extra={},args=[],root=path.join(work,label)){
 const selected={...env,...extra,TUPLE_ROOT:root,GIT_TRACE:path.join(work,label+'.trace')};for(const key of Object.keys(selected))if(selected[key]==null)delete selected[key];
 return command([process.env.ZX||'zx',path.join(repo,script),...args],selected,work,label);
}
function target(name,actual,expected){console.log('ASSERT_REACHED '+name);assert.deepEqual(actual,expected,name);console.log('ASSERT_PASS '+name);}
const tuple=(label,extra)=>run(label,'ci/platform_tuples/fetch_sources.mjs',extra);
function checkout(label,ref=privateRef){const dest=path.join(work,label,'paired-runtime');fs.mkdirSync(path.dirname(dest));git('init',dest);git('-C',dest,'fetch','--depth=1','file://'+mirror,ref);git('-C',dest,'checkout','--detach','FETCH_HEAD');return dest;}
function reject(label,extra,reason){const r=tuple(label,extra),trace=fs.existsSync(path.join(work,label+'.trace'))?fs.readFileSync(path.join(work,label+'.trace'),'utf8'):'';
 target(label+'_rc',r.status,1);assert.match(r.stderr+r.stdout,reason);assert.doesNotMatch(trace,/ fetch /);target(label+'_no_llvm',fs.existsSync(path.join(work,label,'llvm-project')),false);}
function build(label,dest,extra={}){const bin=path.join(work,label+'-bin'),capture=path.join(work,label+'.cmake.json');fs.mkdirSync(bin);
 fs.writeFileSync(path.join(bin,'cmake'),`#!${process.execPath}\nimport('node:fs').then(fs=>{fs.writeFileSync(${JSON.stringify(capture)},JSON.stringify(process.argv.slice(2)));process.exitCode=86;});\n`,{mode:0o755});
 return {r:run(label,'ci/platform_tuples/build_tuple.mjs',{...explicit,...extra,PATH:bin+path.delimiter+env.PATH},[],path.dirname(dest)),capture};}
const cases={
 test_default_pin(){const r=tuple('default',{RUNTIME_REF:privateRef,RUNTIME_SRC_URL:'invalid'});target('default_rc',r.status,0);target('default_head',git('-C',path.join(work,'default/paired-runtime'),'rev-parse','HEAD'),pin);target('default_clean',git('-C',path.join(work,'default/paired-runtime'),'status','--porcelain'),'');},
 test_private_selection(){target('private_rc',tuple('private',explicit).status,0);target('private_head',git('-C',path.join(work,'private/paired-runtime'),'rev-parse','HEAD'),privateRef);target('private_clean',git('-C',path.join(work,'private/paired-runtime'),'status','--porcelain'),'');},
 test_missing_sha(){reject('missing-sha',{CJCJ_NATIVE_RUNTIME_REF:null},/NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);},
 test_empty_sha(){reject('empty-sha',{CJCJ_NATIVE_RUNTIME_REF:''},/NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);},
 test_short_sha(){reject('short-sha',{CJCJ_NATIVE_RUNTIME_REF:privateRef.slice(0,12)},/NATIVE_LLVM_REF_INVALID/);},
 test_invalid_sha(){reject('invalid-sha',{CJCJ_NATIVE_RUNTIME_REF:'z'.repeat(40)},/NATIVE_LLVM_REF_INVALID/);},
 test_dirty_before_fetch(){const dest=checkout('dirty-fetch');fs.appendFileSync(path.join(dest,'runtime/src/Common/StackType.h'),'\n// controlled tracked dirt\n');reject('dirty-fetch',explicit,/checkout is dirty/);},
 test_untracked_before_fetch(){const dest=checkout('untracked-fetch');fs.writeFileSync(path.join(dest,'untracked-input'),'controlled dirt');reject('untracked-fetch',explicit,/checkout is dirty/);},
 test_nonexistent_commit(){const r=tuple('missing-commit',{CJCJ_NATIVE_RUNTIME_REF:'0'.repeat(40)});assert.notEqual(r.status,0);assert.match(fs.readFileSync(path.join(work,'missing-commit/paired-runtime/.git/HEAD'),'utf8'),/^ref:/);const trace=fs.readFileSync(path.join(work,'missing-commit.trace'),'utf8');assert.ok(!trace.includes(pin));assert.ok(trace.includes('0'.repeat(40)));},
 test_build_absolute_source(){const dest=checkout('build-source'),{r,capture}=build('build-source',dest);target('first_cmake',r.status,86);const args=JSON.parse(fs.readFileSync(capture));target('absolute_runtime',args.filter(x=>x.startsWith('-DCANGJIE_RUNTIME_SOURCE_DIR=')),['-DCANGJIE_RUNTIME_SOURCE_DIR='+fs.realpathSync(dest)]);assert.ok(args.includes('-DLLVM_ENABLE_ASSERTIONS=OFF'));},
 test_build_wrong_head(){const dest=checkout('build-wrong-head',pin),{r,capture}=build('build-wrong-head',dest);target('wrong_head_rc',r.status,1);assert.match(r.stdout+r.stderr,/HEAD differs from requested SHA/);assert.equal(fs.existsSync(capture),false);},
 test_build_dirty(){const dest=checkout('build-dirty');fs.appendFileSync(path.join(dest,'runtime/src/Common/StackType.h'),'\n// controlled dirt at consumer\n');const {r,capture}=build('build-dirty',dest);target('dirty_rc',r.status,1);assert.match(r.stdout+r.stderr,/checkout is dirty/);assert.equal(fs.existsSync(capture),false);},
 test_direct_fetch_validation(){const dest=path.join(work,'direct-runtime');const r=run('direct-invalid','ci/fetch-llvm-runtime.mjs',{CJCJ_NATIVE_RUNTIME_REF:'short'},[dest]);target('direct_invalid_rc',r.status,1);assert.equal(fs.existsSync(dest),false);}
};
// These historical environment scenarios now exercise the user's explicit
// removal contract: retired values cannot select a repository or a revision.
for(const [name,extra] of Object.entries({test_missing_url:{CJCJ_LLVM_RUNTIME_URL:null},test_unapproved_url:{CJCJ_LLVM_RUNTIME_URL:'https://gitcode.com/Cangjie/cangjie_runtime.git'},test_credential_url:{CJCJ_LLVM_RUNTIME_URL:'https://user:secret@github.com/cjcj-dev/cangjie-runtime.git'},test_implicit_private:{CJCJ_LLVM_RUNTIME_MODE:null},test_bad_mode:{CJCJ_LLVM_RUNTIME_MODE:'release'},test_mixed_ref:{RUNTIME_REF:pin},test_mixed_url:{RUNTIME_SRC_URL:'https://ignored.invalid'}}))cases[name]=()=>{
 const dest=checkout(name),r=run(name,'ci/fetch-llvm-runtime.mjs',{...explicit,CJCJ_LLVM_RUNTIME_MODE:'private',CJCJ_LLVM_RUNTIME_URL:url,CJCJ_LLVM_RUNTIME_SHA:'f'.repeat(40),...extra},['--verify-checkout',dest]);
 target(name+'_canonical_rc',r.status,0);assert.ok(r.stdout.includes('sha='+privateRef));target(name+'_unchanged_head',git('-C',dest,'rev-parse','HEAD'),privateRef);
};
const names=Object.keys(cases).filter(name=>(!options.only||name===options.only)&&name!==options.skip);assert.ok(names.length,'no selected test');
let failures=0;for(const name of names){try{cases[name]();console.log('PASS '+name);}catch(error){failures++;console.error('FAIL '+name,error.stack);}}
fs.writeFileSync(path.join(work,'result.json'),JSON.stringify({cases:names.length,failures,scope:'real source/first CMake boundary; no LLVM production'}));process.exitCode=Number(failures>0);
