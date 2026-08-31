#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {parseArgs} from 'node:util';
import {runRequiredCheck} from '../../build/lib/fail-closed-probes.mjs';
import {
  BASE_SDK_PROVENANCE,
  baseSdkDownload,
  writeBaseSdkProvenance,
} from '../../build/lib/release-component-provenance.mjs';

const {values} = parseArgs({
  options: {
    platform: {type: 'string'},
    toolchain: {type: 'string'},
    outdir: {type: 'string'},
  },
});

for (const name of ['platform', 'toolchain', 'outdir']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}

const output = path.resolve(values.outdir);
const expected = baseSdkDownload(values.platform, values.toolchain);
const archive = path.join(output, expected.archive);
const partial = `${archive}.partial`;
const sidecar = path.join(output, BASE_SDK_PROVENANCE);
await fs.mkdir(output, {recursive: true});
await fs.rm(partial, {force: true});

console.log(`BASE-SDK-DOWNLOAD url=${expected.url}`);
const response = await fetch(expected.url, {redirect: 'follow'});
if (!response.ok || !response.body) {
  throw new Error(`base SDK download failed: HTTP ${response.status} ${response.statusText}`);
}
try {
  await pipeline(Readable.fromWeb(response.body), (await fs.open(partial, 'w')).createWriteStream());
  await fs.rename(partial, archive);
} catch (error) {
  await fs.rm(partial, {force: true});
  throw error;
}

const provenance = await runRequiredCheck({
  label: 'base SDK pinned archive digest',
  run: () => writeBaseSdkProvenance({
    archive,
    destination: sidecar,
    platform: values.platform,
    toolchain: values.toolchain,
  }),
});
if (process.env.GITHUB_ENV) {
  await fs.appendFile(process.env.GITHUB_ENV, [
    `BASE_SDK_ARCHIVE=${archive}`,
    `BASE_SDK_PROVENANCE=${sidecar}`,
    `BASE_SDK_TOOLCHAIN=${values.toolchain}`,
    '',
  ].join('\n'));
}
console.log(`BASE-SDK-PROVENANCE platform=${values.platform} version=${provenance.release.version} sha256=${provenance.artifact.sha256}`);
