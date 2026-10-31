import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=process.env.NATIVE_TOOLS_EVIDENCE,python=process.env.NATIVE_JOBS_PYTHON;
if(!root||!python||!process.env.NATIVE_UPPERCASE_SCCACHE)throw Error('NATIVE_TOOLS_INPUTS');
await fs.mkdir(root,{recursive:true});
const calls=[];
function run(label,argv,env=process.env){
 const r=spawnSync(argv[0],argv.slice(1),{cwd:root,env,encoding:'utf8',timeout:60000,maxBuffer:4*1024**2});
 calls.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 writeFileSync(root+'/'+label+'.stdout',r.stdout||'');writeFileSync(root+'/'+label+'.stderr',r.stderr||'');
 writeFileSync(root+'/commands.json',JSON.stringify(calls,null,2));return r;
}
const producer=path.resolve('ci/bootstrap/native-cjdb.mjs');
test('public native entry accepts actual sccache with uppercase executable spelling and compiles',async()=>{
 const compiler=root+'/compiler';
 for(const dir of ['compiler/cmake','bounds','flatbuffers','llvm','runtime','libedit','xml-input/xml'])await fs.mkdir(root+'/'+dir,{recursive:true});
 await fs.writeFile(compiler+'/cmake/linux_x86_64_toolchain.cmake','set(CMAKE_SYSTEM_NAME Linux)\n');
 await fs.writeFile(compiler+'/entry.c','#include <stdio.h>\nint main(void){puts("NATIVE_TOOL_COMPILED_ENTRY_REACHED");return 0;}\n');
 await fs.writeFile(compiler+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(ToolSpelling C)
file(WRITE "\${CMAKE_BINARY_DIR}/jobs.txt" "$ENV{CMAKE_BUILD_PARALLEL_LEVEL}|\${CANGJIE_LINK_JOB_POOL}|\${CANGJIE_LLVM_BUILD_ARGS}")
add_executable(tool_entry entry.c)
add_custom_target(lldb COMMAND $<TARGET_FILE:tool_entry> COMMAND "\${CMAKE_COMMAND}" -E false DEPENDS tool_entry)
foreach(name cjdb lldb-boundscheck lldb-cangjie-lsp lldb-cangjie-frontend cangjie-ast-support)
 add_custom_target(\${name})
endforeach()
`);
 await fs.mkdir(compiler+'/third_party/cmake',{recursive:true});await fs.mkdir(compiler+'/src',{recursive:true});
 await fs.copyFile(new URL('../../build/test/fixtures/compiler-41b223-cjdb/BuildCJDB.cmake',import.meta.url),compiler+'/third_party/cmake/BuildCJDB.cmake');
 await fs.writeFile(compiler+'/src/CMakeLists.txt','if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\nendif()\n');
 await fs.copyFile(new URL('../../build/test/fixtures/compiler-174db8f/third_party/CMakeLists.txt',import.meta.url),compiler+'/third_party/CMakeLists.txt');
 await fs.cp(new URL('../../build/test/fixtures/compiler-41b223-schema/schema',import.meta.url),compiler+'/schema',{recursive:true});
 for(const [name,args]of [['init',['init']],['add',['add','.']],['commit',['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','Finite native tool path fixture']]])
  assert.equal(run(name,['git','-C',compiler,...args]).status,0);
 const commit=run('head',['git','-C',compiler,'rev-parse','HEAD']).stdout.trim();
 const launcher=process.env.NATIVE_UPPERCASE_SCCACHE;
 await fs.writeFile(root+'/xml-input/xml/README','not libxml production\n');
 const archive=root+'/xml.tar.xz';assert.equal(run('archive',['tar','-cJf',archive,'-C',root+'/xml-input','xml']).status,0);
 const prefix=run('python',[python,'-c','import sys;print(sys.prefix)']).stdout.trim();
 const jobs=os.availableParallelism()+1;
 const linkJobs=jobs+1;
 const config={jobs,linkJobs,compiler,llvm:root+'/llvm',runtime:root+'/runtime',bounds:root+'/bounds',flatbuffers:root+'/flatbuffers',libedit:root+'/libedit',python:prefix,pythonExecutable:python,
  build:root+'/build',install:root+'/install',commits:{compiler:commit,llvm:commit},tools:{cmake:'cmake',cc:'/usr/lib/llvm-15/bin/clang',cxx:'/usr/lib/llvm-15/bin/clang++',launcher},
  xml2Archive:{file:archive,sha256:crypto.createHash('sha256').update(await fs.readFile(archive)).digest('hex')}};
 const file=root+'/config.json';await fs.writeFile(file,JSON.stringify(config));
 const r=run('public',[process.execPath,producer,file],{...process.env,GITHUB_ACTIONS:'true'});
 console.log('NATIVE_TOOL_CASE_ASSERTION_REACHED');assert.equal(r.status,1);
 assert.match(r.stdout,/NATIVE_TOOL_COMPILED_ENTRY_REACHED/);
 const observed=await fs.readFile(config.build+'/jobs.txt','utf8');
 assert.ok(observed.startsWith(jobs+'|'+linkJobs+'|'),observed);
 assert.ok(observed.includes('-DLLVM_PARALLEL_LINK_JOBS='+linkJobs),observed);
 const events=r.stdout.split('\n').filter(line=>line.startsWith('{"event":')).map(line=>JSON.parse(line));
 const command=events.find(event=>event.event==='target-command'&&event.argv[1]==='--build');
 assert.ok(command,'actual CMake build must execute');
 assert.deepEqual(command.argv.slice(-2),['-j',String(jobs)]);
 console.log('NATIVE_EXPLICIT_JOBS_ASSERTION_REACHED '+jobs+' CPUs='+os.availableParallelism());assert.doesNotMatch(r.stderr,/GHA_SCCACHE_REQUIRED/);
});
test('public GHA entry still rejects a non-sccache launcher',async()=>{
 const file=root+'/wrong-tool.json';await fs.writeFile(file,JSON.stringify({jobs:1,tools:{launcher:'/explicit/ccache'}}));
 const r=run('wrong-tool',[process.execPath,producer,file],{...process.env,GITHUB_ACTIONS:'true'});
 assert.equal(r.status,1);assert.match(r.stderr,/GHA_SCCACHE_REQUIRED/);
});
