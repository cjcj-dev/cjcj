#!/usr/bin/env zx
import {readInstalledNativeShim} from './native-shim-inputs.mjs';
// Native installations retain ABI, source stamp and reader obligations after
// the receipt graph is removed. Results come from installed tools and libraries.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execute, readJson, fileDigest, atomicJson} from './sdk-io.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {nativeSymbolRows} from './std-runtime-colour.mjs';
import {verifyLlvmDylib} from './sdk-native-capi.mjs';
import {verifyCjdbPythonConfiguration, verifyCjdbPythonInstallation, pythonSourceInputs, verifyRelocatedCjdbPython} from './sdk-cjdb-python.mjs';
import {runtimeInputsForArtifact,RUNTIME_INPUTS} from '../../build/lib/runtime-source-inputs.mjs';
import {readInstalledNativeAst} from './installed-native-ast.mjs';

export async function verifyInstalledBitcodeReaders({install,platform,work,commit}) {
    const native=sdkPlatform(platform),root=path.join(install,'third_party/llvm');
    const env={...process.env,[native.loader]:[path.join(root,native.llvmDirectory),path.join(install,'tools/lib'),
      process.env[native.loader]].filter(Boolean).join(path.delimiter)};
    const library=path.join(root,native.llvmDirectory,native.llvmLibrary);
    const stamps=[...new Set([...((await fs.readFile(library)).toString('latin1')).matchAll(/CJLLVM-COMMIT:([0-9a-z_-]+)/g)].map(m=>m[1]))];
    console.log('LLVM_READER_SOURCE_ASSERTION_REACHED '+JSON.stringify(stamps));
    if(stamps.length!==1||stamps[0]!==commit)throw new Error('LLVM_READER_SOURCE');
    // Round-trip actual bitcode through the installed readers, rather than
    // treating --version or a historical reader certificate as qualification.
    const ir=path.join(work,'reader.ll'),bc=path.join(work,'reader.bc'),decoded=path.join(work,'reader-decoded.ll');
    await fs.writeFile(ir,'define i32 @native_reader_value() { ret i32 42 }\n');
    const readerResults=[];
    for(const [name,args] of [['llvm-as',[ir,'-o',bc]],['llvm-dis',[bc,'-o',decoded]]]) {
      const binary=path.join(root,'bin',name+native.exe),result=await execute(binary,args,{env});
      readerResults.push({binary,sha256:await fileDigest(binary),...result});
      if(native.os==='linux') {
        const loaded=(await execute('/usr/bin/ldd',[binary],{env})).stdout;
        console.log('LLVM_READER_DOMAIN_ASSERTION_REACHED '+JSON.stringify({binary,loaded}));
        if(loaded.includes('not found')||!loaded.split('\n').some(line=>line.includes(native.llvmLibrary)&&line.includes(path.join(root,native.llvmDirectory))))
          throw new Error('LLVM_READER_DOMAIN');
      }
    }
    const value=await fs.readFile(decoded,'utf8');
    console.log('LLVM_READER_VALUE_ASSERTION_REACHED '+JSON.stringify({value,readerResults}));
    if(!/define i32 @native_reader_value\(\)/.test(value)||!value.includes('ret i32 42'))throw new Error('LLVM_READER_VALUE');
    return {value,readerResults};
}
export async function checkNativeInput(request) {
  const {kind,install,commit,platform,work}=request, native=sdkPlatform(platform);
  const facts={};
  await fs.mkdir(work,{recursive:true});
  if(kind==='runtime') {
    const files=['runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
      'lib/'+native.tuple+'/libcangjie-runtime.a'];
    let archiveInputs;
    const original=await fs.readFile(path.join(install,RUNTIME_INPUTS)).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
    const artifacts=[];
    for(const [index,rel] of files.entries()) {
      const file=path.join(install,rel),bytes=await fs.readFile(file);
      const stamps=[...new Set([...bytes.toString('latin1').matchAll(/CJRT-COMMIT:([0-9a-z_-]+)/g)].map(m=>m[1]))];
      const names=await nativeSymbolRows(file,{platform,runtime:index===0,defined:true});
      const masks=names.filter(name=>name==='g_cjLoadBadMask').length;
      console.log('RUNTIME_PAIR_ASSERTION_REACHED '+JSON.stringify({file,stamps,masks}));
      const sourceStamp=stamps.length===1&&/^src-[0-9a-f]{64}$/.test(stamps[0]);
      if(!sourceStamp&&(stamps.length!==1||stamps[0]!==commit))throw new Error('RUNTIME_PAIR_SOURCE_STAMP');
      if(sourceStamp||original) {
        if(!original)throw new Error('RUNTIME_SOURCE_RECORD_REQUIRED');
        archiveInputs=await runtimeInputsForArtifact(install,{path:rel,sha256:await fileDigest(file)},
          {repository:request.sourceRepository??request.repository,commit,stamp:'CJRT-COMMIT:'+stamps[0],configuration:request.configuration});
      }
      if(index===0?masks!==1:masks<1)throw new Error('RUNTIME_COLOUR_PAIR');
      artifacts.push({path:rel,sha256:await fileDigest(file)});
    }
    if(archiveInputs)await fs.writeFile(path.join(work,RUNTIME_INPUTS),original);
    if(!archiveInputs&&request.repository)await atomicJson(path.join(work,RUNTIME_INPUTS),{
      source:{status:'resolved',repository:request.sourceRepository??request.repository,commit},embedded_stamp:'CJRT-COMMIT:'+commit,
      build:{configuration:request.configuration},artifacts});
  } else if(kind==='llvm') {
    if(!request.librarySha256||!request.tools)throw new Error('NATIVE_LLVM_ORIGINAL_INPUT_REQUIRED');
    const root=path.join(install,'third_party/llvm');
    const env={...process.env,[native.loader]:[path.join(root,native.llvmDirectory),path.join(install,'tools/lib'),
      process.env[native.loader]].filter(Boolean).join(path.delimiter)};
    facts.llvm=await verifyLlvmDylib({directory:path.join(root,native.llvmDirectory),llvmSha:commit,sha256:request.librarySha256,
      platform,tools:request.tools,probeDirectory:path.join(work,'capi'),env,jobs:request.jobs});
    await verifyInstalledBitcodeReaders({install,platform,work,commit});
    const buildInputs=request.buildResult||path.join(install,'BUILD-INPUTS.json');
    const original=await fs.readFile(buildInputs,'utf8').then(JSON.parse).catch(error=>{if(error.code==='ENOENT'&&!request.buildResult)return null;throw error;});
    if(original?.windowsToolchain)facts.windowsToolchain=original.windowsToolchain;
    if(original?.nativeShim||original?.configuration?.shimSource){
      if(original.commits?.llvm!==commit)throw Error('NATIVE_SHIM_LLVM_SOURCE');
      await readInstalledNativeShim({install,facts:original});
    }
    const shim=path.join(root,'fixed-llc/cjselfhost_llvmshim.o');
    const defined=await nativeSymbolRows(shim,{platform,defined:true});
    const expected=['LLVMGlobalObjectAddStringAttribute'];
    // The exact exported shim API is supplied by the fixed compiler source;
    // ordinary LLVM reader functions cannot replace the self-host shim object.
    const exported=defined.filter(name=>name.startsWith('LLVMSelfhost')||name==='LLVMGlobalObjectAddStringAttribute');
    console.log('LLVM_SHIM_ASSERTION_REACHED '+JSON.stringify({shim,exported}));
    if(!exported.includes(expected[0])||!exported.some(name=>name.startsWith('LLVMSelfhost')))throw new Error('LLVM_SHIM_API');
    if(!request.python)throw new Error('CJDB_PYTHON_NATIVE_INPUT_REQUIRED');
    if(original?.python?.configured&&request.python.record) {
      Object.assign(facts,await verifyRelocatedCjdbPython({install,original,python:request.python,platform,execute}));
    } else {
      facts.pythonConfiguration=await verifyCjdbPythonConfiguration(request.python.root,request.python.lldbBuild,execute,platform,request.python.executable);
      facts.pythonInstallation=await verifyCjdbPythonInstallation(request.python.root,root,execute,platform,request.python.executable);
      facts.pythonSource=await pythonSourceInputs({...request.python,nativeRoot:root,platform,selected:facts.pythonConfiguration.selected});
    }
    facts.artifacts=await Promise.all(['third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary,'tools/bin/cjdb'+native.exe,'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o']
      .map(async relative=>({path:relative,sha256:await fileDigest(path.join(install,relative))})));
  } else if(kind==='ast') {
    facts.astInstallation=await readInstalledNativeAst({install,buildResult:request.buildResult,platform,commit,llvmCommit:request.llvmCommit});
  } else if(kind==='llvm-readers') {
    await verifyInstalledBitcodeReaders({install,platform,work,commit});
  } else throw new Error('NATIVE_INPUT_KIND '+kind);
  await atomicJson(path.join(work,'native-input-result.json'),{kind,install,commit,platform,rc:0,
    source:{repository:request.repository,commit},configuration:request.configuration,...facts});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{await checkNativeInput(JSON.parse(process.argv[2]));}
  catch(error){console.error(error.stack);process.exitCode=Number.isInteger(error.code)?error.code:1;}
}
