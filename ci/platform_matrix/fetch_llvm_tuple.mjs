#!/usr/bin/env zx
// Download the newest successful native tuple job for this runner. A workflow
// run may be red solely because another matrix job failed, so select by job.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {emitBlockedSummary} from './common.mjs';

$.stdio = 'inherit';

const root = process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci');
const repo = process.env.SHIM_ARTIFACT_REPOSITORY || 'cjcj-dev/cjcj';
const workflow = process.env.TUPLE_WORKFLOW || 'platform-tuples.yml';
// Follow the branch this workflow runs on; a fixed default starves consumers on
// iteration branches (darwin waited 30min for artifacts that lived elsewhere).
const branch = process.env.TUPLE_BRANCH || process.env.GITHUB_REF_NAME || 'ci/platform-matrix';

const platforms = {
  'linux/x64': 'linux_x86_64',
  'linux/arm64': 'linux_aarch64',
  'darwin/arm64': 'darwin_aarch64',
  'darwin/x64': 'darwin_x86_64',
  'win32/x64': 'windows_x86_64',
};
const platform = platforms[`${process.platform}/${process.arch}`];
if (!platform) {
  emitBlockedSummary(`unsupported tuple host ${process.platform}/${process.arch}`);
  process.exit(0);
}
const artifactName = `fixed-llvm-tools-${platform}`;

async function ghLines(endpoint, jq) {
  const result = await $({nothrow: true, stdio: 'pipe'})`gh api ${endpoint} --jq ${jq}`;
  if (result.exitCode !== 0) process.exit(result.exitCode);
  return result.stdout.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

export async function selectTupleArtifact() {
  if (platform === 'linux_x86_64') {
    const runId = process.env.LINUX_X64_TUPLE_RUN || '29840652402';
    const ids = await ghLines(`/repos/${repo}/actions/runs/${runId}/artifacts`, `.artifacts[] | select(.name == "${artifactName}" and .expired == false) | .id`);
    return {runId, artifactId: ids[0] || ''};
  }

  const attempts = Number(process.env.TUPLE_FETCH_ATTEMPTS || 60);
  const delaySeconds = Number(process.env.TUPLE_FETCH_DELAY_SECONDS || 30);
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const runIds = await ghLines(`/repos/${repo}/actions/workflows/${workflow}/runs?branch=${encodeURIComponent(branch)}&status=completed&per_page=30`, '.workflow_runs[].id');
    for (const runId of runIds) {
      const jobs = await ghLines(`/repos/${repo}/actions/runs/${runId}/jobs?filter=latest&per_page=100`, `.jobs[] | select(.name | contains("${platform}")) | select(.conclusion == "success") | .id`);
      if (!jobs[0]) continue;
      const artifacts = await ghLines(`/repos/${repo}/actions/runs/${runId}/artifacts`, `.artifacts[] | select(.name == "${artifactName}" and .expired == false) | .id`);
      if (artifacts[0]) return {runId, artifactId: artifacts[0]};
    }
    if (attempt < attempts) {
      console.log(`waiting for ${artifactName} (${attempt}/${attempts})`);
      await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));
    }
  }
  return {runId: '', artifactId: ''};
}

if (!(await (async () => {
  const gh = await $({nothrow: true, stdio: 'pipe'})`gh --version`;
  if (gh.exitCode !== 0) {
    emitBlockedSummary('gh is unavailable; cannot query source-built LLVM tuples');
    return false;
  }
  const unzip = process.platform === 'win32' ? {exitCode: 0} : await $({nothrow: true, stdio: 'pipe'})`unzip -v`;
  if (unzip.exitCode !== 0) {
    emitBlockedSummary('unzip is unavailable; cannot unpack source-built LLVM tuple');
    return false;
  }
  return true;
})())) process.exit(0);

await fs.mkdir(path.join(root, 'fixed-toolchain'), {recursive: true});
const {runId, artifactId} = await selectTupleArtifact();
if (!artifactId) {
  emitBlockedSummary(`no active ${artifactName} artifact from a recent successful tuple job`);
  process.exit(0);
}
console.log(`tuple_selection run=${runId} artifact=${artifactId} platform=${platform} branch=${branch}`);
if (process.env.TUPLE_DRY_RUN === '1') process.exit(0);

