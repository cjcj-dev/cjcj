#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {coffImports,requireMsvcrtImports,selectedExecutable,windowsInstalledEnvironment} from './native-windows-toolchain.mjs';
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
 assert.equal(result.PATH,'C:/N/bin;C:/N/third_party/llvm/bin;C:/Windows/System32;C:/Windows');
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
