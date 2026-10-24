#!/usr/bin/env zx
// Select the actual prepared header output or the actual installed native object.
import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {prepareCppHeaders} from '../../bootstrap/prepare_cpp_headers.mjs';
import {readInstalledNativeShim} from '../../bootstrap/native-shim-inputs.mjs';
export async function buildCompilerShim({cwd=process.cwd(),env=process.env}={}) {
 const selected={...env};
 for(const key of ['CPATH','CPLUS_INCLUDE_PATH','C_INCLUDE_PATH','OBJC_INCLUDE_PATH'])selected[key]='';
 const headers=env.CJCJ_BOOTSTRAP_CPP_SRC||env.CANGJIE_CPP_SRC;
 let object=env.CJCJ_LLVM_SHIM_O;
 const sdk=env.CJCJ_SRCBUILD_CONSUMER_SDK||(env.CANGJIE_WORKSPACE&&path.join(env.CANGJIE_WORKSPACE,'software/cangjie'));
 if(object||!headers) {
  try {
   // The same original producer facts validate either the installed pathname
   // or an explicitly supplied copy. No facts means compile the real source.
   if(!sdk)throw Error('SHIM_OBJECT_BUILD_INPUTS_REQUIRED');
   const shim=await readInstalledNativeShim({install:sdk,objectFile:object&&path.resolve(object)});
   object=object?path.resolve(object):path.join(sdk,shim.object.path);
  } catch(error) {
   console.log('SHIM_OBJECT_UNAVAILABLE '+error.message);object=undefined;
  }
 }
 if(object)selected.CJCJ_LLVM_SHIM_O=path.resolve(object);
 else {
  delete selected.CJCJ_LLVM_SHIM_O;
  const cpp=headers||path.join(cwd,'.srcbuild/cpp');
  if(!headers)await prepareCppHeaders(cpp,env.CJCJ_BOOTSTRAP_RUNTIME_PIN,selected);
  selected.CANGJIE_CPP_SRC=path.resolve(cpp);
 }
 await fs.mkdir(path.join(cwd,'.srcbuild'),{recursive:true});
 const argv=['--yes','zx@8',path.join(cwd,'runtime_shim/build_shim.mjs')];
 let executable='npx',arguments_=argv;
 if(process.platform==='win32') {
  const choices=[...(env.npm_execpath?[path.join(path.dirname(env.npm_execpath),'npx-cli.js')]:[]),
   path.join(path.dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),
   path.resolve(path.dirname(process.execPath),'../lib/node_modules/npm/bin/npx-cli.js')];
  let cli;for(const file of choices)if(await fs.stat(file).catch(()=>null)){cli=file;break;}
  if(!cli)throw Error('SHIM_BUILD_NPX_CLI_REQUIRED');
  executable=process.execPath;arguments_=[cli,...argv];
 }
 const logFile=path.join(cwd,'.srcbuild/shim-build.log');
 const log=await fs.open(logFile,'w');
 let result;
 try { result=spawnSync(executable,arguments_,{cwd,env:selected,stdio:['ignore',log.fd,log.fd]}); }
 finally { await log.close(); }
 await fs.writeFile(path.join(cwd,'.srcbuild/shim-build-command.json'),JSON.stringify({argv:[executable,...arguments_],cwd,rc:result.status,signal:result.signal},null,2));
 if(result.error)throw result.error;
 if(result.status!==0){const error=Error('SHIM_BUILD_FAILED rc='+result.status);error.rc=result.status??1;throw error;}
 const forbidden='used vendored prebuilt shim';
 let tail='';
 for await(const chunk of createReadStream(logFile,{encoding:'utf8'})) {
  const text=tail+chunk;
  if(text.includes(forbidden))throw Error('SHIM_BUILD_VENDORED');
  tail=text.slice(-(forbidden.length-1));
 }
 if(!(await fs.stat(path.join(cwd,'runtime_shim/cjselfhost_llvmshim.o'))).size)throw Error('SHIM_BUILD_EMPTY');
 return {rc:result.status};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try{await buildCompilerShim();}catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
