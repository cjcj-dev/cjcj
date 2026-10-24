import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {nativeAstInstallation} from './native-ast-inputs.mjs';
import {verifyNativeSource} from './sdk-source.mjs';
import {command,inventory,fileDigest} from './sdk-flow.mjs';
import {createBootstrapTargets,FIXED_INPUTS} from './sdk-targets.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {spawnSync} from 'node:child_process';
const execute=promisify(execFile),fixtures=new Map();
const root=await fs.mkdtemp(path.join(process.env.AST_FACTS_EVIDENCE||os.tmpdir(),'native-ast-facts-'));
test.after(async()=>{if(!process.env.AST_FACTS_EVIDENCE)await fs.rm(root,{recursive:true,force:true});});
async function fixture(windows=false,cmakeCommand='cmake'){
 const key=windows+'|'+cmakeCommand;
 if(fixtures.has(key))return fixtures.get(key);
 const platform=windows?'windows_x86_64':'linux_x86_64',tuple=platform+'_cjnative';
 if(process.env.AST_FACTS_INPUT_ROOT){
  const directory=path.join(process.env.AST_FACTS_INPUT_ROOT,platform);
  const facts=JSON.parse(await fs.readFile(path.join(directory,'ast-facts.json'),'utf8'));
  const {source:compiler,build,install}=facts.build.originalLocations;
  const input={compiler,build,install,platform,source:facts.source,commands:JSON.parse(await fs.readFile(path.join(directory,'commands.json'),'utf8'))};
  fixtures.set(key,input);return input;
 }
 const directory=path.join(root,platform+(cmakeCommand==='cmake'?'':'-custom')),compiler=path.join(directory,'source'),build=path.join(directory,'build'),install=path.join(directory,'install');
 await fs.mkdir(compiler,{recursive:true});
 await fs.writeFile(path.join(compiler,'ast.c'),'int fixture_ast_value(void) { return 42; }\n');
 for(const name of ['StdAstFormat.fbs','StdAstFormat_generated.h','flatc'+(windows?'.exe':'')])
  await fs.writeFile(path.join(compiler,name),'Explicit CMake installation fixture; no flatc execution\n');
 await fs.writeFile(path.join(compiler,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(NativeAstInstallationFixture C)
option(CANGJIE_BUILD_STD_SUPPORT "fixture AST target" ON)
add_library(cangjie-ast-support STATIC ast.c)
set_target_properties(cangjie-ast-support PROPERTIES PREFIX "lib" SUFFIX ".a")
install(TARGETS cangjie-ast-support DESTINATION lib/${tuple})
install(FILES StdAstFormat.fbs DESTINATION schema)
install(FILES StdAstFormat_generated.h DESTINATION include/flatbuffers)
install(PROGRAMS flatc${windows?'.exe':''} DESTINATION third_party/flatbuffers/bin)
`);
 for(const args of [['init','-q'],['add','.'],['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Explicit native AST installation fixture']])await execute('git',['-C',compiler,...args]);
 const commit=(await execute('git',['-C',compiler,'rev-parse','HEAD'])).stdout.trim(),commands=[];
 const run=argv=>command(argv,{records:commands});
 const actual=await verifyNativeSource({source:compiler,commit,output:build},{command:run,inventory});
 const source={root:await fs.realpath(compiler),commit:actual};
 await run([cmakeCommand,'-G','Ninja','-S',compiler,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCANGJIE_BUILD_STD_SUPPORT=ON',
  '-DCMAKE_INSTALL_PREFIX='+install,'-DCMAKE_C_COMPILER=/usr/lib/llvm-15/bin/clang',
  ...(windows?['-DCMAKE_SYSTEM_NAME=Windows','-DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu','-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY']:[])]);
 await run([cmakeCommand,'--build',build,'--target','cangjie-ast-support']);
 await run([cmakeCommand,'--install',build]);
 const input={compiler,build,install,platform,source,commands,cmakeCommand};
 await fs.writeFile(path.join(directory,'commands.json'),JSON.stringify(commands,null,2));
 fixtures.set(key,input);return input;
}
test('actual Linux CMake AST target and installation retain relative producer bytes',async()=>{
 const input=await fixture(),facts=await nativeAstInstallation(input);
 console.log('AST_INSTALL_BYTES_ASSERT_REACHED');
 assert.equal(facts.library,'lib/linux_x86_64_cjnative/libcangjie-ast-support.a');
 assert.equal(facts.files[facts.library].sha256,await fileDigest(path.join(input.install,facts.library)));
 assert.equal(facts.source.commit,input.source.commit);
 assert.deepEqual(facts.build.commandIndexes,{configure:0,build:1,install:2});
 await fs.writeFile(path.join(path.dirname(input.build),'ast-facts.json'),JSON.stringify(facts,null,2));
});
test('Windows cross CMake fixture records native layout without flattening or claiming a Windows run',async()=>{
 const input=await fixture(true),facts=await nativeAstInstallation(input);
 assert.equal(facts.library,'lib/windows_x86_64_cjnative/libcangjie-ast-support.a');
 assert.ok(facts.files['third_party/flatbuffers/bin/flatc.exe']);
 assert.equal((await fs.stat(path.join(input.install,'libcangjie-ast-support.a')).catch(()=>null)),null);
 assert.ok(facts.files[facts.library].bytes>0);
 await fs.writeFile(path.join(path.dirname(input.build),'ast-facts.json'),JSON.stringify(facts,null,2));
});
test('stale installed library absent from actual CMake install manifest is rejected',async()=>{
 const input=await fixture(),file=path.join(input.build,'install_manifest.txt'),original=await fs.readFile(file,'utf8');
 try {await fs.writeFile(file,original.split('\n').filter(l=>!l.endsWith('libcangjie-ast-support.a')).join('\n'));
  await assert.rejects(nativeAstInstallation(input),/NATIVE_AST_NOT_INSTALLED/);
 }finally{await fs.writeFile(file,original);}
});
test('missing or failed AST build command is not a successful installed producer',async()=>{
 const input=await fixture();
 for(const commands of [input.commands.filter((_,i)=>i!==1),input.commands.map((r,i)=>i===1?{...r,rc:1}:r)])
  await assert.rejects(nativeAstInstallation({...input,commands}),/NATIVE_AST_PRODUCER_COMMANDS/);
});
test('another prefix or source cannot borrow an existing AST installation',async()=>{
 const input=await fixture();
 await assert.rejects(nativeAstInstallation({...input,install:input.install+'-other'}),/NATIVE_AST_CMAKE_CONFIGURATION/);
 await assert.rejects(nativeAstInstallation({...input,source:{...input.source,root:input.compiler+'-other'}}),/NATIVE_AST_SOURCE/);
});
test('formal native AST target checks transported originals and rechecks bytes on resume before SDK copies',async()=>{
 const input=await fixture(),ast=await nativeAstInstallation(input),llvmCommit='a'.repeat(40);
 const facts={platform:input.platform,commits:{compiler:input.source.commit,llvm:llvmCommit},
  targets:['cangjie-ast-support'],commands:input.commands,astInstallation:ast};
 const buildResult=path.join(input.install,'BUILD-INPUTS.json');await fs.writeFile(buildResult,JSON.stringify(facts));
 const row=(commit,name)=>({commit,tree:'b'.repeat(40),repository:path.join(root,name),install:path.join(root,name),
  configuration:{fixture:true},buildResult:path.join(root,name,'BUILD-INPUTS.json')});
 const runtime=row(FIXED_INPUTS.runtime,'unavailable-runtime');
 const config=createBootstrapTargets({work:path.join(root,'flow-work'),install:path.join(root,'received-sdk'),platform:input.platform,
  host:{install:path.join(root,'unavailable-host'),version:readHostToolchainPin(input.platform).replace(/^nightly-/,'')},
  llvmCommit,astCommit:input.source.commit,llvm:row(llvmCommit,'unavailable-llvm'),runtime,stdlib:{...runtime},
  ast:{...row(input.source.commit,'ast'),install:input.install,buildResult,astInstallation:ast},
  h1:row(FIXED_INPUTS.h1,'unavailable-h1'),compiler:row('c'.repeat(40),'unavailable-compiler'),tools:{privateRoot:path.join(root,'unavailable-tools')}});
 // Exercise the real generated AST target/copy subset; all unrelated compiler,
 // LLVM, runtime and language stages are explicitly outside this finite gate.
 const native=config.stages.find(stage=>stage.id==='nativeAST');
 const copies=config.stages.find(stage=>stage.id==='stage3').copies.filter(copy=>copy.owner.includes('AST')||copy.owner==='schema');
 const flow={work:config.work,install:config.install,repos:{},stages:[native,
  {id:'ast-copies',depends:['nativeAST'],output:'${install}',copies}],finalStage:'ast-copies',test:{required:Object.keys(ast.files)}};
 const file=path.join(root,'ast-flow.json');await fs.writeFile(file,JSON.stringify(flow));
 const log=[];
 async function run(label,args=[],expected=0,diagnostic){
  const argv=[new URL('./sdk-flow.mjs',import.meta.url).pathname,'--config',file,'--no-package',...args];
  const result=spawnSync(process.execPath,argv,{encoding:'utf8',maxBuffer:4*1024*1024});
  log.push({label,argv,rc:result.status,signal:result.signal,stdout:result.stdout,stderr:result.stderr});
  await fs.writeFile(path.join(root,'ast-consumer-commands.json'),JSON.stringify(log,null,2));
  console.log('AST_FORMAL_CONSUMER_ASSERT_REACHED '+label+' rc='+result.status);
  assert.equal(result.status,expected,result.stderr);if(diagnostic)assert.match(result.stderr,diagnostic);
 }
 await run('normal');
 for(const name of Object.keys(ast.files))assert.equal(await fileDigest(path.join(config.install,name)),ast.files[name].sha256);
 const moved=input.compiler+'-unavailable';await fs.rename(input.compiler,moved);
 try{
  await run('source-unavailable-resume',['--from','ast-copies']);
  const library=path.join(input.install,ast.library),original=await fs.readFile(library);
  try{await fs.appendFile(library,'changed');await run('changed-bytes-resume',['--from','ast-copies'],1,/NATIVE_AST_INSTALL_BYTES/);}
  finally{await fs.writeFile(library,original);}
  await run('restored',['--from','ast-copies']);
  for(const mutate of [value=>value.commits.compiler='0'.repeat(40)]){
   const changed=structuredClone(facts);mutate(changed);await fs.writeFile(buildResult,JSON.stringify(changed));
   await run('wrong-original',['--from','ast-copies'],1,/NATIVE_AST_SOURCE_PAIR/);
  }
 }finally{await fs.rename(moved,input.compiler);await fs.writeFile(buildResult,JSON.stringify(facts));}
 console.log('AST_FORMAL_COPY_FINITE_PASS');
});


test('actual renamed CMake installation retains selected tool identity',async()=>{
 const cmake=(await execute('sh',['-c','command -v cmake'])).stdout.trim();
 const alias=path.join(root,'cmake3');
 await fs.symlink(cmake,alias);
 const input=await fixture(false,alias),facts=await nativeAstInstallation(input);
 assert.deepEqual(facts.build.commandIndexes,{configure:0,build:1,install:2});
 await assert.rejects(nativeAstInstallation({...input,cmakeCommand:'unselected-cmake'}),/NATIVE_AST_PRODUCER_COMMANDS/);
 await assert.rejects(nativeAstInstallation({...input,commands:input.commands.map((row,i)=>i===1?{...row,rc:1}:row)}),/NATIVE_AST_PRODUCER_COMMANDS/);
 console.log('RENAMED_CMAKE_INSTALL_ASSERTION_REACHED '+alias);
});
