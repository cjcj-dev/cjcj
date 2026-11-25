#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {assertCjnativeHostArgs} from '../../build/test/fixtures/windows-cjnative-args.mjs';
import {assertCompilerLibcxxEdits} from '../../build/test/fixtures/windows-compiler-libcxx.mjs';
import {cmakePath,coffImports,requireMsvcrtImports,selectedExecutable,selectedWindowsToolchainEnvironment,windowsInstalledEnvironment} from './native-windows-toolchain.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const out=process.env.TOOLCHAIN_TEST_EVIDENCE;
if(!out)throw Error('TOOLCHAIN_TEST_EVIDENCE required');
await fs.mkdir(out,{recursive:true});
test('actual official x64 runtime PE imports retain the MSVCRT runtime family',async()=>{
 const directory=process.env.TOOLCHAIN_DLL_DIRECTORY;
 assert.ok(directory);
 const rows=[];
 for(const name of (await fs.readdir(directory)).filter(n=>n.endsWith('.dll')).sort()){
  assert.ok(process.env.LLVM_READOBJ,'LLVM_READOBJ must select an existing host reader');
  const argv=[process.env.LLVM_READOBJ,'--coff-imports',path.join(directory,name)];
  const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8'});
  await fs.writeFile(path.join(out,name+'.imports'),(r.stdout||'')+(r.stderr||''));
  rows.push({argv,rc:r.status,signal:r.signal,error:r.error?.message});
  await fs.writeFile(out+'/pe-commands.json',JSON.stringify(rows,null,2));
  assert.equal(r.status,0,r.stderr);
  const imports=coffImports(r.stdout);requireMsvcrtImports(imports);
  assert.ok(imports.includes('msvcrt.dll'),name+': '+imports);
 }
 assert.ok(rows.length>0);
});
test('CRT rejection has UCRT and GCC positive controls, not an always-green parser',()=>{
 assert.deepEqual(coffImports('Import {\n  Name: MSVCRT.dll\n}\n'),['msvcrt.dll']);
 requireMsvcrtImports(['msvcrt.dll','kernel32.dll'],{executable:true});
 for(const name of ['ucrtbase.dll','api-ms-win-crt-heap-l1-1-0.dll','libstdc++-6.dll','libgcc_s_seh-1.dll'])
  assert.throws(()=>requireMsvcrtImports(['msvcrt.dll',name]),/WINDOWS_TOOLCHAIN_CRT/);
 assert.throws(()=>requireMsvcrtImports([]),/WINDOWS_TOOLCHAIN_CRT/);
 assert.throws(()=>requireMsvcrtImports(['kernel32.dll'],{executable:true}),/WINDOWS_TOOLCHAIN_CRT/);
});
test('compiler selection resolves the real selected path without an invented compiler identity',async()=>{
 const selected=await selectedExecutable(process.execPath);
 assert.equal(selected,await fs.realpath(process.execPath));
 await assert.rejects(selectedExecutable('not-a-compiler-1020',{PATH:out}),/WINDOWS_COMPILER_MISSING/);
});
test('installed consumer PATH excludes the producer toolchain and source build paths',()=>{
 const result=windowsInstalledEnvironment({SystemRoot:'C:/Windows',PATH:'C:/toolchain/bin;C:/build/bin'},'C:/N');
 assert.deepEqual(result.PATH.split(';'),[path.join('C:/N','bin'),path.join('C:/N','third_party/llvm/bin'),path.join('C:/Windows','System32'),'C:/Windows']);
});
test('selected Windows toolchain bin precedes ambient MSYS2 and host LLVM tools',()=>{
 const result=selectedWindowsToolchainEnvironment({PATH:'D:\\msys64\\mingw64\\bin;C:\\Program Files\\LLVM\\bin'},'D:\\selected\\llvm-mingw\\bin');
 assert.equal(result.PATH,'D:\\selected\\llvm-mingw\\bin;D:\\msys64\\mingw64\\bin;C:\\Program Files\\LLVM\\bin');
});
test('public probe CLI rejects a non-Windows host before producing any success record',async t=>{
 if(process.platform==='win32'){t.skip('this is the non-Windows control');return;}
 const config=out+'/probe.json';await fs.writeFile(config,JSON.stringify({platform:'windows_x86_64',jobs:1,tools:{},work:out+'/forbidden-work'}));
 const argv=[process.execPath,path.join(here,'native-windows-toolchain.mjs'),config];
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8'});
 await fs.writeFile(out+'/public-probe.json',JSON.stringify({argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr},null,2));
 assert.equal(r.status,1);assert.match(r.stderr,/WINDOWS_TOOLCHAIN_NATIVE_REQUIRED/);
 assert.equal(await fs.stat(out+'/forbidden-work').then(()=>true,()=>false),false);
 const producerArgv=[process.execPath,path.join(here,'native-cjdb.mjs'),config];
 const producer=spawnSync(producerArgv[0],producerArgv.slice(1),{encoding:'utf8'});
 await fs.writeFile(out+'/public-producer.json',JSON.stringify({argv:producerArgv,rc:producer.status,signal:producer.signal,stdout:producer.stdout,stderr:producer.stderr},null,2));
 assert.equal(producer.status,1);assert.match(producer.stderr,/NATIVE_CJDB_RUNNER_REQUIRED/);
});

