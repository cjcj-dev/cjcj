#!/usr/bin/env zx
// Run the selected native compiler and its own runtime before the large N build.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {atomicJson,fileDigest,readJson,command,privateRoot} from './sdk-flow.mjs';
import {execute} from './sdk-io.mjs';

export async function selectedExecutable(value,env=process.env) {
 if(!value)throw Error('WINDOWS_COMPILER_REQUIRED');
 const candidates=path.isAbsolute(value)||/[\\/]/.test(value)?[path.resolve(value)]:
  (env.PATH||'').split(path.delimiter).flatMap(dir=>[path.join(dir,value),path.join(dir,value+'.exe')]);
 for(const file of candidates)if(await fs.stat(file).then(s=>s.isFile(),()=>false))return fs.realpath(file);
 throw Error('WINDOWS_COMPILER_MISSING '+value);
}
export function coffImports(text) {
 return [...text.matchAll(/^\s*Name:\s*([^\s]+\.dll)\s*$/gmi)].map(m=>m[1].toLowerCase());
}
export function requireMsvcrtImports(imports,{executable=false}={}) {
 if(!imports.length||imports.some(n=>/^(?:ucrtbase|api-ms-win-crt-.*|libstdc\+\+-6|libgcc_s.*)\.dll$/i.test(n))
   ||executable&&!imports.includes('msvcrt.dll'))throw Error('WINDOWS_TOOLCHAIN_CRT');
}
export const WINDOWS_COMPILER_PROBE=String.raw`#include <_mingw.h>
#include <cstdio>
#include <stdexcept>
#include <string>
#if !defined(__clang__) || !defined(__MINGW32__) || !defined(_WIN64) || defined(_UCRT)
#error Expected native x86_64 Clang with MSVCRT headers
#endif
int main() {
 try { throw std::runtime_error(std::string("42")); }
 catch (const std::exception &e) { return std::printf("WINDOWS_CLANG_MSVCRT_RUNTIME %s\n", e.what()) > 0 ? 0 : 1; }
}
`;
export async function probeWindowsToolchain({tools,compiler,work,env=process.env}) {
 if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_TOOLCHAIN_NATIVE_REQUIRED');
 work=await privateRoot(work);
 await fs.mkdir(path.dirname(work),{recursive:true});
 work=await fs.mkdtemp(work+'-'); // Keep every attempt, including normal reentry.
 const records=[],facts={commands:records};
 const save=()=>atomicJson(path.join(work,'toolchain.json'),facts);
 const capture=async(label,argv,options={})=>{
  const row={label,argv,rc:null,signal:null};records.push(row);
  try {const r=await execute(argv[0],argv.slice(1),{env,maxBuffer:4*1024**2,timeout:120000,...options});
   row.rc=0;row.stdout=r.stdout;row.stderr=r.stderr;return r.stdout;
  }catch(e){row.rc=typeof e.code==='number'?e.code:null;row.signal=e.signal||null;row.error=e.message;row.stdout=e.stdout;row.stderr=e.stderr;throw e;}
  finally{await save();}
 };
 try {
  const cc=await selectedExecutable(tools.cc,env),cxx=await selectedExecutable(tools.cxx,env);
  if(path.dirname(cc)!==path.dirname(cxx))throw Error('WINDOWS_TOOLCHAIN_COMPILER_PAIR');
  const root=path.dirname(path.dirname(cc)),target=path.join(root,'x86_64-w64-mingw32');
  const version=await capture('cxx-version',[cxx,'--version']);
  const triple=(await capture('cxx-target',[cxx,'-print-target-triple'])).trim();
  if(!/clang version /i.test(version)||!/^x86_64-(?:w64-windows-gnu|w64-mingw32)$/.test(triple))throw Error('WINDOWS_TOOLCHAIN_CLANG_TARGET');
  const readobj=await selectedExecutable(path.join(root,'bin','llvm-readobj.exe'),env);
  const runtimeDirectory=path.join(target,'bin');
  const runtimeFiles=(await fs.readdir(runtimeDirectory)).filter(n=>/\.dll$/i.test(n)).sort().map(n=>path.join(runtimeDirectory,n));
  if(!runtimeFiles.some(n=>path.basename(n).toLowerCase()==='libc++.dll'))throw Error('WINDOWS_TOOLCHAIN_LIBCXX');
  facts.compiler={cc:{path:cc,sha256:await fileDigest(cc)},cxx:{path:cxx,sha256:await fileDigest(cxx)},version,triple};
  facts.runtimes=[];
  for(const file of runtimeFiles){
   const imports=coffImports(await capture('runtime-imports-'+path.basename(file),[readobj,'--coff-imports',file]));
   requireMsvcrtImports(imports);
   facts.runtimes.push({path:file,sha256:await fileDigest(file),imports});
  }
  // The real upstream toolchain must preserve the compiler selected here.
  // This small program uses C++, exceptions and the actual MSVCRT headers.
  const source=path.join(work,'source'),build=path.join(work,'build'),install=path.join(work,'install');
  await fs.mkdir(source);await fs.writeFile(path.join(source,'probe.cpp'),WINDOWS_COMPILER_PROBE);
  await fs.writeFile(path.join(source,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(WindowsCompilerInput C CXX)
if(NOT CMAKE_C_COMPILER_ID STREQUAL "Clang" OR NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
 message(FATAL_ERROR "WINDOWS_TOOLCHAIN_ACTUAL_COMPILER")
endif()
if(NOT LLVM_BUILD_C_COMPILER STREQUAL CMAKE_C_COMPILER OR NOT LLVM_BUILD_CXX_COMPILER STREQUAL CMAKE_CXX_COMPILER)
 message(FATAL_ERROR "WINDOWS_TOOLCHAIN_LLVM_COMPILER")
endif()
add_executable(toolchain_probe probe.cpp)
install(TARGETS toolchain_probe RUNTIME DESTINATION bin)
include("\${CANGJIE_RUNTIME_INSTALL_RULE}")
`);
  const run=argv=>command(argv,{env,records});
  await run([tools.cmake||'cmake','-S',source,'-B',build,'-G','Ninja',
   '-DCMAKE_BUILD_TYPE=Release',`-DCMAKE_C_COMPILER=${cc}`,`-DCMAKE_CXX_COMPILER=${cxx}`,
   `-DCMAKE_TOOLCHAIN_FILE=${path.join(compiler,'cmake/mingw_x86_64_toolchain.cmake')}`,
   `-DCMAKE_C_COMPILER_LAUNCHER=${tools.launcher||''}`,`-DCMAKE_CXX_COMPILER_LAUNCHER=${tools.launcher||''}`,
   `-DCANGJIE_RUNTIME_INSTALL_RULE=${path.join(compiler,'cmake/modules/InstallWindowsToolchain.cmake')}`,
   `-DCANGJIE_TOOLCHAIN_RUNTIME_FILES=${runtimeFiles.join(';')}`,`-DCMAKE_INSTALL_PREFIX=${install}`]);
  await run([tools.cmake||'cmake','--build',build,'--parallel','1']);
  await run([tools.cmake||'cmake','--install',build]);
  const program=path.join(install,'bin/toolchain_probe.exe');
  const imports=coffImports(await capture('consumer-imports',[readobj,'--coff-imports',program]));
  requireMsvcrtImports(imports,{executable:true});
  if(!imports.includes('libc++.dll'))throw Error('WINDOWS_TOOLCHAIN_CONSUMER_LIBCXX');
  const output=await capture('installed-consumer',[program],{cwd:install,env:windowsInstalledEnvironment(env,install)});
  if(!output.includes('WINDOWS_CLANG_MSVCRT_RUNTIME 42'))throw Error('WINDOWS_TOOLCHAIN_CONSUMER');
  facts.consumer={path:program,sha256:await fileDigest(program),imports,output};facts.rc=0;await save();
  return {cc,cxx,runtimeFiles,record:path.join(work,'toolchain.json'),facts};
 }catch(error){facts.error=error.message;facts.rc=error.rc??(typeof error.code==='number'?error.code:1);await save();throw error;}
}
export function windowsInstalledEnvironment(env,install) {
 const system=env.SystemRoot||env.SYSTEMROOT;
 if(!system)throw Error('WINDOWS_TOOLCHAIN_SYSTEMROOT');
 return {...env,PATH:[path.join(install,'bin'),path.join(install,'third_party/llvm/bin'),path.join(system,'System32'),system].join(';')};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try{console.log(JSON.stringify(await probeWindowsToolchain(await readJson(process.argv[2]))));}
 catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
