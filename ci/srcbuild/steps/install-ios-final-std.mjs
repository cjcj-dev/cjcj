#!/usr/bin/env zx
// Install only the three target subtrees from each source-ios product. The
// host compiler, std and runtime already belong to the restored stage3 SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import {copyOutputs, fileDigest, privateRoot, publishPaths, readJson} from '../../bootstrap/sdk-flow.mjs';
import {installCrossRuntime} from '../../release/cross-runtime.mjs';
import {iosTargets} from '../lib/ios-runtime.mjs';

const {CANGJIE_WORKSPACE: workspace, IOS_ARTIFACT_DIR: artifacts,
  CJCJ_SRCBUILD_TARGET: host, CJCJ_NATIVE_RUNTIME_REF: runtimeRef} = process.env;
if (!workspace || !artifacts || host !== 'darwin-arm64' || !/^[a-f0-9]{40}$/.test(runtimeRef || ''))
  throw new Error('IOS_INSTALL_INPUTS');
const sdk = await privateRoot(path.resolve(workspace, 'software', 'cangjie'));
const stage = await readJson(path.join(sdk, 'STAGE-INPUTS.json'));
if (stage.phase !== 'stage3' || stage.platform !== 'darwin_aarch64' || stage.runtimeCommit !== runtimeRef)
  throw new Error('IOS_INSTALL_STAGE3_RUNTIME');

const pending = await fs.mkdtemp(path.join(path.dirname(sdk), 'ios-install-'));
const parts = [];
for (const {tuple, artifact} of iosTargets) {
  const root = path.join(artifacts, artifact);
  const build = await readJson(path.join(root, 'ios-build.json'));
  if (build.target.tuple !== tuple || build.runtimeRef !== runtimeRef) throw new Error('IOS_FINAL_STD_IDENTITY ' + tuple);
  const core = 'lib/' + tuple + '/libcangjie-std-core.a';
  if (build.records.find(row => row.file === core)?.sha256 !== await fileDigest(path.join(root, core)))
    throw new Error('IOS_FINAL_STD_CORE_BYTES ' + tuple);
  await fs.access(path.join(root, 'modules', tuple, 'std', 'std.core.cjo'));
  const dirs = ['modules/' + tuple, 'lib/' + tuple, 'runtime/lib/' + tuple];
  // copyOutputs rejects file collisions; std must not overwrite a runtime
  // object or dylib that passed the Mach-O and source identity checks.
  await installCrossRuntime({root: path.join(root, 'cross-runtime'), stage: pending, tuple, runtimeRef});
  await copyOutputs(pending, dirs.map(to => ({from: path.join(root, to), to, owner: artifact})));
  parts.push(...dirs, `CROSS-RUNTIME-${tuple}.json`);
}
// Replace the selected tuples together, also on a restored SDK with old files.
await publishPaths(parts.map(part => ({pending: path.join(pending, part), destination: path.join(sdk, part)})));
await fs.rm(pending, {recursive: true});
console.log('IOS_SDK_INSTALLED ' + iosTargets.map(row => row.tuple).join(','));
