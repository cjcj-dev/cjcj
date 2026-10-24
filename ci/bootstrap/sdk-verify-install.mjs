#!/usr/bin/env zx
// Shared installed and unpacked public compiler gate. Never call on H/H1.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {helloInstall} from './sdk-hello.mjs';
import {macroInstall} from './sdk-installed-macros.mjs';
import {readJson,withProcessCancellation} from './sdk-flow.mjs';
import {assertFinalStdInput} from './sdk-final-std.mjs';
import {verifyInstalledLanguage} from './sdk-installed-language.mjs';
import {verifyCompiler} from './compiler_identity.mjs';
export async function verifyInstall({sdk,work,platform,finalStd=false,cjpm=true}) {
 await verifyCompiler(sdk);
 if(finalStd) {
  const metadata=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  if(!['stage2-target-sdk','stage3','source-build'].includes(metadata.phase))throw new Error('FINAL_STD_INSTALL_PHASE');
  if(platform.startsWith('linux_'))await verifyInstalledLanguage({sdk,work,platform,host:path.join(sdk,'.host')});
  await withProcessCancellation(signal=>assertFinalStdInput({sdk,std:sdk,runtime:sdk,
   host:path.join(sdk,'.host'),platform,work:path.join(work,'string'),signal}));
 }
 await helloInstall({sdk,work:path.join(work,'ordinary'),platform,cjpm});
 return macroInstall({sdk,work:path.join(work,'macros'),platform});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const {values}=parseArgs({options:{sdk:{type:'string'},work:{type:'string'},platform:{type:'string'},'final-std':{type:'boolean'},'compiler-only':{type:'boolean'}}});
  if(!values.sdk||!values.work||!values.platform)throw new Error('usage: sdk-verify-install.mjs --sdk INSTALL --work PRIVATE --platform TUPLE');
  await verifyInstall({...values,finalStd:values['final-std'],cjpm:!values['compiler-only']});
 }catch(e){console.error(e.stack);process.exitCode=Number.isInteger(e.rc)&&e.rc!==0?e.rc:1;}
}
