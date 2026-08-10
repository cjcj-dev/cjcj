#!/usr/bin/env node

// Swap the stock hle for the source-built one, keeping the stock copy beside it
// the way install_cjpm_artifact.mjs keeps cjpm-stock.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {
  HLE_PROVENANCE,
  readToolsPin,
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

const toolsBin = path.join(path.resolve(values.sdk), 'tools', 'bin');
const installed = path.join(toolsBin, name);
const stock = path.join(toolsBin, windows ? 'hle-stock.exe' : 'hle-stock');
const staged = path.join(toolsBin, windows ? 'hle-source.exe' : 'hle-source');
await fs.mkdir(toolsBin, {recursive: true});
try {
  await fs.access(stock);
} catch {
  await fs.copyFile(installed, stock);
}
await fs.copyFile(sourceBinary, staged);
if (!windows) await fs.chmod(staged, 0o755);
await fs.rm(installed, {force: true});
await fs.rename(staged, installed);

// No --version probe here: hle needs the packaged std and runtime on the
// loader path, and this runs before the package is composed. The release
// smoke owns running it.
console.log(`HLE-ACTIVATED platform=${values.platform} source=${provenance.source.repository}@${provenance.source.commit} sha256=${provenance.artifact.sha256}`);
