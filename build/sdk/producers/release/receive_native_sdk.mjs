#!/usr/bin/env zx
// Consume the ordinary package-install archive emitted by sdk-build-target.yml.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isMain, cliArgs} from '../../../../ci/entry-common.mjs';
import {zipCommand,checkArchiveFormat} from '../../../../ci/bootstrap/sdk-archive.mjs';
import {command, privateRoot, fileDigest, readJson} from '../../../../ci/bootstrap/sdk-flow.mjs';
import {getBuildTarget} from '../../../lib/build-target.mjs';
import {selectInstalledColourSdk} from '../../../../ci/prepare-colour-sdk.mjs';
export async function unpackNativeSdk(input, destination, targetKey, env = process.env) {
  const target = getBuildTarget(targetKey);
  // Both public build/cli package and srcbuild package-install archive the
  // same installation. Keep their existing names and validate package facts.
  const prefix = 'cangjie-sdk-' + target.spec.sdkName + '-';
  const archives = (await fs.readdir(input)).filter(name => name.startsWith(prefix) && /\.(tar\.gz|zip)$/.test(name));
  if (archives.length !== 1) throw new Error(`NATIVE_SDK_ARCHIVE_COUNT ${archives.length}`);
  const archive = path.join(input, archives[0]);
  const sidecar = (await fs.readFile(archive+'.sha256', 'utf8')).trim();
  if (sidecar !== `${await fileDigest(archive)}  ${archives[0]}`) throw new Error('NATIVE_SDK_ARCHIVE_DIGEST');
  const format=target.spec.archiveFormat;
  if(!archive.endsWith('.'+format))throw Error('NATIVE_SDK_ARCHIVE_EXTENSION '+format);
  await checkArchiveFormat(archive,format);
  destination = await privateRoot(destination);
  // A new extraction never overwrites an earlier consumer or failed attempt.
  await fs.mkdir(destination);
  await command(format==='zip'?zipCommand('extract',archive,destination):['tar','-xzf',archive,'-C',destination]);
  const sdk = path.join(destination, 'cangjie');
  const facts = await readJson(path.join(sdk, 'BUILD-MANIFEST.json'));
  if (facts.target !== target.spec.key || !(facts.consumption?.status === 'EXECUTED'
      || (target.spec.crossCompile && facts.consumption?.status === 'NOT_RUN' && facts.consumption.reason === 'HOST_CROSS_EXEC'))
      || facts.consumption.platform !== target.spec.llvmPlatform
      || (env.CJCJ_NATIVE_SDK_VERSION && facts.version !== env.CJCJ_NATIVE_SDK_VERSION))
    throw new Error('NATIVE_SDK_PACKAGE_INPUT_MISMATCH');
  return {sdk, facts, archive};
}
export async function receiveNativeSdk(input, destination, targetKey, env = process.env) {
  const {sdk} = await unpackNativeSdk(input, destination, targetKey, env);
  // Recheck actual installed compiler/runtime/std and ordinary/macro consumers.
  // Neither the sidecar nor the factual package manifest grants qualification.
  return selectInstalledColourSdk(sdk, env);
}
if (isMain(import.meta.url)) {
  try {
    const [input, destination, target, ...extra] = cliArgs;
    if (!input || !destination || !target || extra.length) throw new Error('usage: receive_native_sdk.mjs ARTIFACT NEW_PRIVATE_DIR TARGET');
    await receiveNativeSdk(input, destination, target);
  } catch (error) { console.error(error.stack); process.exitCode = error.rc || 1; }
}
