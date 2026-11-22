#!/usr/bin/env zx

import fs from 'node:fs/promises';
import {nativeLlvmInputs} from './native-llvm-inputs.mjs';
import {hostPlatform} from './host-toolchain-pin.mjs';
import {developmentSdkPair,nativePair,resolveRuntimeSource} from './runtime-pin.mjs';

// Select before checkout, on the managed component route only. The native
// producer and SDK graph already consume these handoff variables.
const args=process.argv.slice(process.argv.findIndex(arg=>arg.endsWith('load_runtime_pin.mjs'))+1);
if(args.length && (args.length!==2 || args[0]!=='--development-sdk'))throw Error('usage: load_runtime_pin.mjs [--development-sdk OUTPUT]');
if(!args.length && !process.env.GITHUB_ENV)throw Error('GITHUB_ENV is required');
const env={...process.env};
if(args.length && env.CJCJ_SRCBUILD_TARGET==='linux-x64' && hostPlatform()==='linux_x86_64'
  && env.RUNTIME_NATIVE_PAIR==='1' && (env.RUNTIME_TARGET||'native')==='native'
  && (env.RUNTIME_BUILD_TYPE||'release')==='release' && !nativePair(env,{requireHost:false})
  && !env.CJCJ_RUNTIME_REF_OVERRIDE && !env.CJCJ_BOOTSTRAP_RUNTIME_PIN) {
  const pair=developmentSdkPair(env.CJCJ_SRCBUILD_TARGET);
  if(env.CJCJ_NATIVE_HOST_VERSION && env.CJCJ_NATIVE_HOST_VERSION!==pair.hostVersion)throw Error('LINUX_X64_SDK_HOST_VERSION');
  Object.assign(env,{CJCJ_NATIVE_RUNTIME_REF:pair.runtime,CJCJ_NATIVE_LLVM_REF:pair.llvm,CJCJ_NATIVE_HOST_VERSION:pair.hostVersion});
}
const pins = await resolveRuntimeSource(env);
const environment = [
  `CJCJ_NATIVE_LLVM_REF=${nativeLlvmInputs(env).CJCJ_NATIVE_LLVM_REF}`,
  `CJCJ_NATIVE_RUNTIME_REF=${pins.runtimeRef}`,
  `RUNTIME_VERSION=${pins.RUNTIME_VERSION}`,
  `RUNTIME_SRC_URL=${pins.sourceUrl}`,
];
if (pins.overrideRef) {
  environment.push(`CJCJ_RUNTIME_REF_OVERRIDE=${pins.overrideRef}`);
  environment.push('CJCJ_ALLOW_RUNTIME_OVERRIDE=true');
}
if (pins.nativePair) {
  if(pins.nativePair.hostVersion) environment.push(`CJCJ_NATIVE_HOST_VERSION=${pins.nativePair.hostVersion}`);
}
const text=environment.join('\n')+'\n';
if(args.length)await fs.writeFile(args[1],text,{flag:'wx'});
else await fs.appendFile(process.env.GITHUB_ENV,text);
console.log(`[runtime] selected ref=${pins.runtimeRef} pin=${pins.pinRef} `
  + `override=${pins.overrideRef || '<none>'} native_pair=${pins.nativePair?.llvm || '<none>'}`);
