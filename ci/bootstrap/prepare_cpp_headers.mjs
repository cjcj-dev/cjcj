#!/usr/bin/env zx
// One producer for source-built Cjo shim headers. Original sources stay immutable.
import fs from 'node:fs';
import path from 'node:path';
import {selectBuildJobs} from '../build-resources.mjs';
import {fileURLToPath} from 'node:url';
import {run} from '../../build/lib/runner.mjs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {selectShimSources,resolveShimSources} from './shim-header-sources.mjs';

const roots=['third_party/llvm-project/llvm/include','build/build/third_party/llvm/include','build/build/include','build/build/schema'];
const sourceIdentity=sources=>Object.fromEntries(Object.entries(sources).map(([name,row])=>[name,{
 commit:row.commit,root:row.root,...(row.repository?{repository:row.repository}:{}),...(row.archive?{archive:row.archive}:{})}]));
async function selection(cpp,runtimePinFile,env) {
 const runtime=await resolveRuntimeSource(env,runtimePinFile),sources=selectShimSources(cpp,env);
 if(sources.runtime.commit!==runtime.runtimeRef)throw Error('SHIM_HEADERS_RUNTIME_PAIR');
 // This is the target LLVM pair, never the independent bootstrap host LLVM.
 const targetLlvm=runtime.nativePair?.llvm||env.LLVM_SHA;
 if(targetLlvm&&sources.llvm.commit!==targetLlvm)throw Error('SHIM_HEADERS_LLVM_PAIR');
 return sources;
}
export async function prepareCppHeaders(cppSrc,runtimePinFile=process.env.CJCJ_BOOTSTRAP_RUNTIME_PIN,env=process.env) {
 const cpp=path.resolve(cppSrc);await selection(cpp,runtimePinFile,env);
 fs.mkdirSync(cpp,{recursive:true});
 const sources=await resolveShimSources(cpp,env,{fetch:true});
 const compiler=sources.compiler.root,llvm=sources.llvm.root,runtime=sources.runtime.root,flatbuffers=sources.flatbuffers.root;
 const schemaSource=path.join(compiler,'schema/CjoFormat.fbs');
 if(!fs.existsSync(schemaSource))throw Error('SHIM_HEADERS_CJO_SOURCE '+sources.compiler.commit);
 const build=path.join(cpp,'build/build'),llvmBuild=path.join(build,'third_party/llvm');
 const flatBuild=path.join(cpp,'build/shim-flatbuffers'),schema=path.join(build,'schema/flatbuffers');
 const flatc=path.join(flatBuild,'flatc'+(process.platform==='win32'?'.exe':''));
 const jobs=String(await selectBuildJobs(undefined,env)),commands=[];
 const cleanEnv={...env};
 for(const key of ['CPATH','CPLUS_INCLUDE_PATH','C_INCLUDE_PATH','OBJC_INCLUDE_PATH'])cleanEnv[key]='';
 async function execute(argv) {
  const started=new Date().toISOString();
  try { const result=await run(argv,{stage:'bootstrap.cpp-headers',env:cleanEnv});
   commands.push({argv,rc:result.exitCode??0,started,ended:new Date().toISOString()});}
  catch(error){commands.push({argv,rc:error.exitCode??error.rc??null,error:String(error),started,ended:new Date().toISOString()});throw error;}
  finally{fs.writeFileSync(path.join(cpp,'shim-header-commands.json'),JSON.stringify(commands,null,2));}
 }
 await execute(['cmake','-G','Ninja','-S',path.join(llvm,'llvm'),'-B',llvmBuild,
  '-DCANGJIE_RUNTIME_SOURCE_DIR='+runtime,'-DCMAKE_BUILD_TYPE=Release','-DLLVM_ENABLE_PROJECTS=','-DLLVM_TARGETS_TO_BUILD=X86',
  '-DLLVM_ENABLE_RTTI=OFF','-DLLVM_INCLUDE_TESTS=OFF','-DLLVM_INCLUDE_BENCHMARKS=OFF','-DLLVM_INCLUDE_EXAMPLES=OFF',
  '-DLLVM_BUILD_TOOLS=OFF','-DLLVM_ENABLE_BINDINGS=OFF','-DLLVM_ENABLE_TERMINFO=OFF','-DLLVM_ENABLE_ZLIB=OFF','-DLLVM_ENABLE_ZSTD=OFF','-DLLVM_ENABLE_LIBXML2=OFF',
  '-DCMAKE_C_COMPILER='+(env.CC||'clang'),'-DCMAKE_CXX_COMPILER='+(env.CXX||'clang++')]);
 await execute(['cmake','--build',llvmBuild,'--target','intrinsics_gen','-j',jobs]);
 await execute(['cmake','-G','Ninja','-S',flatbuffers,'-B',flatBuild,
  '-DFLATBUFFERS_BUILD_TESTS=OFF','-DFLATBUFFERS_BUILD_FLATLIB=OFF','-DFLATBUFFERS_BUILD_SHAREDLIB=OFF',
  '-DCMAKE_C_COMPILER='+(env.CC||'clang'),'-DCMAKE_CXX_COMPILER='+(env.CXX||'clang++')]);
 await execute(['cmake','--build',flatBuild,'--target','flatc','-j',jobs]);
 fs.mkdirSync(schema,{recursive:true});
 await execute([flatc,'--no-warnings','-c','-o',schema,schemaSource]);
 for(const [from,to] of [[path.join(llvm,'llvm/include'),roots[0]],[path.join(flatbuffers,'include'),roots[2]],
  [schemaSource,'schema/CjoFormat.fbs']]) {
  fs.mkdirSync(path.dirname(path.join(cpp,to)),{recursive:true});fs.cpSync(from,path.join(cpp,to),{recursive:true});
 }
 const manifest={sources:sourceIdentity(sources),commands};
 const record=path.join(cpp,'BUILD-INPUTS.json');
 fs.writeFileSync(record,JSON.stringify(manifest,null,2)+'\n');
 console.log('SHIM_HEADERS_READY inputs='+record);
 return manifest;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 if(!process.argv[2])throw Error('usage: prepare_cpp_headers.mjs <private header output> [runtime selection]');
 await prepareCppHeaders(process.argv[2],process.argv[3]);
}
