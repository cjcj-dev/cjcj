#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {installCrossRuntime} from '../../release/cross-runtime.mjs';
import {publishPaths, readJson} from '../../bootstrap/sdk-flow.mjs';
import {androidTuple, androidStdProvenance, androidStdRoots, readAndroidInputs} from '../lib/android-sdk.mjs';

const workspace = process.env.CANGJIE_WORKSPACE;
if (!workspace || process.env.CJCJ_SRCBUILD_TARGET !== 'linux-x64') throw Error('ANDROID_INSTALL_HOST');
const software = path.resolve(workspace, 'software');
const sdk = path.join(software, 'cangjie');
const src = path.join(software, 'final-std-android-aarch64');
const host = await readJson(path.join(sdk, 'STAGE-INPUTS.json'));
const runtimeRef = process.env.CJCJ_NATIVE_RUNTIME_REF;
if (!runtimeRef || host.runtimeCommit !== runtimeRef) throw Error('ANDROID_INSTALL_RUNTIME_PAIR');
const provenance = await fs.readFile(path.join(src, 'PROVENANCE.txt'), 'utf8');
if (!provenance.split('\n').includes('STD_SOURCE_COMMIT = ' + runtimeRef)) throw Error('ANDROID_INSTALL_STD_SOURCE');

const pending = await fs.mkdtemp(path.join(software, '.android-install-'));
try {
  for (const rel of androidStdRoots) {
    await fs.cp(path.join(src, rel), path.join(pending, rel), {recursive:true});
  }
  await installCrossRuntime({root:path.join(src, 'cross-runtime'), stage:pending, tuple:androidTuple, runtimeRef});
  await fs.writeFile(path.join(pending, androidStdProvenance), provenance);
  const source = host.sources?.runtime;
  if (!source?.repository || source.commit !== runtimeRef) throw Error('ANDROID_INSTALL_RUNTIME_PAIR');
  await readAndroidInputs(pending, {status:'resolved', repository:source.repository, commit:runtimeRef});
  // Replace this tuple as a whole on resume; a removed library must not survive.
  const members = [...androidStdRoots, androidStdProvenance, 'CROSS-RUNTIME-' + androidTuple + '.json'];
  await publishPaths(members.map(rel => ({pending:path.join(pending, rel), destination:path.join(sdk, rel)})));
} finally {
  await fs.rm(pending, {recursive:true, force:true});
}
