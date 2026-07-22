#!/usr/bin/env zx
// Fetch the immutable Linux x64 shim produced alongside the fixed llc and
// reject any artifact drift before it reaches the cjcj link.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

$.stdio = 'inherit';

const repository = process.env.SHIM_ARTIFACT_REPOSITORY || 'cjcj-dev/cjcj';
const run = process.env.SHIM_ARTIFACT_RUN || '29840652402';
const artifactName = process.env.SHIM_ARTIFACT_NAME || 'fixed-llvm-tools-linux_x86_64';
const expectedSize = Number(process.env.SHIM_EXPECTED_SIZE || 207776);
const expectedSha256 = process.env.SHIM_EXPECTED_SHA256 || 'bb05dfd1fa584aa8456356064c3dd392c3588a13708327a6f899d9a09ec4fd47';
const destination = process.env.SHIM_DESTINATION || path.join('runtime_shim', 'cjselfhost_llvmshim.o');
const scratch = process.env.RUNNER_TEMP || process.env.TMPDIR || os.tmpdir();
const work = path.join(scratch, 'platform-ci-linux-x64-shim');

if (process.platform !== 'linux' || process.arch !== 'x64') {
  console.error(`ERROR: Linux x64 shim injection requested on ${process.platform}/${process.arch}`);
  process.exit(2);
}
for (const command of ['gh', 'unzip']) {
  const probe = await $({nothrow: true, stdio: 'pipe'})`command -v ${command}`;
  if (probe.exitCode !== 0) {
    console.error(`ERROR: ${command} is required to ${command === 'gh' ? 'download' : 'unpack'} the shim artifact`);
    process.exit(3);
  }
}

await fs.mkdir(work, {recursive: true});
const ids = await $({stdio: 'pipe'})`gh api /repos/${repository}/actions/runs/${run}/artifacts --jq ${`.artifacts[] | select(.name == "${artifactName}" and .expired == false) | .id`}`;
const artifactId = ids.stdout.split(/\r?\n/).find(Boolean)?.trim() || '';
if (!artifactId) {
  console.error(`ERROR: active artifact ${artifactName} not found on run ${run}`);
  process.exit(4);
}

const archive = path.join(work, 'artifact.zip');
const archiveFd = fsSync.openSync(archive, 'w');
const download = spawnSync('gh', ['api', `/repos/${repository}/actions/artifacts/${artifactId}/zip`], {stdio: ['inherit', archiveFd, 'inherit']});
fsSync.closeSync(archiveFd);
if (download.status !== 0) process.exit(download.status ?? 1);
const entries = (await $({stdio: 'pipe'})`unzip -Z1 ${archive}`).stdout.split(/\r?\n/).filter(Boolean);
const entry = entries.find((name) => /(^|\/)cjselfhost_llvmshim\.o$/.test(name));
if (!entry) {
  console.error(`ERROR: cjselfhost_llvmshim.o missing from artifact ${artifactId}`);
  process.exit(5);
}
const candidate = path.join(work, 'cjselfhost_llvmshim.o');
await $`unzip -p ${archive} ${entry} > ${candidate}`;

const bytes = await fs.readFile(candidate);
const actualSize = bytes.length;
const actualSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
console.log(`shim_artifact_id=${artifactId}\nshim_size=${actualSize}\nshim_sha256=${actualSha256}`);
if (actualSize !== expectedSize || actualSha256 !== expectedSha256) {
  console.error(`ERROR: shim integrity mismatch; expected ${expectedSize} bytes/${expectedSha256}`);
  process.exit(6);
}
const description = (await $({stdio: 'pipe'})`file ${candidate}`).stdout;
if (!/ELF 64-bit.*(x86-64|x86_64)/.test(description)) {
  console.error('ERROR: downloaded shim is not an ELF x86-64 relocatable object');
  process.exit(7);
}
await fs.mkdir(path.dirname(destination), {recursive: true});
await fs.copyFile(candidate, destination);
console.log(`injected verified Linux x64 shim: ${destination}`);
