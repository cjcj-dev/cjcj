#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {
  CJPM_PROVENANCE,
  readCjpmPin,
  writeCjpmProvenance,
} from '../../build/lib/release-component-provenance.mjs';
import {stampBinaryLineage} from '../../build/lib/toolchain-identity.mjs';

const {values} = parseArgs({
  options: {
    platform: {type: 'string'},
    binary: {type: 'string'},
    outdir: {type: 'string'},
  },
});
for (const name of ['platform', 'binary', 'outdir']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}

const windows = values.platform === 'windows-x64';
const destination = path.resolve(values.outdir);
const binary = path.join(destination, windows ? 'cjpm.exe' : 'cjpm');
const sidecar = path.join(destination, CJPM_PROVENANCE);
const pinFile = path.resolve(import.meta.dirname, '..', 'cjpm_pin.env');
const pin = await readCjpmPin(pinFile);

await fs.rm(destination, {recursive: true, force: true});
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(path.resolve(values.binary), binary);
if (!windows) await fs.chmod(binary, 0o755);
const lineage = await stampBinaryLineage({file: binary, prefix: 'CJTOOL-COMMIT', commit: pin.commit});
const provenance = await writeCjpmProvenance({
  binary,
  destination: sidecar,
  platform: values.platform,
  repository: pin.repository,
  commit: pin.commit,
});
console.log(`CJPM-LINEAGE stamp=${lineage.stamp} changed=${lineage.changed}`);
console.log(`CJPM-PROVENANCE platform=${values.platform} source=${pin.repository}@${pin.commit} sha256=${provenance.artifact.sha256}`);
