#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {
  GATE_APPARATUS_PROVENANCE,
  parseGateHostToolchain,
  resolveGateHostRuntime,
  writeGateApparatusProvenance,
} from '../../build/lib/release-gate-apparatus.mjs';

const {values} = parseArgs({
  options: {
    sdk: {type: 'string'},
    platform: {type: 'string'},
    'toolchain-pin': {type: 'string'},
    'base-sdk-provenance': {type: 'string'},
    outdir: {type: 'string'},
  },
});

for (const name of ['sdk', 'platform', 'toolchain-pin', 'base-sdk-provenance', 'outdir']) {
  if (!values[name]) throw new Error(`--${name} is required`);
}

const toolchain = parseGateHostToolchain(await fs.readFile(values['toolchain-pin'], 'utf8'));
const baseSdkProvenance = JSON.parse(await fs.readFile(values['base-sdk-provenance'], 'utf8'));
const source = await resolveGateHostRuntime({sdk: values.sdk, platform: values.platform});
const output = path.resolve(values.outdir);
const retainedRuntime = path.join(output, `gate-host-runtime${path.extname(source.file)}`);
const sidecar = path.join(output, GATE_APPARATUS_PROVENANCE);
await fs.mkdir(output, {recursive: true});
await fs.copyFile(source.file, retainedRuntime);
const provenance = await writeGateApparatusProvenance({
  runtime: retainedRuntime,
  runtimePath: source.relative,
  destination: sidecar,
  platform: values.platform,
  toolchain,
  baseSdkProvenance,
});

if (process.env.GITHUB_ENV) {
  await fs.appendFile(process.env.GITHUB_ENV, [
    `GATE_HOST_RUNTIME=${retainedRuntime}`,
    `GATE_APPARATUS_PROVENANCE=${sidecar}`,
    '',
  ].join('\n'));
}

console.log([
  'GATE-APPARATUS',
  `platform=${values.platform}`,
  `toolchain=${provenance.gate_host_toolchain}`,
  `runtime_sha256=${provenance.host_runtime.sha256}`,
  `g_cjLoadBadMask=${provenance.host_runtime.g_cjLoadBadMask_count}`,
  `sidecar=${sidecar}`,
].join(' '));