const scratch = path.join(process.env.RUNNER_TEMP || process.env.TMPDIR || os.tmpdir(), `platform-ci-${platform}-tuple`);
await fs.mkdir(scratch, {recursive: true});
const archive = path.join(scratch, 'artifact.zip');
const archiveFd = fsSync.openSync(archive, 'w');
const download = spawnSync('gh', ['api', `/repos/${repo}/actions/artifacts/${artifactId}/zip`], {stdio: ['inherit', archiveFd, 'inherit']});
fsSync.closeSync(archiveFd);
if (download.status !== 0) process.exit(download.status ?? 1);

let entries;
let extracted;
if (process.platform === 'win32') {
  extracted = path.join(scratch, 'artifact');
  await fs.rm(extracted, {recursive: true, force: true});
  await $`pwsh -NoLogo -NoProfile -Command ${`Expand-Archive -LiteralPath '${archive.replaceAll("'", "''")}' -DestinationPath '${extracted.replaceAll("'", "''")}' -Force`}`;
  async function collect(directory) {
    const found = [];
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) found.push(...await collect(target));
      else if (entry.isFile()) found.push(path.relative(extracted, target));
    }
    return found;
  }
  entries = await collect(extracted);
} else {
  entries = (await $({stdio: 'pipe'})`unzip -Z1 ${archive}`).stdout.split(/\r?\n/).filter(Boolean);
}
const llcEntry = entries.find((entry) => /(^|[\\/])llc\.gz$/.test(entry));
const shimEntry = entries.find((entry) => /(^|[\\/])cjselfhost_llvmshim\.o$/.test(entry));
if (!llcEntry || !shimEntry) {
  emitBlockedSummary(`${artifactName} is incomplete (requires llc.gz + cjselfhost_llvmshim.o)`);
  process.exit(0);
}

const dest = path.join(root, 'fixed-toolchain', platform);
await fs.mkdir(dest, {recursive: true});
const llc = path.join(dest, 'llc.gz');
const shim = path.join(dest, 'cjselfhost_llvmshim.o');
if (process.platform === 'win32') {
  await fs.copyFile(path.join(extracted, llcEntry), llc);
  await fs.copyFile(path.join(extracted, shimEntry), shim);
} else {
  await $`unzip -p ${archive} ${llcEntry} > ${llc}`;
  await $`unzip -p ${archive} ${shimEntry} > ${shim}`;
}
if (!(await fs.stat(llc)).size || !(await fs.stat(shim)).size) throw new Error('tuple artifact contains an empty required file');

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
}
if (platform === 'linux_x86_64') {
  if (await sha256(llc) !== '084b0e437e879a20b72892464aed387955c7f0fe8e2d2b3bbb00f022af036e23') throw new Error('fixed llc integrity mismatch');
  if (await sha256(shim) !== 'bb05dfd1fa584aa8456356064c3dd392c3588a13708327a6f899d9a09ec4fd47') throw new Error('fixed shim integrity mismatch');
} else {
  const descriptions = {
    linux_aarch64: /ELF 64-bit.*(aarch64|ARM)/i,
    darwin_aarch64: /Mach-O 64-bit.*(arm64|aarch64)/i,
    darwin_x86_64: /Mach-O 64-bit.*x86_64/i,
  };
  if (platform === 'windows_x86_64') {
    const header = await fs.readFile(shim);
    if (header.length < 2 || header.readUInt16LE(0) !== 0x8664) throw new Error('unexpected shim format: not COFF AMD64');
  } else {
    const description = (await $({stdio: 'pipe'})`file ${shim}`).stdout;
    if (!descriptions[platform].test(description)) throw new Error(`unexpected shim format: ${description.trim()}`);
  }
}

await fs.copyFile(shim, path.join('runtime_shim', 'cjselfhost_llvmshim.o'));
const destAbs = path.resolve(dest);
const githubEnv = process.env.GITHUB_ENV;
if (!githubEnv) throw new Error('GITHUB_ENV is required');
await fs.appendFile(githubEnv, `FIXED_LLC_GZ=${path.join(destAbs, 'llc.gz')}\nCJCJ_LLVM_SHIM_O=${path.join(destAbs, 'cjselfhost_llvmshim.o')}\nPLATFORM_TUPLE=${platform}\n`);
console.log(`tuple_run=${runId}\ntuple_artifact=${artifactId}\ntuple_platform=${platform}`);
console.log(`${await sha256(llc)}  ${llc}\n${await sha256(shim)}  ${shim}`);
