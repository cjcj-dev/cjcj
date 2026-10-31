#!/usr/bin/env zx

// One source-built Cangjie tool, published as an artifact with the identity of
// the checkout it was built from. cjpm and hle keep their own entry points
// because their install paths differ (cjpm carries a fork pin, hle is renamed);
// everything else goes through here, so a tool added to the source-build list
// needs no new script.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {getTarget} from '../../build/lib/targets.mjs';
import {privateRoot,fileDigest} from '../bootstrap/sdk-flow.mjs';
import {
  safePayloadPath,
  artifactSourceBinary,
  writeComponentProvenance,
} from '../../build/lib/release-component-provenance.mjs';
import {stampBinaryLineage} from '../../build/lib/toolchain-identity.mjs';
import {sourceToolPayloads} from './source-tool-payloads.mjs';

const {values} = parseArgs({
  options: {
    tool: {type: 'string'},
    platform: {type: 'string'},
    binary: {type: 'string'},
    outdir: {type: 'string'},
    sdk: {type: 'string'},
  },
});
for (const name of ['tool', 'platform', 'binary', 'outdir', 'sdk']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}
if (!/^[A-Za-z0-9][A-Za-z0-9_.+-]*$/.test(values.tool)) throw new Error(`invalid tool name: ${values.tool}`);

if(values.tool==='cjlint'&&values.platform!=='linux-x64')throw Error('CJLINT_PLATFORM_NOT_SUPPORTED');
const windows = values.platform === 'windows-x64';
const name = values.tool + (windows ? '.exe' : '');
const destination = await privateRoot(values.outdir);
const binary = path.join(destination, name);
const sidecar = path.join(destination, 'SOURCE-PROVENANCE.json');
const sourceSdk = path.resolve(values.sdk);
const record=JSON.parse(await fs.readFile(path.join(sourceSdk,'TOOLS-INPUTS.json'),'utf8'));
const row=record.files?.['tools/bin/'+name],producer=row?.producer;
if(producer?.source?.status!=='resolved'||!producer.source.repository||!/^[a-f0-9]{40}$/.test(producer.source.commit??'')
  ||producer.build?.rc!==0||producer.install?.rc!==0||producer.build.platform!==getTarget(values.platform).spec.llvmPlatform)throw Error('SOURCE_TOOL_ARTIFACT_PRODUCER '+values.tool);
const pin=producer.source;
// Transport the normal install's existing target launcher and relative recipe.
// Artifact installation must not rebuild a host launcher for a cross target.
if(['cjlint','LSPServer','cjhead'].includes(values.tool)) {
  const publicPath='tools/bin/'+name;
  if(row.entry?.path!==publicPath||row.entry.recipe?.path!==publicPath+'.entry')throw Error('SOURCE_TOOL_ARTIFACT_ENTRY '+values.tool);
  for(const entry of [row.entry,row.entry.recipe])if(await fileDigest(await safePayloadPath(sourceSdk,entry.path))!==entry.sha256)
    throw Error('SOURCE_TOOL_ARTIFACT_ENTRY_BYTES '+entry.path);
  const retained=await artifactSourceBinary(path.join(sourceSdk,publicPath),sourceSdk,values.platform);
  if(retained===path.join(sourceSdk,publicPath)||await fileDigest(retained)!==row.sha256)throw Error('SOURCE_TOOL_ARTIFACT_ENTRY_BODY '+values.tool);
}

const inputBinary=await fs.realpath(values.binary);
const realSdk=await fs.realpath(sourceSdk);
if(inputBinary===destination || inputBinary.startsWith(destination+path.sep) || realSdk===destination || realSdk.startsWith(destination+path.sep)) throw new Error('artifact output overlaps its input');
const actualBinary=await artifactSourceBinary(path.resolve(values.binary),sourceSdk,values.platform);
if(await fileDigest(actualBinary)!==row.sha256||producer.install.artifact?.sha256!==row.sha256)throw Error('SOURCE_TOOL_ARTIFACT_BYTES '+values.tool);
// Do not stamp a currently selected source onto changed runtime payloads.
// These are the producer's ordinary install facts, not a second selector.
for(const [rel,payload]of Object.entries(producer.install.payloads??{})) {
  const input=await safePayloadPath(sourceSdk,rel);
  if(await fileDigest(input)!==payload.sha256)throw Error('SOURCE_TOOL_ARTIFACT_PAYLOAD '+rel);
}
await fs.rm(destination, {recursive: true, force: true});
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(actualBinary,binary);
if (!windows) await fs.chmod(binary, 0o755);

// A tool is its binary plus the files it reads at run time. They are taken from
// the source-built SDK this artifact came from, at the very paths the installer
// will put them back to, so the release package cannot end up with our front end
// next to the official configuration or implementation library.
const payloads = [];
for (const relative of sourceToolPayloads(values.tool, values.platform)) {
  const from = await safePayloadPath(sourceSdk, relative);
  const stat = await fs.stat(from).catch(() => null);
  if (!stat) throw new Error(`${values.tool}: source SDK has no ${relative} (looked in ${sourceSdk})`);
  const to = await safePayloadPath(destination, relative);
  await fs.mkdir(path.dirname(to), {recursive: true});
  if((['cjlint','LSPServer','cjhead'].includes(values.tool)&&relative.startsWith('.target-tools/tools/'))
    ||(values.tool==='cjprof'&&relative.endsWith('/config/static'))) {
    // Transport the existing successful install set, not extra files left in
    // a shared SDK directory. Both cjprof body-relative layouts are required.
    const members=Object.keys(producer.install.payloads??{}).filter(rel=>rel.startsWith(relative+'/'));
    if(!members.length)throw Error('SOURCE_TOOL_ARTIFACT_CONFIG '+values.tool);
    for(const member of members) {
      const input=await safePayloadPath(sourceSdk,member),output=await safePayloadPath(destination,member);
      if(await fileDigest(input)!==producer.install.payloads[member].sha256)throw Error('SOURCE_TOOL_ARTIFACT_PAYLOAD '+member);
      await fs.mkdir(path.dirname(output),{recursive:true});await fs.copyFile(input,output);
    }
  } else await fs.cp(from, to, {recursive: stat.isDirectory()});
  payloads.push({path: relative, type: stat.isDirectory() ? 'directory' : 'file'});
}

const lineage = await stampBinaryLineage({file: binary, prefix: 'CJTOOL-COMMIT', commit: pin.commit});
const provenance = await writeComponentProvenance({
  component: values.tool,
  binary,
  destination: sidecar,
  platform: values.platform,
  repository: pin.repository,
  commit: pin.commit,
  payloads,
});
console.log(`${values.tool.toUpperCase()}-LINEAGE stamp=${lineage.stamp} changed=${lineage.changed}`);
console.log(`${values.tool.toUpperCase()}-PROVENANCE platform=${values.platform} source=${pin.repository}@${pin.commit} sha256=${provenance.artifact.sha256} payloads=${payloads.length}`);
