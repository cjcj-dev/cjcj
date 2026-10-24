#!/usr/bin/env zx
import path from 'node:path';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {sdkPlatform} from './sdk-platform.mjs';
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
