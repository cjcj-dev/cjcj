// Runtime identity and ABI are checked from actual installed products.
import path from 'node:path';
import fs from 'node:fs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {verifyRuntime,runtimeFiles,digest} from '../release/colour_runtime.mjs';
import {execute} from './sdk-io.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {nativeSymbolRows} from './std-runtime-colour.mjs';
export async function verifyBootstrapRuntimeSdk(sdk,tuple,env=process.env,sourceRoot){
 const selection=await resolveRuntimeSource(env),original=verifyRuntime({...env,RUNTIME_REF:selection.runtimeRef});
 const native=sdkPlatform(tuple.replace(/_cjnative$/,''));
 if(sourceRoot){const r=await execute('git',['-C',sourceRoot,'rev-parse','HEAD']);
  if(r.stdout.trim()!==selection.runtimeRef)throw new Error('BOOTSTRAP_RUNTIME_SOURCE_MISMATCH');}
 for(const rel of runtimeFiles){
  const installed=rel.replace('linux_x86_64_cjnative',tuple).replace(/\.so$/,native.shared);
  if(digest(path.join(sdk,installed))!==digest(path.join(original,rel)))throw new Error('BOOTSTRAP_SDK_RUNTIME_MISMATCH '+installed);
  if(path.basename(installed).startsWith('libcangjie-runtime.')){
   const stamps=[...new Set(fs.readFileSync(path.join(sdk,installed)).toString('latin1').match(/CJRT-COMMIT:[A-Za-z0-9_-]+/g)||[])];
   if(stamps.length!==1||stamps[0]!=='CJRT-COMMIT:'+selection.runtimeRef)throw new Error('BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH '+installed);
  }
 }
 const shared=path.join(sdk,'runtime/lib',tuple,'libcangjie-runtime'+native.shared),archive=path.join(sdk,'lib',tuple,'libcangjie-runtime.a');
 const sharedMasks=(await nativeSymbolRows(shared,{platform:tuple.replace(/_cjnative$/,''),runtime:true})).filter(n=>n==='g_cjLoadBadMask').length;
 const archiveMasks=(await nativeSymbolRows(archive,{platform:tuple.replace(/_cjnative$/,''),defined:true})).filter(n=>n==='g_cjLoadBadMask').length;
 if(sharedMasks!==1||archiveMasks<1)throw new Error('BOOTSTRAP_SDK_RUNTIME_COLOUR_PAIR_MISMATCH');
 console.log(`BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED runtime=${selection.runtimeRef}`);
}
