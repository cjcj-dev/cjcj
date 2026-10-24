#!/usr/bin/env zx
// Consume the existing native runtime producer's installation and original gate
// result. No build, stripping, status rewrite or qualification is done here.
import fs from 'node:fs/promises';
import {isDeepStrictEqual} from 'node:util';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {privateRoot, readJson} from './sdk-flow.mjs';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {checkNativeInput} from './sdk-native-input-check.mjs';
import {assertLanguageState, GC_UNIT_LANGUAGE_DEFERRED, GC_UNIT_LANGUAGE_DONE} from '../../build/srcbuild/gc-unit-gate.mjs';
export {nativePair} from '../runtime-pin.mjs';
export async function receiveNativeRuntime({root, sourceRoot, sourceRepository, configuration, platform, llvmCommit, runtimeCommit, hostVersion, work, gateStatus}) {
  root = await privateRoot(root);
  const native = sdkPlatform(platform);
  if (platform !== hostPlatform()) throw new Error('NATIVE_RUNTIME_CONSUMER_HOST');
  if (![llvmCommit,runtimeCommit].every(value=>/^[a-f0-9]{40}$/.test(value || '')) || !hostVersion)
    throw new Error('NATIVE_RUNTIME_CONSUMER_PAIR');
  const source = (await fs.readFile(path.join(root, 'SOURCE_SHA'), 'utf8')).trim();
  const facts = await readJson(path.join(root, 'NATIVE-INPUTS.json'));
  if (source !== runtimeCommit || facts.runtime_sha !== runtimeCommit || facts.paired_llvm_sha !== llvmCommit
      || facts.platform !== platform) throw new Error('NATIVE_RUNTIME_COMPONENT_IDENTITY');
  for (const relative of ['runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
    'runtime/lib/'+native.tuple+'/libboundscheck'+native.shared, 'lib/'+native.tuple+'/libcangjie-runtime.a'])
    if (!(await fs.stat(path.join(root,relative))).isFile()) throw new Error('NATIVE_RUNTIME_COMPONENT_MISSING ' + relative);
  if (native.os === 'linux') {
    const carried=path.join(root,'share/runtime-build');
    // A producing caller can name its actual runtime/ and current status.
    // Received archives use the normal carried inputs without reopening it.
    const runtime=gateStatus ? sourceRoot : path.join(sourceRoot||carried,'runtime');
    if(!runtime)throw new Error('NATIVE_RUNTIME_SOURCE_ROOT_REQUIRED');
    const status=gateStatus||path.join(runtime,'CMakebuild/gc-unit.status');
    const mode=facts.language_test_mode;
    if(!['defer','all','only'].includes(mode))throw new Error('NATIVE_RUNTIME_LANGUAGE_MODE');
    const fields=assertLanguageState(status,mode==='defer'?GC_UNIT_LANGUAGE_DEFERRED:GC_UNIT_LANGUAGE_DONE,'native.receive');
    if(fields.get('CPP_SUITE')!=='PASS')throw new Error('NATIVE_RUNTIME_CPP_RESULT');
    for(const directory of new Set([runtime,path.join(carried,'runtime')]))
      for(const member of ['tests/gc_unit/gate_gc_unit.sh','tests/gc_unit/language_toolchain.mjs',
        'CMakebuild/compile_commands.json'])await fs.access(path.join(directory,member));
    // Return the installed source root used by transport/SDK graph consumers.
    sourceRoot=carried;
    await fs.access(path.join(root,'runtime/include/schedule.h'));
  }
  const buildConfiguration={buildType:facts.build_type,version:facts.version,hostVersion,pairedLlvmCommit:llvmCommit};
  if(configuration&&!isDeepStrictEqual(configuration,buildConfiguration))throw new Error('NATIVE_RUNTIME_CONFIGURATION_CHANGED');
  await checkNativeInput({kind:'runtime',install:root,commit:runtimeCommit,sourceRepository,
    configuration:buildConfiguration,platform,work:path.join(work,'component-check')});
  console.log(`NATIVE_RUNTIME_COMPONENT_ACCEPTED runtime=${runtimeCommit} llvm=${llvmCommit} install=${root}`);
  return {install:root,buildResult:path.join(root,'NATIVE-INPUTS.json'),sourceRoot,
    configuration:buildConfiguration,
    verification:{},component:true};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await receiveNativeRuntime(JSON.parse(await fs.readFile(process.argv[2], 'utf8'))); }
  catch (error) { console.error(error.stack); process.exitCode=error.rc||error.exitCode||1; }
}
