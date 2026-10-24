#!/usr/bin/env zx
// Materialize selected sources once. Official CMake/Ninja owns the writable
// private tree thereafter, including configure_file and ExternalProject patches.
import fs from 'node:fs/promises';
import path from 'node:path';
import {isDeepStrictEqual} from 'node:util';
import {atomicJson,readJson,privateRoot} from './sdk-flow.mjs';
import {verifyNativeSource} from './sdk-source.mjs';
export async function prepareNativeCompilerSource({compiler,compilerArchive,bounds,flatbuffers,build,install=path.join(build,'install'),commit,commits={}},run) {
 const original=compilerArchive?path.resolve(compiler):await fs.realpath(compiler),working=path.resolve(build)+'.compiler-source';
 await privateRoot(working);
 if(working===original||working.startsWith(original+path.sep))throw Error('NATIVE_COMPILER_BUILD_INSIDE_SOURCE');
 if(!/^[a-f0-9]{40}$/.test(commit||''))throw Error('NATIVE_AST_SOURCE_REQUIRED');
 const source={root:working,commit,originalRoot:original,
  dependencies:{bounds:{root:await fs.realpath(bounds),...(commits.bounds?{commit:commits.bounds}:{})},
   flatbuffers:{root:await fs.realpath(flatbuffers),...(commits.flatbuffers?{commit:commits.flatbuffers}:{})}},
  ...(compilerArchive?{archive:{file:path.resolve(compilerArchive.file),sha256:compilerArchive.sha256}}:{})};
 const record=path.join(install,'BUILD-INPUTS.json');
 const previous=await readJson(record).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
 if(previous){
  // A different explicit input needs a different build directory. This is the
  // original selection, not a digest/stamp granting validity to working bytes.
  if(!isDeepStrictEqual(previous.compilerSource,source))throw Error('NATIVE_COMPILER_SOURCE_SELECTION_CHANGED use a new build/install directory');
  await fs.access(path.join(working,'CMakeLists.txt'));
  return {compiler:working,source};
 }
 await verifyNativeSource({source:original,commit,output:build,
  ...(compilerArchive?{'source-archive':compilerArchive.file,'source-archive-sha256':compilerArchive.sha256}:{})});
 // Materialize into a new empty directory. Preserve an interrupted extraction
 // for diagnosis; never adopt or overwrite an unrelated existing source tree.
 await fs.mkdir(path.dirname(working),{recursive:true});
 await fs.mkdir(working);
 if(compilerArchive) {
  await run(['tar','-xf',compilerArchive.file,'-C',working]);
 }
 for(const [from,to] of [...(compilerArchive?[]:[[original,working]]),[source.dependencies.bounds.root,path.join(working,'third_party/boundscheck')],
  [source.dependencies.flatbuffers.root,path.join(working,'third_party/flatbuffers')]]) {
  const existing=await fs.lstat(to).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  if(existing&&!existing.isDirectory())throw Error('NATIVE_COMPILER_WORK_DIRECTORY '+to);
  await fs.cp(from,to,{recursive:true,verbatimSymlinks:true,filter:file=>path.basename(file)!=='.git'});
 }
 await atomicJson(record,{compilerSource:source});
 return {compiler:working,source};
}
