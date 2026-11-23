#!/usr/bin/env zx

// Install one source-built Cangjie tool over the stock copy in the release SDK,
// keeping the stock bytes under tools/stock the way install_cjpm_artifact.mjs
// keeps cjpm's. The sidecar pins the exact binary that must be installed, so a
// swapped payload is refused rather than shipped.

import fs from 'node:fs/promises';
import path from 'node:path';
import {assertX64PeImage} from '../../../lib/pe-symbols.mjs';
import {parseArgs} from 'node:util';
import {privateRoot} from '../../../../ci/bootstrap/sdk-flow.mjs';
import {toolName,retainedToolPath,cjlintPublicConfigPath} from '../../../srcbuild/tool-layout.mjs';
import {requireCjlintRuntimePair} from './cjlint-runtime-pair.mjs';
import {preserveStock} from '../../../lib/stock-backup.mjs';
import {
  readToolsPin, artifactSourceBinary,
  safePayloadPath,
  verifyComponentProvenance,
} from '../../../lib/release-component-provenance.mjs';

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

if(values.tool==='cjlint'&&!['linux-x64','windows-x64'].includes(values.platform))throw Error('CJLINT_PLATFORM_NOT_SUPPORTED');
const windows = values.platform === 'windows-x64';
const name = values.tool + (windows ? '.exe' : '');
const artifactRoot = path.resolve(values.artifact);
const sourceBinary = path.join(artifactRoot, name);
if(windows)assertX64PeImage(sourceBinary,false);
const sidecar = path.join(artifactRoot, 'SOURCE-PROVENANCE.json');
const pin = await readToolsPin(path.resolve(import.meta.dirname, '..', '..', '..', '..', 'ci', 'source_pin.env'));
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
const lintConfig=[];
if(values.tool==='cjlint') {
  await requireCjlintRuntimePair(artifactRoot);
  await fs.mkdir(sdkRoot,{recursive:true});
  // The verified artifact already transports the private source configuration.
  // Preflight the corresponding public paths before replacing any stock entry.
  const prefix='.target-tools/tools/cjlint/config';
  const config=await safePayloadPath(artifactRoot,prefix);
  for(const name of await fs.readdir(config,{recursive:true})) {
    const fromRel=prefix+'/'+name.split(path.sep).join('/');
    const toRel=cjlintPublicConfigPath(fromRel);
    if(!toRel)continue;
    const from=await safePayloadPath(artifactRoot,fromRel);
    if(!(await fs.stat(from)).isFile())continue;
    lintConfig.push({from,to:await safePayloadPath(sdkRoot,toRel)});
  }
  if(!lintConfig.some(row=>row.to===path.join(sdkRoot,'tools/config/cjlint_rule_list.json')))
    throw Error('CJLINT_PUBLIC_RULE_LIST_MISSING');
}
const toolsBin = await privateRoot(path.join(sdkRoot, 'tools', 'bin'));
const installed = path.join(toolsBin, name);
const staged = path.join(toolsBin, values.tool + '-source' + (windows ? '.exe' : ''));
await fs.mkdir(toolsBin, {recursive: true});
// A newly added source tool (for example cjhead) has no stock predecessor.
// Preserve an existing entry, but do not require an obsolete tool in a fresh SDK.
const prior = await fs.lstat(installed).catch(error => {
  if (error.code === 'ENOENT') return null;
  throw error;
});
if (prior) await preserveStock({sdk: values.sdk, installed, name});
await fs.copyFile(sourceBinary, staged);
if (!windows) await fs.chmod(staged, 0o755);
await fs.rm(installed, {force: true});
const isolated=['cjlint','LSPServer','cjhead'].includes(values.tool);
const retained=isolated?retainedToolPath({producer:toolName(values.tool),name,to:'tools/bin/'+name}):null;
// Payload installation also replaces the private runtime tree. Publish the
// retained body afterwards so replacing that tree cannot remove the new body.
if(!isolated)await fs.rename(staged, installed);

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
  if((values.tool==='cjprof'&&['tools/config/static','.target-tools/tools/config/static'].includes(entry.path))||(['cjlint','LSPServer','cjhead'].includes(values.tool)&&entry.path==='.target-tools/tools/'+toolName(values.tool)))
    await fs.rm(to,{recursive:true,force:true});
  // Merge genuinely shared directories.
  await fs.cp(from, to, {recursive: entry.type === 'directory', force:true});
}
for(const {from,to} of lintConfig) {
  await fs.mkdir(path.dirname(to),{recursive:true});
  await fs.copyFile(from,to);
}
if(isolated) {
  const body=await safePayloadPath(sdkRoot,retained);
  await fs.mkdir(path.dirname(body),{recursive:true});await fs.rename(staged,body);
  const selected=await artifactSourceBinary(installed,sdkRoot,values.platform);
  if(selected!==body)throw Error('SOURCE_TOOL_ARTIFACT_ENTRY_BODY '+values.tool);
}
if (provenance.payloads.length) {
  console.log(`${values.tool.toUpperCase()}-PAYLOADS installed=${provenance.payloads.map(entry => entry.path).join(',')}`);
}

// The release manifest keeps the verified source identity beside the installed
// application, including tools whose public entry selects a retained body.
// Write the verified sidecar into the package, not just beside the artifact.
await fs.copyFile(sidecar, path.join(path.resolve(values.sdk), 'tools', `${values.tool}.SOURCE.json`));

// These tools need the packaged std and runtime on the loader path, which do not
// exist until the package is composed, so the release smoke owns running them.
console.log(`${values.tool.toUpperCase()}-ACTIVATED platform=${values.platform} `
  + `source=${provenance.source.repository}@${provenance.source.commit} sha256=${provenance.artifact.sha256}`);
