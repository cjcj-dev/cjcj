#!/usr/bin/env zx
// Install the newest successful patched-cjpm artifact into the provisioned
// Windows SDK. Non-Windows matrix jobs remain untouched; local dry-run may
// explicitly exercise artifact selection from another host.

import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {spawnSync} from 'node:child_process';
import {emitBlockedSummary, toCommandPath} from './common.mjs';

$.stdio = 'inherit';

const dryRun = process.env.CJPM_FETCH_DRY_RUN === '1';
if (process.platform !== 'win32' && !dryRun) {
  console.log(`patched cjpm is Windows-only; skipping ${process.platform}/${process.arch}`);
  process.exit(0);
}
if (process.platform === 'win32' && process.arch !== 'x64') {
  emitBlockedSummary(`unsupported patched cjpm host ${process.platform}/${process.arch}`);
  process.exit(0);
}

const repo = process.env.CJPM_ARTIFACT_REPOSITORY || 'cjcj-dev/cjcj';
const workflow = process.env.CJPM_WORKFLOW || 'build-cjpm.yml';
const artifactName = 'patched-cjpm-windows_x86_64';

async function ghLines(endpoint, jq) {
  const result = await $({nothrow: true, stdio: 'pipe'})`gh api ${endpoint} --jq ${jq}`;
  if (result.exitCode !== 0) process.exit(result.exitCode);
  return result.stdout.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

export async function selectCjpmArtifact() {
  const attempts = Number(process.env.CJPM_FETCH_ATTEMPTS || 60);
  const delaySeconds = Number(process.env.CJPM_FETCH_DELAY_SECONDS || 30);
  const branchQuery = process.env.CJPM_BRANCH ? `&branch=${encodeURIComponent(process.env.CJPM_BRANCH)}` : '';
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const runIds = await ghLines(
      `repos/${repo}/actions/workflows/${workflow}/runs?status=completed&per_page=30${branchQuery}`,
      '.workflow_runs[].id',
    );
    for (const runId of runIds) {
      const jobs = await ghLines(
        `repos/${repo}/actions/runs/${runId}/jobs?filter=latest&per_page=100`,
        '.jobs[] | select(.name | contains("windows_x86_64")) | select(.conclusion == "success") | .id',
      );
      if (!jobs[0]) continue;
      const artifacts = await ghLines(
        `repos/${repo}/actions/runs/${runId}/artifacts`,
        `.artifacts[] | select(.name == "${artifactName}" and .expired == false) | .id`,
      );
      if (artifacts[0]) return {runId, artifactId: artifacts[0]};
    }
    if (attempt < attempts) {
      console.log(`waiting for ${artifactName} (${attempt}/${attempts})`);
      await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));
    }
  }
  return {runId: '', artifactId: ''};
}

const gh = await $({nothrow: true, stdio: 'pipe'})`gh --version`;
if (gh.exitCode !== 0) {
  emitBlockedSummary('gh is unavailable; cannot query patched cjpm artifacts');
  process.exit(dryRun ? 0 : 78);
}

const {runId, artifactId} = await selectCjpmArtifact();
if (!artifactId) {
  emitBlockedSummary(`no active ${artifactName} artifact from a recent successful Windows job`);
  process.exit(dryRun ? 0 : 78);
}
console.log(`cjpm_selection run=${runId} artifact=${artifactId}`);
if (dryRun) process.exit(0);

const cangjieHome = process.env.CANGJIE_HOME;
if (!cangjieHome) throw new Error('CANGJIE_HOME is required after SDK provision');
const scratch = path.join(process.env.RUNNER_TEMP || os.tmpdir(), 'platform-ci-patched-cjpm');
await fs.mkdir(scratch, {recursive: true});
const archive = path.join(scratch, 'artifact.zip');
const archiveFd = fsSync.openSync(archive, 'w');
const download = spawnSync('gh', ['api', `repos/${repo}/actions/artifacts/${artifactId}/zip`], {
  stdio: ['inherit', archiveFd, 'inherit'],
});
fsSync.closeSync(archiveFd);
if (download.status !== 0) process.exit(download.status ?? 1);

const extracted = path.join(scratch, 'artifact');
await fs.rm(extracted, {recursive: true, force: true});
const archiveCommandPath = toCommandPath(archive).replaceAll("'", "''");
const extractedCommandPath = toCommandPath(extracted).replaceAll("'", "''");
await $`pwsh -NoLogo -NoProfile -Command ${`Expand-Archive -LiteralPath '${archiveCommandPath}' -DestinationPath '${extractedCommandPath}' -Force`}`;

async function findFirst(directory, name) {
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === name.toLowerCase()) return target;
    if (entry.isDirectory()) {
      const found = await findFirst(target, name);
      if (found) return found;
    }
  }
  return '';
}

const compressed = await findFirst(extracted, 'cjpm.exe.gz');
if (!compressed) throw new Error(`${artifactName} is incomplete: cjpm.exe.gz is missing`);
const toolsBin = path.join(cangjieHome, 'tools', 'bin');
const installed = path.join(toolsBin, 'cjpm.exe');
const stock = path.join(toolsBin, 'cjpm-stock.exe');
const staged = path.join(toolsBin, 'cjpm-patched.exe');
await fs.mkdir(toolsBin, {recursive: true});
try {
  await fs.access(stock);
} catch {
  await fs.copyFile(installed, stock);
}
await fs.writeFile(staged, zlib.gunzipSync(await fs.readFile(compressed)));
const stagedProbe = spawnSync(staged, ['--version'], {encoding: 'utf8'});
if (stagedProbe.status !== 0) {
  throw new Error(`patched cjpm probe failed before activation: status=${stagedProbe.status} error=${stagedProbe.error?.code || 'none'} stderr=${stagedProbe.stderr?.slice(0, 400) || ''}`);
}
await fs.rm(installed, {force: true});
await fs.rename(staged, installed);
await $`${toCommandPath(installed)} --version`;
console.log(`activated patched cjpm: ${installed}; stock backup: ${stock}`);
