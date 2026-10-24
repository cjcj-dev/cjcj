#!/usr/bin/env zx
// Repackage one verified native installation; never overlay an official SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isMain, cliArgs} from '../entry-common.mjs';
import {unpackNativeSdk} from './receive_native_sdk.mjs';
import {verifyNativeRelease} from './verify_native_release.mjs';
import {releaseSelection} from './native-release-inputs.mjs';
import {archiveInstall, privateRoot} from '../bootstrap/sdk-flow.mjs';
import {writePlatformSums} from './package_checksums.mjs';
export async function composeNativePackage(env = process.env) {
  for (const key of ['NATIVE_SDK_ARTIFACT_DIR', 'NATIVE_SDK_INSTALL_DIR', 'RELEASE_PLATFORM',
    'CJCJ_NATIVE_SDK_VERSION', 'CJCJ_RELEASE_SOURCE_SHA', 'RUNTIME_REF', 'FINAL_STD_DIR', 'RELEASE_DIST'])
    if (!env[key]) throw new Error(key + ' required');
  const platform = env.RELEASE_PLATFORM, version = env.CJCJ_NATIVE_SDK_VERSION;
  if (!/^[A-Za-z0-9][A-Za-z0-9.+_-]*$/.test(version)) throw new Error('NATIVE_RELEASE_VERSION');
  const {target, release} = releaseSelection(platform, env.RELEASE_KEY);
  if (env.RELEASE_LLVM_PLATFORM && env.RELEASE_LLVM_PLATFORM !== target.spec.llvmPlatform) throw new Error('NATIVE_RELEASE_LLVM_PLATFORM');
  if (env.RELEASE_RUNTIME_TUPLE && env.RELEASE_RUNTIME_TUPLE !== target.spec.runtimeTuple) throw new Error('NATIVE_RELEASE_RUNTIME_TUPLE');
  const dist = await privateRoot(env.RELEASE_DIST);
  await fs.mkdir(dist, {recursive: true});
  const {sdk} = await unpackNativeSdk(env.NATIVE_SDK_ARTIFACT_DIR, env.NATIVE_SDK_INSTALL_DIR, platform, env);
  const options = {sdk, platform, version, sourceSha: env.CJCJ_RELEASE_SOURCE_SHA, runtimeRef: env.RUNTIME_REF,
    releaseKey: env.RELEASE_KEY, std: env.FINAL_STD_DIR, crossRoot: env.CROSS_STD_DIR, work: path.join(dist, 'installed-check')};
  await verifyNativeRelease(options, env);
  const stem = `cjcj-${version}-${release.archiveKey}`;
  const archive = path.join(dist, stem + '.' + target.spec.archiveFormat);
  const check = fileURLToPath(new URL('./verify_native_release.mjs', import.meta.url));
  const args = ['--sdk', '${install}', '--platform', platform, '--version', version,
    '--source-sha', options.sourceSha, '--runtime-ref', options.runtimeRef,
    '--release-key', release.key, '--std', options.std, '--cross-root', options.crossRoot || '', '--work', '${work}'];
  const result = await archiveInstall({install: sdk, archive, format: target.spec.archiveFormat,
    test: {commands: [{argv: [process.execPath, check, ...args],
      env: {CROSS_STD_ARTIFACTS: env.CROSS_STD_ARTIFACTS || '[]', CROSS_STD_ARTIFACT: env.CROSS_STD_ARTIFACT || '', CROSS_STD_TUPLE: env.CROSS_STD_TUPLE || ''}}]},
    vars: {work: path.join(dist, 'relocated-check')}, records: []});
  await fs.copyFile(path.join(sdk, 'RELEASE-MANIFEST.jsonl'), path.join(dist, stem + '.RELEASE-MANIFEST.jsonl'));
  writePlatformSums({dist, version, platform: release.archiveKey});
  console.log(`NATIVE_RELEASE_ARCHIVE ${result.archive} sha256=${result.sha256}`);
  return result;
}
if (isMain(import.meta.url)) {
  try { await composeNativePackage(); }
  catch (error) { console.error(error.stack); process.exitCode = error.rc || error.exitCode || 1; }
}
