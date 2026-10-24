#!/usr/bin/env zx
// Complete the original runtime gate with independent build/language SDKs.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertLanguageState,GC_UNIT_LANGUAGE_DONE} from '../../build/srcbuild/gc-unit-gate.mjs';

const entry = fileURLToPath(import.meta.url);
const entryIndex = process.argv.findIndex(value => path.resolve(value) === entry);
const args = process.argv.slice(entryIndex + 1);
if (args[0]?.startsWith('--') && args[0] !== '--build-sdk') {
  console.error(`COLOUR_RT_GATE_INTERFACE unsupported=${args[0]}`);
  process.exit(2);
}
const buildSdkMode = args[0] === '--build-sdk';
if (buildSdkMode) args.shift();
if (args.length !== 4) {
  console.error('usage: gate_colour_runtime.mjs [--build-sdk] RUNTIME_SOURCE SDK NEW_PRIVATE_DIR RUNTIME_INSTALL');
  process.exit(2);
}
const source = fs.realpathSync(args[0]);
const sdkInput = fs.realpathSync(args[1]);
const active = path.resolve(args[2]);
const installed = fs.realpathSync(args[3]);
const {hostPlatform} = await import('../host-toolchain-pin.mjs');
const {sdkPlatform} = await import('../bootstrap/sdk-platform.mjs');
const platform = process.env.PLATFORM_TUPLE || hostPlatform();
const native = sdkPlatform(platform);
if (native.os !== 'linux') throw new Error('COLOUR_RT_GATE_PLATFORM requires Linux');
// Every subprocess inherits a zero soft/hard core limit. Preserve its raw rc.
async function run(command, commandArgs, env = process.env, capture = false) {
  const result = await $({env, stdio: capture ? 'pipe' : 'inherit', verbose: false, nothrow: true})
    `ulimit -c 0; exec ${command} ${commandArgs}`;
  if (result.exitCode !== 0) process.exit(result.exitCode);
  return result.stdout;
}

// Consume the normal installation and its selected CMake build directly.
// Strip/install transformations do not require an unstripped publication copy.
const target=path.join(installed,'runtime/lib',native.tuple);
let env={...process.env};delete env.GCV2_RUNTIME_CONFIG;
fs.mkdirSync(active,{recursive:true});
const status=path.join(active,'gate.status');fs.rmSync(status,{force:true});fs.rmSync(active+'.env',{force:true});
const languageSdk = sdkInput;
const {compilerRuntimeDirectory}=await import('../../build/lib/runtime-split.mjs');
const {buildConfig}=await import('../../build/lib/config.mjs');
const {cleanSdkEnvironment}=await import('../bootstrap/sdk-platform.mjs');
const configObject=buildConfig({workspace:active,consumerSdk:languageSdk,targetKey:platform === 'linux_aarch64' ? 'linux-aarch64' : 'linux-x64'});
const hostSdk=path.join(languageSdk,'.host');
const host=compilerRuntimeDirectory({sdk:languageSdk,hostSdk,target:configObject.target});
for(const name of ['libcangjie-runtime.so','libboundscheck.so'])
  await run('cmp',[path.join(target,name),path.join(languageSdk,'runtime/lib',native.tuple,name)],env);
env={...cleanSdkEnvironment(languageSdk,platform,env),
  GC_UNIT_LANGUAGE_SDK:languageSdk,GC_UNIT_CJC_RUNTIME_LIB_DIR:host,
   GC_UNIT_RUNTIME_TUPLE:native.tuple,
   GC_UNIT_CJC_RUNTIME_TUPLE:configObject.target.spec.hostRuntimeTuple||configObject.target.spec.runtimeTuple,
  GC_UNIT_COLOUR_HOST_RUNTIME:path.join(hostSdk,`runtime/lib/${native.tuple}/libcangjie-runtime.so`),
  CANGJIE_HOME:languageSdk,CJC:path.join(languageSdk,'bin/cjc'),
  GCV2_RUNTIME_LIB_DIR:target,GCV2_RUNTIME_OUTPUT_ROOT:path.join(source,'runtime/CMakebuild/runtime-staging'),
  GCV2_RUNTIME_BUILD_DIR:path.join(source,'runtime/CMakebuild'),GC_UNIT_GATE_STATUS:status,
  GC_UNIT_GATE_LANGUAGE_TESTS:'all',GC_UNIT_OUT:active,
};
// Original complete gate executes both consumers and writes this run result.
await run('bash', [path.join(source, 'runtime/tests/gc_unit/gate_gc_unit.sh')], env);

assertLanguageState(status,GC_UNIT_LANGUAGE_DONE,'release.gc_unit_language');
// The packaging step consumes exactly the installed pair exercised here.
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
fs.writeFileSync(active+'.env', `GCV2_RUNTIME_LIB_DIR=${quote(target)}\nGC_UNIT_LANGUAGE_SDK=${quote(languageSdk)}\n`);
