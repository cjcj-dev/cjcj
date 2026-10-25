import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=process.env.NATIVE_JOB_EVIDENCE;
if(!root||!process.env.NATIVE_JOB_PYTHON||!process.env.NATIVE_JOB_SCCACHE)throw Error('NATIVE_JOB_TEST_INPUTS');
fs.mkdirSync(root,{recursive:true});
const rows=[];
function run(label,argv,env=process.env) {
 const out=fs.openSync(path.join(root,label+'.stdout'),'wx'),err=fs.openSync(path.join(root,label+'.stderr'),'wx');
 const r=spawnSync(argv[0],argv.slice(1),{cwd:root,env,stdio:['ignore',out,err],timeout:120000});
 fs.closeSync(out);fs.closeSync(err);rows.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 fs.writeFileSync(path.join(root,'commands.json'),JSON.stringify(rows,null,2));
 return {...r,stdout:fs.readFileSync(path.join(root,label+'.stdout'),'utf8'),stderr:fs.readFileSync(path.join(root,label+'.stderr'),'utf8')};
}
const entry=path.resolve('ci/bootstrap/native-cjdb-job.mjs');
let selectedEnv,config;
test('public native workflow adapter reaches existing CMake compile; finite fixture stops before installation',()=>{
 const input=root+'/input',compiler=input+'/compiler';
 for(const dir of ['compiler/cmake','dep','libedit','xml-input/xml'])fs.mkdirSync(input+'/'+dir,{recursive:true});
 fs.writeFileSync(compiler+'/cmake/linux_x86_64_toolchain.cmake','set(CMAKE_SYSTEM_NAME Linux)\n');
 fs.writeFileSync(compiler+'/entry.c','#include <stdio.h>\nint main(void){puts("NATIVE_JOB_REAL_COMPILE_REACHED");return 0;}\n');
 fs.writeFileSync(compiler+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(FiniteWorkflow C)
add_executable(entry entry.c)
add_custom_target(lldb COMMAND $<TARGET_FILE:entry> COMMAND "\${CMAKE_COMMAND}" -E false DEPENDS entry)
foreach(name cjdb lldb-boundscheck lldb-cangjie-lsp lldb-cangjie-frontend cangjie-ast-support)
 add_custom_target(\${name})
endforeach()
`);
 fs.cpSync(new URL('../../build/test/fixtures/compiler-174db8f/',import.meta.url),compiler,{recursive:true});
 fs.cpSync(new URL('../../build/test/fixtures/compiler-41b223-schema/schema',import.meta.url),compiler+'/schema',{recursive:true});
 function git(dir,label){for(const [name,args]of [['init',['init']],['add',['add','.']],['commit',['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','--allow-empty','-m','Finite workflow input']]])assert.equal(run(label+'-'+name,['git','-C',dir,...args]).status,0);return run(label+'-head',['git','-C',dir,'rev-parse','HEAD']).stdout.trim();}
 const compilerSha=git(compiler,'compiler'),dependencySha=git(input+'/dep','dependency');
 fs.writeFileSync(input+'/xml-input/xml/README','finite dependency transfer only\n');
 const archive=input+'/xml.tar.xz';assert.equal(run('xml',['tar','-cJf',archive,'-C',input+'/xml-input','xml']).status,0);
 const python=process.env.NATIVE_JOB_PYTHON,prefix=run('python',[python,'-c','import sys;print(sys.prefix)']).stdout.trim();
 config={platform:'linux_x86_64',jobs:2,linkJobs:1,compiler:'compiler',llvm:'dep',runtime:'dep',bounds:'dep',flatbuffers:'dep',libedit:'libedit',python:prefix,pythonExecutable:python,
 commits:{compiler:compilerSha,llvm:dependencySha,runtime:dependencySha,bounds:dependencySha,flatbuffers:dependencySha},
 tools:{cmake:'cmake',cc:'/usr/lib/llvm-15/bin/clang',cxx:'/usr/lib/llvm-15/bin/clang++',launcher:process.env.NATIVE_JOB_SCCACHE},
 xml2Archive:{file:'xml.tar.xz',sha256:crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex')}};
 fs.writeFileSync(input+'/native-cjdb.json',JSON.stringify(config));
 selectedEnv={...process.env,GITHUB_ACTIONS:'true',CJCJ_NATIVE_LLVM_REF:dependencySha,CJCJ_NATIVE_RUNTIME_REF:dependencySha,CJCJ_NATIVE_HOST_VERSION:'1.3.0-alpha.20261009001050',
 CJCJ_NATIVE_SOURCE_SELECTION:JSON.stringify({ast:{repository:compiler,commit:compilerSha}})};
 const r=run('public',[process.execPath,entry,'build',input,root+'/work'],selectedEnv);
 console.log('NATIVE_JOB_COMPILE_ASSERTION_REACHED');assert.equal(r.status,1,r.stderr);
 assert.match(r.stdout,/NATIVE_JOB_REAL_COMPILE_REACHED/);
 const calls=JSON.parse(fs.readFileSync(root+'/work/commands.json'));
 assert.ok(calls.some(row=>row.argv?.some(arg=>String(arg).endsWith('/native-cjdb.mjs'))));
 assert.equal(fs.existsSync(root+'/work/native-install.tar'),false,'failed native producer must not publish installation');
});
test('public native adapter rejects a different selected compiler before CMake',()=>{
 const bad={...selectedEnv,CJCJ_NATIVE_SOURCE_SELECTION:JSON.stringify({ast:{repository:'file:///wrong',commit:'f'.repeat(40)}})};
 const r=run('bad-pair',[process.execPath,entry,'build',root+'/input',root+'/bad-work'],bad);
 console.log('NATIVE_JOB_PAIR_CONTROL_REACHED');assert.equal(r.status,1);assert.match(r.stderr,/NATIVE_JOB_SOURCE_PAIR/);
 assert.equal(fs.existsSync(root+'/bad-work/native-cjdb.json'),false);
});
