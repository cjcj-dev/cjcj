#!/usr/bin/env zx
// Finite command observer for the real Windows probe and nativeCjdb entry points.
// No Windows binary executes here. The archive, Python and source inputs are fixtures.
import fs from 'node:fs/promises';
import path from 'node:path';
import {mock} from 'node:test';
import * as flow from '../sdk-flow.mjs';
import * as io from '../sdk-io.mjs';

const [mode,work]=process.argv.slice(2);
const windowsRoot='D:\\a\\cjcj\\cjcj';
// On POSIX, a literal Windows path component exercises even fs.realpath results.
const root=process.platform==='win32'?work:path.join(work,windowsRoot);
const compiler=path.join(root,'compiler'), bin=path.join(root,'selected toolchain','bin');
const build=path.join(root,'build'),install=path.join(root,'install');
const tools={cc:path.join(bin,'clang.exe'),cxx:path.join(bin,'clang++.exe'),launcher:windowsRoot+'/sccache.exe'};
const runtime=path.join(path.dirname(bin),'x86_64-w64-mingw32','bin','libc++.dll');
for(const file of [tools.cc,tools.cxx,path.join(bin,'llvm-readobj.exe'),runtime,path.join(path.dirname(runtime),'libunwind.dll')]){
 await fs.mkdir(path.dirname(file),{recursive:true});
 await fs.writeFile(file,'finite fixture');
}
const commands=[];
let probeInstall;
const mainConfigure=new Error('observed main configure');
mock.module('../sdk-flow.mjs',{namedExports:{...flow,command:async(argv,{env})=>{
 commands.push({argv,path:env.PATH});
 if(argv.includes('-DCANGJIE_BUILD_CJDB=ON'))throw mainConfigure;
 if(argv.includes('--install')){
  // Materialize the fake executable in the fixture's host filesystem.
  probeInstall=path.join(path.dirname(argv[2]),'install');
  await fs.mkdir(path.join(probeInstall,'bin'),{recursive:true});
  await fs.writeFile(path.join(probeInstall,'bin','toolchain_probe.exe'),'finite consumer');
 }
}}});
mock.module('../sdk-io.mjs',{namedExports:{...io,execute:async(file,args,{env})=>{
 commands.push({argv:[file,...args],path:env.PATH});
 if(args.includes('--version'))return {stdout:'clang version fixture'};
 if(args.includes('-print-target-triple'))return {stdout:'x86_64-w64-mingw32'};
 if(args.includes('--coff-imports'))return {stdout:'Name: msvcrt.dll\nName: libc++.dll'};
 if(file.endsWith('toolchain_probe.exe'))return {stdout:'WINDOWS_CLANG_MSVCRT_RUNTIME 42'};
 throw Error('unexpected command: '+file+' '+args);
}}});
const python=await import('../sdk-cjdb-python.mjs');
mock.module('../sdk-cjdb-python.mjs',{namedExports:{...python,pythonConfiguration:()=>({
 executable:windowsRoot+'\\python\\python.exe',include:windowsRoot+'\\python\\include',
 library:windowsRoot+'\\python\\libs\\python311.lib',suffix:'.pyd'})}});
mock.module('../native-compiler-input.mjs',{namedExports:{prepareNativeCompilerSource:()=>({compiler,source:{root:compiler}})}});
const windows=await import('../native-windows-toolchain.mjs');
let incomingProbePath;
if(mode==='native')mock.module('../native-windows-toolchain.mjs',{namedExports:{...windows,probeWindowsToolchain:options=>{
 incomingProbePath=options.env.PATH;
 return windows.probeWindowsToolchain(options);
}}});
const {nativeCjdb}=await import('../native-cjdb.mjs');
Object.defineProperty(process,'platform',{value:'win32'});
Object.defineProperty(process,'arch',{value:'x64'});
process.env.SystemRoot??=path.join(work,'Windows');
if(mode==='probe'){
 await windows.probeWindowsToolchain({tools,compiler,work:build,env:{SystemRoot:process.env.SystemRoot,PATH:'ambient'}});
}else{
 await fs.cp(new URL('../../../build/test/fixtures/compiler-41b223-windows/',import.meta.url),compiler,{recursive:true});
 await fs.cp(new URL('../../../build/test/fixtures/compiler-41b223-schema/schema/',import.meta.url),path.join(compiler,'schema'),{recursive:true});
 const config={compiler,build,install,tools,commits:{compiler:'f'.repeat(40)},platform:'windows_x86_64',
  llvm:windowsRoot+'\\llvm-fork',runtime:windowsRoot+'\\runtime-source',python:windowsRoot+'\\python',
  xml2Archive:{file:runtime,sha256:await flow.fileDigest(runtime)}};
 const installOnly=mode==='install-only';
 if(installOnly){
  await flow.atomicJson(path.join(install,'BUILD-INPUTS.json'),{commands:[],configuration:config,commits:config.commits,
   compilerSource:{root:compiler,commit:config.commits.compiler},
   windowsToolchain:{installedFiles:[{path:'bin/libc++.dll'},{path:'bin/libunwind.dll'}]}});
 }
 try{
  await nativeCjdb(installOnly?{nativeInstall:install,install:path.join(root,'new-install')}:config,{installOnly});
  throw Error('main configure not observed');
 }catch(err){if(err!==mainConfigure)throw err;}
}
console.log(JSON.stringify({commands,bin,probeInstall,incomingProbePath}));