for(const mode of ['probe','native','install-only']){
 test('Windows command wiring: '+mode,async t=>{
  const work=await fs.mkdtemp(path.join(out,'wiring-'));
  t.after(()=>fs.rm(work,{recursive:true,force:true}));
  const observer=path.join(here,'fixtures/windows-toolchain-commands.mjs');
  const child=spawnSync(process.execPath,['--experimental-test-module-mocks',observer,mode,work],{encoding:'utf8'});
  assert.equal(child.status,0,child.stderr||child.error?.message);
  const {commands,bin,probeInstall,incomingProbePath}=JSON.parse(child.stdout.trim().split('\n').at(-1));
  const main=commands.find(c=>c.argv.includes('-DCANGJIE_BUILD_CJDB=ON'));
  for(const {argv} of commands.filter(c=>c.argv[0]==='cmake')){
   for(const def of argv.filter(arg=>arg.startsWith('-D')))assert.doesNotMatch(def,/\\/);
   if(argv.includes('-S')){
    const dlls=argv.find(arg=>arg.startsWith('-DCANGJIE_TOOLCHAIN_RUNTIME_FILES=')).split('=').at(1).split(';');
    assert.deepEqual(dlls.map(file=>path.posix.basename(file)),['libc++.dll','libunwind.dll']);
   }
  }
  const probeCmake=commands.filter(c=>c.argv[0]==='cmake'&&c!==main);
  assert.equal(probeCmake.length,mode==='install-only'?0:3,'expected probe configure/build/install');
  if(mode!=='install-only'){
   assert.ok(probeCmake[0].argv.includes('-S'));
   assert.ok(probeCmake[0].argv.includes('-DCMAKE_INSTALL_PREFIX='+probeInstall.replaceAll('\\','/')));
   assert.equal(probeCmake[1].argv[1],'--build');
   assert.equal(probeCmake[2].argv[1],'--install');
   for(const c of probeCmake)assert.equal(c.path.split(';')[0],bin,'probe CMake must search selected bin first: '+c.argv[1]);
   const consumer=commands.find(c=>path.basename(c.argv[0])==='toolchain_probe.exe');
   const system=process.env.SystemRoot||path.join(work,'Windows');
   assert.deepEqual(consumer.path.split(';'),[path.join(probeInstall,'bin'),path.join(probeInstall,'third_party/llvm/bin'),path.join(system,'System32'),system]);
  }
  if(mode!=='probe'){
   assertCompilerLibcxxEdits(main.argv[main.argv.indexOf('-S')+1]);
   const header=await fs.readFile(path.join(main.argv[main.argv.indexOf('-S')+1],'demangler/Demangler.h'),'utf8');
   assert.match(header,/#include <vector>\r?\n#ifndef BUILD_LIB_CANGJIE_DEMANGLE/,'native configure must see the unconditional vector include');
   if(mode==='native')assert.equal(incomingProbePath.split(';')[0],bin,'nativeCjdb must bind PATH before invoking probe');
   assert.equal(main.path.split(';')[0],bin,'main configure must search selected bin first: '+mode);
   assert.ok(main.argv.includes('-DCANGJIE_CJNATIVE_SOURCE_DIR=D:/a/cjcj/cjcj/llvm-fork'));
   const childArgs=main.argv.find(s=>s.startsWith('-DCJCJ_LLDB_ARGS=')).slice('-DCJCJ_LLDB_ARGS='.length).split(';');
   for(const [key,name] of [['AR','llvm-ar.exe'],['RANLIB','llvm-ranlib.exe']]){
    const arg='-DCMAKE_'+key+'='+path.join(bin,name).replaceAll('\\','/');
    assert.ok(main.argv.includes(arg),arg);
    assert.ok(childArgs.includes(arg),'standalone LLDB '+arg);
   }
   const build=main.argv[main.argv.indexOf('-B')+1];
   const tblgen=cmakePath(path.join(build,'third_party/cjnative-prefix/src/cjnative-build/bin/llvm-tblgen.exe'));
   assert.deepEqual(childArgs.filter(arg=>arg.startsWith('-DLLVM_TABLEGEN=')),['-DLLVM_TABLEGEN='+tblgen]);
   assertCjnativeHostArgs(main.argv[main.argv.indexOf('-S')+1],work);
  }
 });
}

test('CMake configure reparses the LLVM source path without corrupting Windows escapes',async t=>{
 const source=await fs.mkdtemp(path.join(out,'cmake-'));
 t.after(()=>fs.rm(source,{recursive:true,force:true}));
 // Like a generated install script, a macro substitutes its argument as CMake source.
 await fs.writeFile(path.join(source,'CMakeLists.txt'),[
  'cmake_minimum_required(VERSION 3.20)','project(path_probe NONE)',
  'macro(select_source root)',
  ' file(WRITE "${CMAKE_BINARY_DIR}/selected.txt" "${root}/llvm/lib/Support/ConvertUTF.cpp")',
  'endmacro()','select_source("${CANGJIE_CJNATIVE_SOURCE_DIR}")',''].join('\n'));
 const windows='D:\\a\\cjcj\\cjcj\\llvm-fork';
 for(const [label,value] of [['raw',windows],['normalized',cmakePath(windows)]]){
  const build=path.join(source,label);
  const args=['-S',source,'-B',build,'-DCANGJIE_CJNATIVE_SOURCE_DIR='+value];
  const r=spawnSync('cmake',args,{encoding:'utf8'});
  assert.ifError(r.error);
  await fs.writeFile(path.join(out,'cmake-'+label+'.json'),JSON.stringify({args,rc:r.status,stderr:r.stderr,stdout:r.stdout}));
  if(label==='raw'){
   assert.equal(r.status,1,r.stderr);
   assert.match(r.stderr,/Invalid character escape '\\a'/);
  }else{
   assert.equal(r.status,0,r.stderr);
   assert.equal(await fs.readFile(path.join(build,'selected.txt'),'utf8'),'D:/a/cjcj/cjcj/llvm-fork/llvm/lib/Support/ConvertUTF.cpp');
  }
 }
});
