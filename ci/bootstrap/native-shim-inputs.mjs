// Ordinary native shim inputs/results carried by BUILD-INPUTS.json.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest,readJson} from './sdk-flow.mjs';

export async function nativeHostFlatc(install, astInstallation) {
 const names=Object.keys(astInstallation?.files||{}).filter(name=>/^third_party\/flatbuffers\/bin\/flatc(?:\.exe)?$/.test(name));
 if(names.length!==1)throw Error('NATIVE_SHIM_HOST_FLATC');
 const relative=names[0],file=path.join(install,relative),record=astInstallation.files[relative];
 if(await fileDigest(file)!==record.sha256)throw Error('NATIVE_SHIM_HOST_FLATC_BYTES');
 return {file,path:relative,sha256:record.sha256};
}

export async function readInstalledNativeShim({install,facts,objectFile}) {
 facts??=await readJson(path.join(install,'share/cjcj/build-inputs/native-build.json'))
  .catch(error=>{if(error.code!=='ENOENT')throw error;return readJson(path.join(install,'BUILD-INPUTS.json'));});
 const shim=facts?.nativeShim;
 if(!shim||shim.source?.commit!==facts.commits?.shim||!/^[a-f0-9]{40}$/.test(shim.source?.commit||'')||
    shim.compiler?.commit!==facts.commits?.compiler||shim.llvm?.commit!==facts.commits?.llvm)
  throw Error('NATIVE_SHIM_SOURCE_PAIR');
 const object='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
 if(shim.object?.path!==object)throw Error('NATIVE_SHIM_OBJECT_PATH');
 const record=shim.object,file=objectFile||path.join(install,object),stat=await fs.lstat(file);
 if(!stat.isFile()||!stat.size||stat.size!==record.bytes||await fileDigest(file)!==record.sha256)
  throw Error('NATIVE_SHIM_INSTALLED_BYTES '+object);
 return shim;
}

// Both public preparation and the compiler producer select the same ordinary
// object. A separate install changes only compiler-owned glue, never N's pair.
export async function compilerNativeShim({install, nativeInstall, compilerCommit}) {
 const shim=await readInstalledNativeShim({install:install||nativeInstall});
 if(shim.source.commit!==compilerCommit)throw Error('NATIVE_SHIM_COMPILER_SOURCE '+shim.source.commit+' != '+compilerCommit);
 if(install) {
  const library=shim.configuration?.llvmLibrary;
  let originalRequired=true;
  if(library) {
   const relative='third_party/llvm/lib/libLLVM-15.so';
   if(process.platform!=='linux'||library.file!==relative||library.sha256!==await fileDigest(path.join(nativeInstall,relative)))throw Error('NATIVE_SHIM_LLVM_LIBRARY');
   const exists=file=>fs.lstat(file).then(()=>true,e=>{if(e.code==='ENOENT')return false;throw e;});
   originalRequired=await exists(path.join(nativeInstall,'BUILD-INPUTS.json'))||
     await exists(path.join(nativeInstall,'share/cjcj/build-inputs/native-build.json'));
  }
  if(originalRequired) {
   const original=await readInstalledNativeShim({install:nativeInstall});
   if(shim.llvm.commit!==original.llvm.commit||shim.compiler.commit!==original.compiler.commit)
    throw Error('NATIVE_SHIM_DEPENDENCY_PAIR');
  }
 }
 return shim;
}
