#!/usr/bin/env zx
// The verifier calls the real native LLVM C API on every supported runner.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {selectBuildJobs} from '../build-resources.mjs';
import {execute, fileDigest, readJson, atomicJson, canonical, objectId, reject} from './sdk-io.mjs';
import {privateRoot} from './sdk-flow.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {verifyEntryFormat} from './sdk-entry-producer.mjs';
const source = fileURLToPath(new URL('./native-qualification/', import.meta.url));

export async function nativeCapiProbe({platform, tools, directory, jobs, env=process.env}) {
  const native = sdkPlatform(platform);
  if (process.platform !== native.os || process.arch !== native.arch)
    reject('VERIFIER_PLATFORM', platform, 'actual native runner required');
  const inputs = {};
  for (const name of ['cmake', 'clang++', 'ninja']) {
    const tool = tools[name];
    if (!tool || await fileDigest(tool.path) !== tool.sha256) reject('TOOL_IDENTITY', name, 'frozen verifier tool required');
    inputs[name] = tool;
  }
  if (tools.launcher) {
    if (await fileDigest(tools.launcher.path) !== tools.launcher.sha256) reject('TOOL_IDENTITY', 'launcher', 'frozen verifier tool required');
    inputs.launcher = tools.launcher;
  }
  const files = Object.fromEntries(await Promise.all(['CMakeLists.txt', 'capi.cpp'].map(async rel => [rel, await fileDigest(path.join(source, rel))])));
  const identity = {schema:'sdk-native-capi-producer-v1', platform, tools:inputs, files};
  const root = path.join(directory, objectId(identity));
  await privateRoot(root); await fs.mkdir(root, {recursive:true});
  const binary = path.join(root, 'cjcj-llvm-capi' + native.exe);
  const build = path.join(root, 'build');
  await execute(inputs.cmake.path, ['-G','Ninja','-S',source,'-B',build,'-DCMAKE_BUILD_TYPE=Release',
    `-DCMAKE_CXX_COMPILER=${inputs['clang++'].path}`,`-DCMAKE_MAKE_PROGRAM=${inputs.ninja.path}`,
    ...(inputs.launcher ? [`-DCMAKE_CXX_COMPILER_LAUNCHER=${inputs.launcher.path}`] : [])],{env});
  await execute(inputs.cmake.path, ['--build',build,'--config','Release','--parallel',String(await selectBuildJobs(jobs,env))],{env});
  await fs.copyFile(path.join(build,path.basename(binary)),binary); await fs.chmod(binary,0o755);
  await verifyEntryFormat(binary,platform);
  const sha256=await fileDigest(binary);
  await atomicJson(path.join(root,'probe-inputs.json'),{identity,sha256});
  return {binary,identity,sha256};
}
export async function verifyLlvmDylib({directory, llvmSha, sha256, platform, tools, probeDirectory, env, jobs}) {
  const library = path.join(directory, sdkPlatform(platform).llvmLibrary);
  // Native CMake installs the library directly. Source and bytes are checked
  // against the caller's fixed input; target registration is observed below.
  if (!/^[a-f0-9]{40}$/.test(llvmSha || '')) reject('LLVM_DYLIB_SOURCE',platform,'full LLVM source commit required');
  if (!/^[a-f0-9]{64}$/.test(sha256 || '') || await fileDigest(library) !== sha256)
    reject('LLVM_DYLIB_SHA256',platform,'LLVM_DYLIB_SHA256_MISMATCH');
  const stamps = new Set([...((await fs.readFile(library)).toString('latin1')).matchAll(/CJLLVM-COMMIT:([0-9a-z-]+)/g)].map(match => match[1]));
  if (stamps.size !== 1 || !stamps.has(llvmSha)) reject('LLVM_DYLIB_STAMP', platform, 'LLVM_DYLIB_SOURCE_STAMP_MISMATCH');
  await verifyEntryFormat(library,platform);
  const probe = await nativeCapiProbe({platform,tools,directory:probeDirectory,jobs,env});
  console.log(`LLVM_NATIVE_CAPI_PROBE_READY ${canonical({binary:probe.binary,sha256:probe.sha256}).trim()}`);
  const result = await execute(probe.binary,[library],{env});
  const observed = JSON.parse(result.stdout);
  console.log(`LLVM_NATIVE_CAPI_OBSERVED ${canonical(observed).trim()}`);
  if (await fs.realpath(observed.loaded) !== await fs.realpath(library) || observed.targets !== 15
    || observed.context_call !== 'ok' || await fileDigest(observed.loaded) !== sha256)
    reject('LLVM_DYLIB_LOADED_ORIGIN', platform, 'actual C API result differs from the original library');
  if (canonical(observed.lookups?.map(row => [row.rc, row.name])) !== canonical([[0,'x86-64'],[0,'arm'],[0,'aarch64']]))
    reject('LLVM_DYLIB_TARGET_LOOKUP', platform, `actual registered target lookup failed: ${canonical(observed.lookups).trim()}`);
  const evidence = {...observed,sha256,llvm_sha:llvmSha,probeSha256:probe.sha256};
  console.log(`LLVM_NATIVE_CAPI_VERIFIED ${canonical(evidence).trim()}`);
  return evidence;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 3) throw new Error('usage: sdk-native-capi.mjs FROZEN_REQUEST.json');
    await verifyLlvmDylib(await readJson(process.argv[2]));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
