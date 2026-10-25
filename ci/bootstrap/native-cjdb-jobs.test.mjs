import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=process.env.NATIVE_JOBS_EVIDENCE;
if(!root)throw Error('NATIVE_JOBS_EVIDENCE_REQUIRED');
await fs.mkdir(root,{recursive:true});
const calls=[];
function run(label,argv,{cwd=root,env=process.env}={}){
 const started=new Date().toISOString();
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env,encoding:'utf8',timeout:60000,maxBuffer:8*1024**2});
 calls.push({label,argv,cwd,started,ended:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message});
 fsSyncWrite(label,r);return r;
}
import {writeFileSync} from 'node:fs';
function fsSyncWrite(label,r){
 writeFileSync(root+'/'+label+'.stdout',r.stdout||'');writeFileSync(root+'/'+label+'.stderr',r.stderr||'');
 writeFileSync(root+'/commands.json',JSON.stringify(calls,null,2));
}
const good=(label,argv,opts)=>{const r=run(label,argv,opts);assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
const producer=path.resolve('ci/bootstrap/native-cjdb.mjs');
const launcher=process.env.NATIVE_JOBS_SCCACHE;
if(!launcher)throw Error('NATIVE_JOBS_SCCACHE_REQUIRED');
const env={...process.env,GITHUB_ACTIONS:'false',CMAKE_BUILD_PARALLEL_LEVEL:'99',
 SCCACHE_SERVER_PORT:'42319',SCCACHE_IDLE_TIMEOUT:'60',SCCACHE_CACHE_SIZE:'8M'};
const python=process.env.NATIVE_JOBS_PYTHON||'/usr/bin/python3.11';
test('four CPU public native producer reaches real CMake configure and compiled target with default and explicit jobs',async()=>{
 assert.equal(os.availableParallelism(),4,'execute this finite entry gate in a real four-CPU domain');
 const source=root+'/compiler',dep=root+'/dependencies';
 for(const rel of ['compiler/cmake','dependencies/bounds','dependencies/flatbuffers','dependencies/llvm','dependencies/runtime','dependencies/libedit','xml-input/xml2'])
  await fs.mkdir(root+'/'+rel,{recursive:true});
 await fs.writeFile(source+'/cmake/linux_x86_64_toolchain.cmake','set(CMAKE_SYSTEM_NAME Linux)\n');
 await fs.writeFile(source+'/entry.c','#include <stdio.h>\n#include <stdlib.h>\nint main(void){const char *j=getenv("CMAKE_BUILD_PARALLEL_LEVEL");printf("NATIVE_JOBS_BUILD_REACHED jobs=%s\\n",j?j:"unset");return j?0:9;}\n');
 await fs.writeFile(source+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(NativeJobsEntry C)
file(WRITE "\${CMAKE_BINARY_DIR}/jobs-observed.txt" "$ENV{CMAKE_BUILD_PARALLEL_LEVEL}|\${CANGJIE_LINK_JOB_POOL}|\${CANGJIE_LLVM_BUILD_ARGS}")
message(STATUS "NATIVE_JOBS_CONFIGURE_REACHED")
add_executable(native_jobs_entry entry.c)
# Compile and execute a real C target, then stop this finite gate before any
# native AST/Python-LLDB installation could be represented as complete.
add_custom_target(lldb COMMAND $<TARGET_FILE:native_jobs_entry>
 COMMAND "\${CMAKE_COMMAND}" -E false DEPENDS native_jobs_entry)
foreach(name cjdb lldb-boundscheck lldb-cangjie-lsp lldb-cangjie-frontend cangjie-ast-support)
 add_custom_target(\${name})
endforeach()
`);
 await fs.mkdir(source+'/third_party/cmake',{recursive:true});await fs.mkdir(source+'/src',{recursive:true});
 await fs.writeFile(source+'/third_party/cmake/BuildCJDB.cmake','externalproject_get_property(cjnative BINARY_DIR)\nset(LLVM_GC_BINARY_DIR "${BINARY_DIR}")\n    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative)\n');
 await fs.writeFile(source+'/src/CMakeLists.txt','if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\nendif()\n');
 good('git-init',['git','init',source]);good('git-add',['git','-C',source,'add','.']);
 good('git-commit',['git','-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','Finite native jobs entry']);
 const commit=good('git-head',['git','-C',source,'rev-parse','HEAD']);
 await fs.writeFile(root+'/xml-input/xml2/README','Explicit small dependency unpack input; not libxml2 production.\n');
 const archive=root+'/xml2.tar.xz';good('xml-archive',['tar','-cJf',archive,'-C',root+'/xml-input','xml2']);
 const pythonRoot=good('python-prefix',[python,'-c','import sys;print(sys.prefix)']);
 for(const [label,selection,expected]of [['default',{},[4,4]],['explicit',{jobs:2,linkJobs:1},[2,1]]]){
  const config={...selection,compiler:source,llvm:dep+'/llvm',runtime:dep+'/runtime',bounds:dep+'/bounds',flatbuffers:dep+'/flatbuffers',
   python:pythonRoot,pythonExecutable:python,libedit:dep+'/libedit',platform:'linux_x86_64',build:root+'/'+label+'-build',install:root+'/'+label+'-install',
   commits:{compiler:commit,llvm:commit},tools:{cmake:'cmake',cc:'/usr/lib/llvm-15/bin/clang',cxx:'/usr/lib/llvm-15/bin/clang++',launcher},
   xml2Archive:{file:archive,sha256:crypto.createHash('sha256').update(await fs.readFile(archive)).digest('hex')}};
  const file=root+'/'+label+'.json';await fs.writeFile(file,JSON.stringify(config));
  const r=run(label+'-public',[process.execPath,producer,file],{env});
  console.log('NATIVE_JOBS_ENTRY_ASSERTION_REACHED '+label+' actualCpus='+os.availableParallelism());
  assert.equal(r.status,1,'finite target intentionally stops after real C execution');
  assert.match(r.stdout,/NATIVE_JOBS_CONFIGURE_REACHED/);
  assert.match(r.stdout,new RegExp('NATIVE_JOBS_BUILD_REACHED jobs='+expected[0]));
  const events=r.stdout.split('\n').filter(line=>line.startsWith('{"event":')).map(line=>JSON.parse(line));
  const buildCommand=events.find(event=>event.event==='target-command'&&event.argv[1]==='--build');
  assert.ok(buildCommand,'public producer invoked the actual CMake build');
  assert.deepEqual(buildCommand.argv.slice(-2),['-j',String(expected[0])]);
  const observed=await fs.readFile(config.build+'/jobs-observed.txt','utf8');
  assert.ok(observed.startsWith(expected.join('|')+'|'),observed);
  assert.ok(observed.includes('-DLLVM_PARALLEL_LINK_JOBS='+expected[1]),observed);
  assert.doesNotMatch(r.stderr,/NATIVE_CPUS/);
 }
});
test('public native jobs rejects invalid capacity before creating a build directory',async()=>{
 for(const [label,selection,error]of [['zero',{jobs:0},'NATIVE_JOBS'],
  ['fraction',{jobs:1.5},'NATIVE_JOBS'],['link-zero',{jobs:2,linkJobs:0},'NATIVE_LINK_JOBS']]){
  const build=root+'/'+label+'-must-not-exist',file=root+'/'+label+'.json';
  await fs.writeFile(file,JSON.stringify({...selection,build,tools:{launcher}}));
  const r=run(label+'-public',[process.execPath,producer,file],{env});
  assert.equal(r.status,1);assert.match(r.stderr,new RegExp(error));assert.equal(await fs.stat(build).catch(()=>null),null);
 }
});
test('public native producer retains host identity rejection on a legal small CPU domain',async()=>{
 const file=root+'/wrong-host.json';await fs.writeFile(file,JSON.stringify({jobs:2,platform:'windows_x86_64',tools:{launcher}}));
 const r=run('wrong-host-public',[process.execPath,producer,file],{env});
 assert.equal(r.status,1);assert.match(r.stderr,/NATIVE_CJDB_RUNNER_REQUIRED/);
});
