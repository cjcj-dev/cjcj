// Cjo shim header sources are separate from historical binary tuple pins.
import fs from 'node:fs';
import path from 'node:path';
import {checkoutExactSource} from '../../build/lib/git.mjs';
import {run} from '../../build/lib/runner.mjs';
import {verifyNativeSource,materializeNativeSource} from './sdk-source.mjs';
import {command} from './sdk-flow.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';
const pins=readSourcePins();
export const SHIM_SOURCE_COMMITS=Object.freeze({compiler:pins.source.COMPILER_REF,
 llvm:pins.llvm.LLVM_SHA,runtime:pins.runtime.RUNTIME_REF,flatbuffers:pins.llvm.FLATBUFFERS_SHA});
const repositories={compiler:pins.source.COMPILER_SRC_URL,llvm:pins.llvm.LLVM_URL,
 runtime:pins.runtime.RUNTIME_SRC_URL,flatbuffers:pins.llvm.FLATBUFFERS_URL};

export function selectShimSources(root,env=process.env) {
 const explicit=env.CJCJ_BOOTSTRAP_SHIM_SOURCES
  ?JSON.parse(fs.readFileSync(env.CJCJ_BOOTSTRAP_SHIM_SOURCES,'utf8'))
  :JSON.parse(env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION||'{}');
 if(!explicit||Array.isArray(explicit)||typeof explicit!=='object'
   ||Object.keys(explicit).some(name=>!Object.hasOwn(SHIM_SOURCE_COMMITS,name)))
  throw Error('SHIM_SOURCE_SELECTION');
 return Object.fromEntries(Object.entries(SHIM_SOURCE_COMMITS).map(([name,commit])=>{
  const row=explicit[name]||{};
  if(typeof row!=='object'||Array.isArray(row)||row.commit&&!/^[a-f0-9]{40}$/.test(row.commit))
   throw Error('SHIM_SOURCE_SELECTION '+name);
  return [name,{...(explicit[name]?{}:{repository:repositories[name]}),...row,commit:row.commit||commit,root:path.resolve(row.root||path.join(root,'sources',name))}];
 }));
}

export async function resolveShimSources(root,env=process.env,{fetch=false}={}) {
 const sources=selectShimSources(root,env);
 for(const [name,row] of Object.entries(sources)) {
  if(row.archive) {
   if(!fs.existsSync(row.root)&&!fetch)throw Error('SHIM_SOURCE_LOCATION_REQUIRED '+name+' '+row.commit);
   await materializeNativeSource({source:row.root,commit:row.commit,'source-archive':row.archive.file,'source-archive-sha256':row.archive.sha256},command);
  } else {
   if(!fs.existsSync(row.root)) {
    if(!fetch||!row.repository)throw Error('SHIM_SOURCE_LOCATION_REQUIRED '+name+' '+row.commit);
    await checkoutExactSource(row.repository,row.root,row.commit);
   }
   await verifyNativeSource({source:row.root,commit:row.commit});
   const origin=await run(['git','-C',row.root,'config','--get','remote.origin.url'],{capture:true,check:false,logOutput:false});
   const actual=origin.exitCode===0?origin.stdout.trim():null;
   if(row.repository&&actual!==row.repository)throw Error('SHIM_SOURCE_REPOSITORY '+name);
   if(actual)row.repository=actual;
  }
 }
 return sources;
}
