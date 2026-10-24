#!/usr/bin/env node

// srcbuild already builds hle from source (build/srcbuild/stages/tools.mjs) and
// throws the binary away: srcbuild.yml uploads only source-cjpm-* and
// final-std-*. The stock hle that ships instead is not coloured, so it
// dereferences the coloured pointers a rebuilt std and the fork runtime hand it
// and dies. Staging it here mirrors prepare_cjpm_artifact.mjs.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {privateRoot} from '../bootstrap/sdk-flow.mjs';
import {
  HLE_PROVENANCE,
  readToolsPin,
  safePayloadPath,
  artifactSourceBinary,
  writeComponentProvenance,
} from '../../build/lib/release-component-provenance.mjs';
import {stampBinaryLineage} from '../../build/lib/toolchain-identity.mjs';
import {sourceToolPayloads} from './source-tool-payloads.mjs';

const {values} = parseArgs({
  options: {
    platform: {type: 'string'},
    binary: {type: 'string'},
    outdir: {type: 'string'},
    sdk: {type: 'string'},
  },
});
for (const name of ['platform', 'binary', 'outdir', 'sdk']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}

const windows = values.platform === 'windows-x64';
const destination = await privateRoot(values.outdir);
const sourceSdk = path.resolve(values.sdk);
// The tools build names its product `main`; the SDK calls it `hle`
// (build/srcbuild/stages/package.mjs).
const binary = path.join(destination, windows ? 'hle.exe' : 'hle');
const sidecar = path.join(destination, HLE_PROVENANCE);
const pin = await readToolsPin(path.resolve(import.meta.dirname, '..', 'source_pin.env'));

const inputBinary=await fs.realpath(values.binary);
const realSdk=await fs.realpath(sourceSdk);
if(inputBinary===destination || inputBinary.startsWith(destination+path.sep) || realSdk===destination || realSdk.startsWith(destination+path.sep)) throw new Error('artifact output overlaps its input');
await fs.rm(destination, {recursive: true, force: true});
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(await artifactSourceBinary(path.resolve(values.binary),sourceSdk,values.platform), binary);
if (!windows) await fs.chmod(binary, 0o755);
// hle's entry point loads its parser payload at run time. Staging the binary
// alone would leave the official payload beside our executable, so it is carried
// at the same relative path the installer puts it back to.
const payloads = [];
for (const relative of sourceToolPayloads('hle', values.platform)) {
  const from = await safePayloadPath(sourceSdk, relative);
  const stat = await fs.stat(from).catch(() => null);
  if (!stat) throw new Error(`hle: source SDK has no ${relative} (looked in ${sourceSdk})`);
  const to = await safePayloadPath(destination, relative);
  await fs.mkdir(path.dirname(to), {recursive: true});
  await fs.cp(from, to, {recursive: stat.isDirectory()});
  payloads.push({path: relative, type: stat.isDirectory() ? 'directory' : 'file'});
}
const lineage = await stampBinaryLineage({file: binary, prefix: 'CJTOOL-COMMIT', commit: pin.commit});
const provenance = await writeComponentProvenance({
  component: 'hle',
  binary,
  destination: sidecar,
  platform: values.platform,
  repository: pin.repository,
  commit: pin.commit,
  payloads,
});
console.log(`HLE-LINEAGE stamp=${lineage.stamp} changed=${lineage.changed}`);
console.log(`HLE-PROVENANCE platform=${values.platform} source=${pin.repository}@${pin.commit} sha256=${provenance.artifact.sha256} payloads=${payloads.length}`);
