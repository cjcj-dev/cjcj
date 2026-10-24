#!/usr/bin/env zx

// Swap the stock hle for the source-built one, keeping the stock copy under
// tools/stock the way install_cjpm_artifact.mjs keeps cjpm's.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {privateRoot} from '../bootstrap/sdk-flow.mjs';
import {preserveStock} from '../../build/lib/stock-backup.mjs';
import {
  HLE_PROVENANCE,
  readToolsPin,
  safePayloadPath,
  verifyComponentProvenance,
} from '../../build/lib/release-component-provenance.mjs';

const {values} = parseArgs({
  options: {
    platform: {type: 'string'},
    artifact: {type: 'string'},
    sdk: {type: 'string'},
  },
});
for (const name of ['platform', 'artifact', 'sdk']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}

const windows = values.platform === 'windows-x64';
const name = windows ? 'hle.exe' : 'hle';
const artifactRoot = path.resolve(values.artifact);
const sourceBinary = path.join(artifactRoot, name);
const sidecar = path.join(artifactRoot, HLE_PROVENANCE);
const pin = await readToolsPin(path.resolve(import.meta.dirname, '..', 'source_pin.env'));
const provenance = await verifyComponentProvenance({
  component: 'hle',
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
const staged = path.join(toolsBin, windows ? 'hle-source.exe' : 'hle-source');
await fs.mkdir(toolsBin, {recursive: true});
await preserveStock({sdk: values.sdk, installed, name});
await fs.copyFile(sourceBinary, staged);
if (!windows) await fs.chmod(staged, 0o755);
await fs.rm(installed, {force: true});
await fs.rename(staged, installed);

// The parser payload travels with the binary; both were verified against the
// sidecar above. Without this the package would carry our hle next to the
// official payload it reads at run time.
const root = sdkRoot;
for (const entry of provenance.payloads ?? []) {
  const from = await safePayloadPath(artifactRoot, entry.path);
  const to = await safePayloadPath(root, entry.path);
  await fs.mkdir(path.dirname(to), {recursive: true});
  // dtsparser is HLE-owned: remove members deleted by this producer version.
  // Shared payload directories keep other tools' installed configuration.
  if (entry.path === 'tools/dtsparser' && entry.type === 'directory') {
    await fs.rm(to, {recursive: true, force: true});
  }
  await fs.cp(from, to, {recursive: entry.type === 'directory', force:true});
}
if ((provenance.payloads ?? []).length) {
  console.log(`HLE-PAYLOADS installed=${provenance.payloads.map(entry => entry.path).join(',')}`);
}

await fs.copyFile(sidecar, path.join(root, 'tools', 'hle.SOURCE.json'));

// No --version probe here: hle needs the packaged std and runtime on the
// loader path, and this runs before the package is composed. The release
// smoke owns running it.
console.log(`HLE-ACTIVATED platform=${values.platform} source=${provenance.source.repository}@${provenance.source.commit} sha256=${provenance.artifact.sha256}`);
