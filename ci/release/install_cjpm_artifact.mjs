#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {parseArgs} from 'node:util';
import {
  CJPM_PROVENANCE,
  readCjpmPin,
  verifyCjpmProvenance,
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
const artifactRoot = path.resolve(values.artifact);
const sourceBinary = path.join(artifactRoot, windows ? 'cjpm.exe' : 'cjpm');
const sidecar = path.join(artifactRoot, CJPM_PROVENANCE);
const pin = await readCjpmPin(path.resolve(import.meta.dirname, '..', 'cjpm_pin.env'));
const provenance = await verifyCjpmProvenance({
  binary: sourceBinary,
  sidecar,
  platform: values.platform,
  expectedRepository: pin.repository,
  expectedCommit: pin.commit,
});

const toolsBin = path.join(path.resolve(values.sdk), 'tools', 'bin');
const installed = path.join(toolsBin, windows ? 'cjpm.exe' : 'cjpm');
const stock = path.join(toolsBin, windows ? 'cjpm-stock.exe' : 'cjpm-stock');
const staged = path.join(toolsBin, windows ? 'cjpm-source.exe' : 'cjpm-source');
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

const probe = spawnSync(installed, ['--version'], {encoding: 'utf8', env: process.env});
if (probe.status !== 0) {
  throw new Error(`installed cjpm probe failed: status=${probe.status} error=${probe.error?.code || 'none'} stderr=${probe.stderr?.slice(0, 400) || ''}`);
}
process.stdout.write(probe.stdout || probe.stderr);
if (process.env.GITHUB_ENV) {
  await fs.appendFile(process.env.GITHUB_ENV, [
    `CJPM_PROVENANCE=${sidecar}`,
    `CJPM_SOURCE_REPOSITORY=${provenance.source.repository}`,
    `CJPM_SOURCE_COMMIT=${provenance.source.commit}`,
    '',
  ].join('\n'));
}
console.log(`CJPM-ACTIVATED platform=${values.platform} source=${provenance.source.repository}@${provenance.source.commit} sha256=${provenance.artifact.sha256}`);
