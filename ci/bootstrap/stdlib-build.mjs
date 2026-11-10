#!/usr/bin/env zx
import path from 'node:path';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {sdkPlatform} from './sdk-platform.mjs';
import {isDeepStrictEqual} from 'node:util';
import {readSourcePins} from '../native-llvm-inputs.mjs';
export function stdDependencySources() {
 const {source}=readSourcePins();
 return {bounds:{repository:source.BOUNDS_SRC_URL,commit:source.BOUNDS_REF},
  pcre2:{repository:source.PCRE2_SRC_URL,commit:source.PCRE2_REF}};
}
export async function stdDependencyInputs(selected) {
 const expected=stdDependencySources(),result={};
 if(!selected||Object.keys(selected).sort().join(',')!=='bounds,pcre2')throw Error('STD_DEPENDENCY_INPUT_REQUIRED');
 for(const [name,pin] of Object.entries(expected)) {
  const row=selected[name];
  if(!row||row.repository!==pin.repository||row.commit!==pin.commit||!path.isAbsolute(row.root||''))
   throw Error('STD_DEPENDENCY_SOURCE '+name);
  const root=await fs.realpath(row.root);
  const required=name==='bounds'?['include/securec.h','src/securecutil.c']:['pcre2/CMakeLists.txt'];
  for(const rel of required)if(!(await fs.stat(path.join(root,rel))).isFile())throw Error('STD_DEPENDENCY_FILE '+name+'/'+rel);
  result[name]={root,...pin};
 }
 return result;
}
export async function prepareStdDependencies({source,dependencies,previous=[],records=[]}) {
 const selected=await stdDependencyInputs(dependencies);
 for(const [name,row] of Object.entries(selected)) {
  const destination=path.join(source,'stdlib/third_party',name==='bounds'?'boundscheck-v1.1.16':'pcre2');
  const fact={event:'std-dependency',name,source:row,destination};
  const present=await fs.lstat(destination).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  if(present) {
   if(present.isSymbolicLink()||!present.isDirectory()||!previous.some(old=>isDeepStrictEqual(old,fact)))
    throw Error('STD_DEPENDENCY_DESTINATION_EXISTS '+destination);
  } else {
   await fs.mkdir(path.dirname(destination),{recursive:true});
   await fs.cp(row.root,destination,{recursive:true,dereference:true,errorOnExist:true,force:false,filter:file=>path.basename(file)!=='.git'});
  }
  records.push(fact);console.log(JSON.stringify(fact));
 }
}
export async function verifyStdBuildInputs(sdk,platform=process.env.CJCJ_SDK_PLATFORM||'linux_x86_64') {
 const native=sdkPlatform(platform);
 for(const rel of [`lib/${native.tuple}/libcangjie-ast-support.a`,'schema/StdAstFormat.fbs',
  'include/flatbuffers/StdAstFormat_generated.h',`third_party/flatbuffers/bin/flatc${native.exe}`])
  if(!(await fs.stat(path.join(sdk,rel))).isFile())throw new Error('STD_AST_INPUT '+rel);
 return {sdk,platform:native};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const {values}=parseArgs({options:{sdk:{type:'string'},platform:{type:'string'}}});if(!values.sdk)throw new Error('--sdk required');await verifyStdBuildInputs(values.sdk,values.platform);}
 catch(e){console.error(e.message);process.exitCode=1;}
}
