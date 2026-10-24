#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {command,withProcessCancellation} from './sdk-flow.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {assertStdBarriers} from '../srcbuild/lib/assert-std-barriers.mjs';
export async function assertFinalStdInput({sdk,std,runtime,host,platform,work,signal}) {
  if(!sdk||!std||!runtime||!host||!work)throw new Error('FINAL_STD_CONSUMER_INPUT_REQUIRED');
  const native=sdkPlatform(platform);
  await assertStdBarriers({coreLib:path.join(std,'lib',native.tuple,'libcangjie-std-core.a'),
    runtime:path.join(runtime,'runtime/lib',native.tuple,'libcangjie-runtime'+native.shared),
    hostRuntime:path.join(host,'runtime/lib',native.tuple,'libcangjie-runtime'+native.shared),
    signal, target:{spec:{os:native.os==='win32'?'windows':native.os,arch:native.arch==='arm64'?'aarch64':'x86_64',key:platform}}});
  if(native.os!=='linux'||native.arch!=='x64') {
    console.log(`INSTALLED_STRING_NOT_RUN platform=${platform} scope=linux-x64; native symbol obligations completed`);
    return;
  }
  await command([process.execPath,fileURLToPath(new URL('./sdk-installed-string.mjs',import.meta.url)),
    '--sdk',sdk,'--std',std,'--runtime',runtime,'--platform',platform,'--work',work],{signal});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const {values}=parseArgs({options:Object.fromEntries(['sdk','std','runtime','host','platform','work'].map(k=>[k,{type:'string'}]))});
    await withProcessCancellation(signal=>assertFinalStdInput({...values,signal}));
  }catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
