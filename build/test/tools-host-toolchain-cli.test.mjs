#!/usr/bin/env zx
// Formal tools CLI, real read-only official H, bounded CMake C++ consumers.
// This tests upper entry/configuration, not cjlint's Cangjie AST ABI.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';
import {toolBuildInputs} from '../srcbuild/tool-build-inputs.mjs';
const host=process.env.CJCJ_TOOLS_TEST_HOST,base=process.env.RELEASE_EVIDENCE_TEST_ROOT;
function fixture(name) {
  assert(host&&base,'CJCJ_TOOLS_TEST_HOST and RELEASE_EVIDENCE_TEST_ROOT required');
  assert(!fs.existsSync(path.join(host,'STAGE-INPUTS.json')),'use an unmodified official SDK');
  const root=fs.mkdtempSync(path.join(base,'tools-'+name+'-')),workspace=path.join(root,'workspace');
  const tools=path.join(workspace,'cangjie_tools'),deps=path.join(root,'json'),records=[];
  const write=(p,s)=>{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,s);};
  function run(argv,options={}) {
    const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:8*1024*1024,...options});
    records.push({argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
    write(path.join(root,'commands.json'),JSON.stringify(records,null,2));return r;
  }
  const ok=r=>{assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r;};
  function freeze(dir) {
    ok(run(['git','init',dir]));ok(run(['git','-C',dir,'add','.']));
    ok(run(['git','-C',dir,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: finite native CLI consumer']));
    ok(run(['git','-C',dir,'remote','add','origin','file://'+dir]));
    return ok(run(['git','-C',dir,'rev-parse','HEAD'])).stdout.trim();
  }
  write(path.join(deps,'include/nlohmann/json.hpp'),'// explicit bounded dependency fixture\n');
  const depCommit=freeze(deps);
  write(path.join(root,'dependencies.json'),JSON.stringify({json:{repo:'file://'+deps,commit:depCommit,path:deps}}));
  write(path.join(tools,'.gitignore'),'**/build/build/\n**/output/\n');
  write(path.join(tools,'cjpm/build/build.py'),'# fixed selector overlay, not executed\n');
  for(const [directory,binary]of [['cjlint','cjlint'],['cangjie-language-server','LSPServer']]) {
    write(path.join(tools,directory,'main.cpp'),'#include <optional>\n#include <cstdio>\nint main(){std::optional<int> n=42; printf("%d\\n",*n);}\n');
    write(path.join(tools,directory,'lib.cpp'),'int bounded_native_consumer(){return 42;}\n');
    write(path.join(tools,directory,'config/rules.json'),'{}\n');
    write(path.join(tools,directory,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(tools_cli_fixture CXX)
set(GCC_TOOLCHAIN_FLAG "" CACHE PATH "selected native GCC prefix")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(GCC_TOOLCHAIN_FLAG)
 add_compile_options("--gcc-toolchain=\${GCC_TOOLCHAIN_FLAG}")
 add_link_options("--gcc-toolchain=\${GCC_TOOLCHAIN_FLAG}")
endif()
add_executable(${binary} main.cpp)
set_target_properties(${binary} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "\${CMAKE_BINARY_DIR}/bin")
add_library(native SHARED lib.cpp)
set_target_properties(native PROPERTIES OUTPUT_NAME cjlint LIBRARY_OUTPUT_DIRECTORY "\${CMAKE_BINARY_DIR}/lib")
`);
    write(path.join(tools,directory,'build/build.py'),`import os,pathlib,subprocess,sys,shutil
root=pathlib.Path(__file__).resolve().parents[1]
build=root/'build/build'
def run(args): subprocess.run(args,check=True)
if sys.argv[1]=='clean':
 if build.exists(): shutil.rmtree(build)
elif sys.argv[1]=='build':
 # Exercise the actual selected host executable as well as the native compiler.
 run([str(pathlib.Path(os.environ['CANGJIE_HOME'])/'bin/cjc'),'--version'])
 gcc=sys.argv[sys.argv.index('--gcc-toolchain')+1] if '--gcc-toolchain' in sys.argv else ''
 run(['cmake','-S',str(root),'-B',str(build),'-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DGCC_TOOLCHAIN_FLAG='+gcc])
 run(['cmake','--build',str(build),'--parallel',sys.argv[sys.argv.index('--jobs')+1]])
 if root.name=='cangjie-language-server':
  out=root/'output/bin/LSPServer';out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(build/'bin/LSPServer',out)
else: raise RuntimeError('unexpected phase')
`);
  }
  const commit=freeze(tools);
  write(path.join(workspace,'.source-selection.json'),JSON.stringify({tools:{url:'file://'+tools,tag:commit},cjpm:{url:'file://'+tools,tag:commit}}));
  const env={...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:host,CJCJ_SRCBUILD_HOST_SDK:host};
  for(const key of ['CANGJIE_BUILD_DRY_RUN','CJCJ_TOOLS_GCC_TOOLCHAIN','CJCJ_SRCBUILD_SOURCE_MIRRORS','CJCJ_SRCBUILD_REQUIRE_MIRRORS'])delete env[key];
  function build(tool,extra=[]) {
    return run([process.execPath,new URL('../cli.mjs',import.meta.url).pathname,'--workspace',workspace,
      '--build-root',path.join(root,'buildtools'),'--official-sdk-root',host,'--host-profile','kkk2',
      '--target','linux-x64','--build-type','release','--tools-phase','build','--tools-build-set',tool,
      '--tools-dependencies',path.join(root,'dependencies.json'),'--jobs','1',...extra,'build','tools'],{env});
  }
  const facts=tool=>JSON.parse(fs.readFileSync(path.join(workspace,'build/tools',tool,'build-inputs.json')));
  return {root,workspace,tools,write,run,ok,build,facts,host};
}
test('official H reaches the public tools producer without a synthetic stage record',()=>{
  const f=fixture('host');f.ok(f.build('lsp'));
  const facts=f.facts('lsp');
  console.log('OFFICIAL_H_PRODUCER_FACTS_ASSERTION_REACHED');
  assert.equal(facts.build.inputs.stage,undefined);
  assert.equal(facts.build.inputs.artifacts.compiler.sdkRelative,'bin/cjc');
  assert.equal(facts.build.rc,0);
  assert.equal(f.ok(f.run([facts.artifact.path])).stdout.trim(),'42');
  assert(!fs.existsSync(path.join(host,'STAGE-INPUTS.json')));
});
test('public cjlint GCC selection survives cold, warm, withdrawal and restoration',async()=>{
  const f=fixture('gcc'),prefix='/usr';
  f.ok(f.build('cjlint',['--tools-gcc-toolchain',prefix]));
  function selected(expected) {
    const facts=f.facts('cjlint');
    console.log('TOOLS_GCC_CONSUMER_ASSERTION_REACHED '+JSON.stringify({expected}));
    assert.equal(facts.build.nativeConfiguration.native.values.GCC_TOOLCHAIN_FLAG,expected);
    assert.equal(f.ok(f.run([facts.artifact.path])).stdout.trim(),'42');
    const commands=JSON.parse(fs.readFileSync(path.join(f.tools,'cjlint/build/build/compile_commands.json')));
    for(const row of commands)assert.equal(row.command.includes('--gcc-toolchain='+prefix),expected===prefix);
    return facts;
  }
  selected(prefix);
  f.ok(f.build('cjlint',['--tools-build-mode','incremental','--tools-gcc-toolchain',prefix]));selected(prefix);
  f.ok(f.build('cjlint',['--tools-build-mode','incremental']));selected('');
  f.ok(f.build('cjlint',['--tools-build-mode','incremental','--tools-gcc-toolchain',prefix]));
  const facts=selected(prefix),config=buildConfig({workspace:f.workspace,targetKey:'linux-x64',buildType:'release'});
  const cache=path.join(f.tools,'cjlint/build/build/CMakeCache.txt'),original=fs.readFileSync(cache,'utf8');
  f.write(cache,original.replace('GCC_TOOLCHAIN_FLAG:PATH=/usr','GCC_TOOLCHAIN_FLAG:PATH=/other'));
  await assert.rejects(toolBuildInputs(config,'cjlint',facts.artifact.path),/TOOL_BUILD_CONFIGURATION_CHANGED/);
  f.write(cache,original);await toolBuildInputs(config,'cjlint',facts.artifact.path);
  const relative=f.build('cjlint',['--tools-gcc-toolchain','relative']);assert.equal(relative.status,2);assert.match(relative.stderr,/absolute GCC/);
  const cross=f.build('cjlint',['--target','windows-x64','--tools-gcc-toolchain',prefix]);assert.equal(cross.status,2);assert.match(cross.stderr,/native Linux cjlint/);
});
