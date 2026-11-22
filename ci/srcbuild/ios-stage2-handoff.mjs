#!/usr/bin/env zx
// Preserve executable modes and SDK aliases without transporting a source tree.
import fs from 'node:fs/promises';
import path from 'node:path';
import {command, fileDigest, privateRoot, readJson} from '../bootstrap/sdk-flow.mjs';
import {verifyCompiler} from '../bootstrap/compiler_identity.mjs';
import {verifyStdBuildInputs} from '../bootstrap/stdlib-build.mjs';

const [mode, directory] = process.argv.slice(2);
const {CANGJIE_WORKSPACE: workspace, CJCJ_SRCBUILD_TARGET: target, GITHUB_RUN_ID: run,
  GITHUB_SHA: sourceSha, CJCJ_NATIVE_RUNTIME_REF: runtimeRef, RUNTIME_SRC_URL: runtimeUrl,
  SOURCE_SDK_VERSION: version, GITHUB_ENV: githubEnv} = process.env;
if (!['pack', 'restore'].includes(mode) || !directory || !workspace || target !== 'darwin-arm64'
    || !/^\d+$/.test(run || '') || ![sourceSha, runtimeRef].every(sha => /^[a-f0-9]{40}$/.test(sha || ''))
    || !runtimeUrl || /[\r\n]/.test(runtimeUrl)) throw Error('IOS_STAGE2_INPUTS');

const bootstrap = await privateRoot(path.resolve(workspace, 'native-bootstrap'));
const archive = path.resolve(directory, 'sdk-stage2.tar.gz');
const manifest = path.resolve(directory, 'sdk-stage2.json');
const identity = {run, sourceSha, target, runtimeRef, runtimeUrl};
const checkVersion = value => {
  if (!/^[A-Za-z0-9][A-Za-z0-9.+_-]*$/.test(value || '')) throw Error('IOS_STAGE2_VERSION');
};
async function checkStage(sdk) {
  const stage = await verifyCompiler(sdk);
  if (stage.phase !== 'stage2' || stage.platform !== 'darwin_aarch64' || stage.runtimeCommit !== runtimeRef)
    throw Error('IOS_STAGE2_LINEAGE');
  await verifyStdBuildInputs(sdk, stage.platform);
}
try {
  if (mode === 'pack') {
    checkVersion(version);
    await checkStage(path.join(bootstrap, 'sdk-stage2'));
    await fs.mkdir(path.dirname(archive), {recursive: true});
    await command(['tar', '-czf', archive, '-C', bootstrap, 'sdk-stage2']);
    await fs.writeFile(manifest, JSON.stringify({...identity, version, sha256: await fileDigest(archive)}) + '\n');
  } else {
    if (!githubEnv) throw Error('GITHUB_ENV required');
    const record = await readJson(manifest);
    for (const [key, value] of Object.entries(identity))
      if (record[key] !== value) throw Error('IOS_STAGE2_IDENTITY ' + key);
    checkVersion(record.version);
    if (record.sha256 !== await fileDigest(archive)) throw Error('IOS_STAGE2_ARCHIVE_BYTES');
    const sdk = path.join(bootstrap, 'sdk-stage2');
    if (await fs.lstat(sdk).catch(error => {if (error.code !== 'ENOENT') throw error;}))
      throw Error('IOS_STAGE2_DESTINATION_EXISTS');
    await fs.mkdir(bootstrap, {recursive: true});
    const pending = await fs.mkdtemp(path.join(bootstrap, '.ios-stage2-'));
    await command(['tar', '-xzf', archive, '-C', pending]);
    const unpacked = path.join(pending, 'sdk-stage2');
    await checkStage(unpacked);
    await fs.rename(unpacked, sdk);
    await fs.rmdir(pending);
    await fs.appendFile(githubEnv, 'SOURCE_SDK_VERSION=' + record.version + '\n');
  }
  console.log('IOS_STAGE2_HANDOFF ' + mode + ' ' + target + ' ' + runtimeRef);
} catch (error) {
  console.error(error.stack);
  process.exitCode = error.rc || 1;
}
