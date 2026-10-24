import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest,readJson,copyOutputs} from '../../bootstrap/sdk-flow.mjs';
import {compilerProducer,verifyCompiler} from '../../bootstrap/compiler_identity.mjs';
import {sdkPlatform} from '../../bootstrap/sdk-platform.mjs';
import {verifyColourTuple} from '../../release/bootstrap_tuple.mjs';
import {parseLlvmToolsManifest} from '../../llvm-tools-manifest.mjs';
export async function assertBootstrapCompiler({sdk,command,producer,producerSha256}){
 await verifyCompiler(sdk,producerSha256);
 const original=await compilerProducer(sdk);
 const suffix=original.endsWith('.exe')?'.exe':'';
 if(await fs.realpath(command)!==await fs.realpath(path.join(sdk,'bin','cjc'+suffix))
  ||await fileDigest(producer)!==producerSha256||await fileDigest(original)!==producerSha256)
  throw new Error('bootstrap compiler independent producer mismatch');
 if(await fs.readlink(path.join(sdk,'bin','cjc'+suffix))!=='cjcj-stage1'+suffix)throw new Error('bootstrap compiler alias mismatch');
 return {producer,compilerSha256:producerSha256,entrySha256:await fileDigest(command)};
}
export async function prepareBootstrapHandoff({work,sdk,source,tuple}){
 const native=sdkPlatform(tuple.replace(/_cjnative$/,''));
 const installed=path.join(work,'sdk-stage2');
 const compiler=await compilerProducer(installed);
 if(path.resolve(sdk)!==path.resolve(installed))await copyOutputs(sdk,[{from:installed,to:''}]);
 const objects=['cjselfhost_llvmshim.o','cjc_runtime_config.o'];
 for(const name of objects){await fs.mkdir(path.join(source,'runtime_shim'),{recursive:true});
  await fs.copyFile(path.join(installed,'share/cjcj/runtime_shim',name),path.join(source,'runtime_shim',name));}
 const targetLd=[sdk+'/third_party/llvm/lib',sdk+'/runtime/lib/'+tuple,sdk+'/lib/'+tuple,sdk+'/tools/lib'].join(path.delimiter);
 return {compiler,targetLd,stdOutput:{prefix:sdk,coreSha256:await fileDigest(path.join(sdk,'lib',native.tuple,'libcangjie-std-core.a'))}};
}
export async function bootstrapBackendIdentity(env=process.env){
 const {directory}=verifyColourTuple(env.CJCJ_BOOTSTRAP_COLOUR_TUPLE,{pinFile:env.CJCJ_BOOTSTRAP_INPUTS_PIN,sumsSha:env.LLVM_TUPLE_SUMS_SHA});
 const {values}=parseLlvmToolsManifest(await fs.readFile(path.join(directory,'fixed-llc/llvm-tools.manifest'),'utf8'));
 const llvmSha=env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA,library=env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SO;
 const metadata=await readJson(path.join(path.dirname(library),'manifest.json'));
 if(values.get('LLVM_SHA')!==llvmSha||metadata.llvm_sha!==llvmSha||await fileDigest(library)!==env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256)
  throw new Error('BOOTSTRAP_BACKEND_INPUT_MISMATCH');
 const native=sdkPlatform(values.get('PLATFORM'));
 return {llvmSha,files:{['bin/opt'+native.exe]:values.get('OPT_SHA256'),['bin/llc'+native.exe]:values.get('LLC_SHA256'),
  ['bin/'+values.get('LLD_TOOL')+native.exe]:values.get('LLD_SHA256'),[native.llvmDirectory+'/'+native.llvmLibrary]:env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256}};
}
export async function assertBootstrapBackends({sdk,targetLd,identity}){
 const root=path.join(sdk,'third_party/llvm');
 for(const [rel,expected]of Object.entries(identity.files)){
  const file=path.join(root,rel);
  if(await fileDigest(file)!==expected)throw new Error('BOOTSTRAP_BACKEND_HASH_MISMATCH '+rel);
  const stamps=[...new Set((await fs.readFile(file)).toString('latin1').match(/CJLLVM-COMMIT:[A-Za-z0-9_-]+/g)||[])];
  if(stamps.length!==1||stamps[0]!=='CJLLVM-COMMIT:'+identity.llvmSha)throw new Error('BOOTSTRAP_BACKEND_STAMP_MISMATCH '+rel);
 }
 const library=Object.keys(identity.files).find(rel=>/libLLVM.*\.(?:so|dylib|dll)$/.test(rel));
 const resolved=[];for(const dir of targetLd.split(path.delimiter)){
  try{resolved.push(await fs.realpath(path.join(dir,path.basename(library))));}catch(e){if(e.code!=='ENOENT')throw e;}}
 if(resolved[0]!==await fs.realpath(path.join(root,library)))throw new Error('BOOTSTRAP_BACKEND_LOADER_MISMATCH');
}
