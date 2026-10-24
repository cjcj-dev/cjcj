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
