#!/usr/bin/env node

// srcbuild already builds hle from source (build/srcbuild/stages/tools.mjs) and
// throws the binary away: srcbuild.yml uploads only source-cjpm-* and
// final-std-*. The stock hle that ships instead is not coloured, so it
// dereferences the coloured pointers a rebuilt std and the fork runtime hand it
// and dies. Staging it here mirrors prepare_cjpm_artifact.mjs.

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {
  HLE_PROVENANCE,
  readToolsPin,
  writeComponentProvenance,
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
// The tools build names its product `main`; the SDK calls it `hle`
// (build/srcbuild/stages/package.mjs).
const binary = path.join(destination, windows ? 'hle.exe' : 'hle');
const sidecar = path.join(destination, HLE_PROVENANCE);
const pin = await readToolsPin(path.resolve(import.meta.dirname, '..', 'source_pin.env'));

await fs.rm(destination, {recursive: true, force: true});
await fs.mkdir(destination, {recursive: true});
await fs.copyFile(path.resolve(values.binary), binary);
if (!windows) await fs.chmod(binary, 0o755);
const lineage = await stampBinaryLineage({file: binary, prefix: 'CJTOOL-COMMIT', commit: pin.commit});
const provenance = await writeComponentProvenance({
  component: 'hle',
  binary,
  destination: sidecar,
  platform: values.platform,
  repository: pin.repository,
  commit: pin.commit,
});
console.log(`HLE-LINEAGE stamp=${lineage.stamp} changed=${lineage.changed}`);
console.log(`HLE-PROVENANCE platform=${values.platform} source=${pin.repository}@${pin.commit} sha256=${provenance.artifact.sha256}`);
