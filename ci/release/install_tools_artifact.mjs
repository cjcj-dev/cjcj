#!/usr/bin/env node

// Install one source-built Cangjie tool over the stock copy in the release SDK,
// keeping the stock bytes under tools/stock the way install_cjpm_artifact.mjs
// keeps cjpm's. The sidecar pins the exact binary that must be installed, so a
// swapped payload is refused rather than shipped.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {privateRoot} from '../bootstrap/sdk-flow.mjs';
import {installEntries} from '../bootstrap/sdk-install-entries.mjs';
import {getTarget} from '../../build/lib/targets.mjs';
import {preserveStock} from '../../build/lib/stock-backup.mjs';
import {
  readToolsPin,
  safePayloadPath,
  verifyComponentProvenance,
} from '../../build/lib/release-component-provenance.mjs';

const {values} = parseArgs({
  options: {
    tool: {type: 'string'},
    platform: {type: 'string'},
    artifact: {type: 'string'},
    sdk: {type: 'string'},
  },
});
for (const name of ['tool', 'platform', 'artifact', 'sdk']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}
if (!/^[A-Za-z0-9][A-Za-z0-9_.+-]*$/.test(values.tool)) throw new Error(`invalid tool name: ${values.tool}`);

if(values.tool==='cjlint'&&values.platform!=='linux-x64')throw Error('CJLINT_PLATFORM_NOT_SUPPORTED');
const windows = values.platform === 'windows-x64';
const name = values.tool + (windows ? '.exe' : '');
const artifactRoot = path.resolve(values.artifact);
const sourceBinary = path.join(artifactRoot, name);
const sidecar = path.join(artifactRoot, 'SOURCE-PROVENANCE.json');
const pin = await readToolsPin(path.resolve(import.meta.dirname, '..', 'source_pin.env'));
const provenance = await verifyComponentProvenance({
  component: values.tool,
  artifactName: name,
  binary: sourceBinary,
  sidecar,
  platform: values.platform,
  expectedRepository: pin.repository,
  expectedCommit: pin.commit,
});

const sdkRoot=await privateRoot(values.sdk);
const toolsBin = await privateRoot(path.join(sdkRoot, 'tools', 'bin'));
const installed = path.join(toolsBin, name);
const staged = path.join(toolsBin, values.tool + '-source' + (windows ? '.exe' : ''));
await fs.mkdir(toolsBin, {recursive: true});
await preserveStock({sdk: values.sdk, installed, name});
await fs.copyFile(sourceBinary, staged);
if (!windows) await fs.chmod(staged, 0o755);
await fs.rm(installed, {force: true});
await fs.rename(staged, installed);

// The tool's run-time files travel with it. They were verified against the
// sidecar above, so they are the ones the source build produced; copying them is
// what keeps the official configuration and implementation library out of a
// package whose tool binary is ours.
const root = sdkRoot;
for (const entry of provenance.payloads) {
  const from = await safePayloadPath(artifactRoot, entry.path);
  const to = await safePayloadPath(root, entry.path);
  await fs.mkdir(path.dirname(to), {recursive: true});
  // cjprof owns its static subtrees; removed source pages must disappear on
  // artifact reinstallation too. Keep other tools' shared config intact.
  if((values.tool==='cjprof'&&['tools/config/static','.target-tools/tools/config/static'].includes(entry.path))||(values.tool==='cjlint'&&entry.path==='.target-tools/tools/cjlint'))
    await fs.rm(to,{recursive:true,force:true});
  // Merge genuinely shared directories.
  await fs.cp(from, to, {recursive: entry.type === 'directory', force:true});
}
if(values.tool==='cjlint')await installEntries({root:sdkRoot,build:path.join(sdkRoot,'.native-tools/cjlint-entry'),
  platform:getTarget(values.platform).spec.llvmPlatform,records:[],
  groups:[{directory:'tools/bin',retain:'.target-tools/tools/cjlint/bin',names:['cjlint'],libraries:['.target-tools/tools/cjlint/lib']}]});
if (provenance.payloads.length) {
  console.log(`${values.tool.toUpperCase()}-PAYLOADS installed=${provenance.payloads.map(entry => entry.path).join(',')}`);
}

// The release manifest discovers a C++-backed tool by the sidecar naming the
// installed binary, since such a tool carries no Cangjie runtime entry point.
// Write the verified sidecar into the package, not just beside the artifact.
await fs.copyFile(sidecar, path.join(path.resolve(values.sdk), 'tools', `${values.tool}.SOURCE.json`));

// These tools need the packaged std and runtime on the loader path, which do not
// exist until the package is composed, so the release smoke owns running them.
console.log(`${values.tool.toUpperCase()}-ACTIVATED platform=${values.platform} `
  + `source=${provenance.source.repository}@${provenance.source.commit} sha256=${provenance.artifact.sha256}`);
