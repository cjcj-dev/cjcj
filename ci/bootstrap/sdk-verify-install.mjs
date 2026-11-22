#!/usr/bin/env zx
// Shared installed and unpacked public compiler gate. Never call on H/H1.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {verifyInstalledRegex} from './sdk-installed-regex.mjs';
import {verifyInstalledJava} from './sdk-installed-java.mjs';
import {consumeInstalledLspMacro} from '../release/installed-lsp-macro.mjs';
import {helloInstall} from './sdk-hello.mjs';
import {macroInstall,precompiledStdxMacros} from './sdk-installed-macros.mjs';
import {readJson,withProcessCancellation} from './sdk-flow.mjs';
import {assertFinalStdInput} from './sdk-final-std.mjs';
import {verifyInstalledLanguage} from './sdk-installed-language.mjs';
import {verifyCompiler} from './compiler_identity.mjs';
import {compilerExecutionRoot} from './sdk-targets.mjs';
export async function verifyInstall({sdk,work,platform,finalStd=false,cjpm=true,precompiledStdx=false,packageRegex=false,java=false,javaHome,lspMacro=false}) {
 sdk=path.resolve(sdk);work=path.resolve(work);
 await verifyCompiler(sdk);
 if(java)await verifyInstalledJava(sdk,work,javaHome);
 if(packageRegex)await verifyInstalledRegex({sdk,work:path.join(work,'regex'),platform});
 if(finalStd) {
  const metadata=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  if(!['stage2-target-sdk','stage3','source-build'].includes(metadata.phase))throw new Error('FINAL_STD_INSTALL_PHASE');
  const execution=compilerExecutionRoot(sdk,metadata.selection);
  if(platform.startsWith('linux_'))await verifyInstalledLanguage({sdk,work,platform,host:execution});
  // Compare the host runtime copied into this installation. The producer's
  // bootstrap path is provenance and may be unavailable after relocation.
  await withProcessCancellation(signal=>assertFinalStdInput({sdk,std:sdk,runtime:sdk,
   host:path.join(sdk,'.host'),platform,work:path.join(work,'string'),signal}));
 }
 await helloInstall({sdk,work:path.join(work,'ordinary'),platform,cjpm});
 if(precompiledStdx)await precompiledStdxMacros({sdk,work:path.join(work,'precompiled-stdx'),platform});
 if(lspMacro)await consumeInstalledLspMacro({sdk,work,platform});
 return macroInstall({sdk,work:path.join(work,'macros'),platform});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const {values}=parseArgs({options:{sdk:{type:'string'},work:{type:'string'},platform:{type:'string'},'final-std':{type:'boolean'},'compiler-only':{type:'boolean'},'precompiled-stdx':{type:'boolean'},'package-regex':{type:'boolean'},java:{type:'boolean'},'java-home':{type:'string'},'lsp-macro':{type:'boolean'}}});
  if(!values.sdk||!values.work||!values.platform)throw new Error('usage: sdk-verify-install.mjs --sdk INSTALL --work PRIVATE --platform TUPLE');
  await verifyInstall({...values,javaHome:values['java-home'],finalStd:values['final-std'],cjpm:!values['compiler-only'],precompiledStdx:values['precompiled-stdx'],packageRegex:values['package-regex'],lspMacro:values['lsp-macro']});
 }catch(e){console.error(e.stack);process.exitCode=Number.isInteger(e.rc)&&e.rc!==0?e.rc:1;}
}
