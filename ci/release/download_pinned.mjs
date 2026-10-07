#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {verify} from './bootstrap_store.mjs';

export function archivePin(repository, artifactId) {
  const file = process.env.BOOTSTRAP_ARCHIVES_PIN || new URL('../bootstrap_artifacts_pin.json', import.meta.url);
  const registry = JSON.parse(fs.readFileSync(file, 'utf8'));
  const pin = registry.artifacts?.[artifactId];
  if (registry.version !== 1 || !pin || pin.repository !== repository || pin.prerelease !== true
      || !Number.isSafeInteger(pin.asset) || pin.asset < 1 || !/^[a-f0-9]{64}$/.test(pin.release_sha256)) {
    throw new Error(`PERSISTENT_ARCHIVE_PIN_MISSING artifact=${artifactId}`);
  }
  return pin;
}

export function downloadPinned(repository, artifactId, archive) {
  const pin = archivePin(repository, artifactId);
  const fd = fs.openSync(archive, 'w');
  try {
    const result = spawnSync('gh', ['api', `repos/${repository}/releases/assets/${pin.asset}`,
      '-H', 'Accept: application/octet-stream'], {stdio: ['inherit', fd, 'inherit']});
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`PERSISTENT_ARCHIVE_DOWNLOAD_FAILED artifact=${artifactId} status=${result.status}`);
    verify(fs.readFileSync(archive), pin.release_sha256, `artifact-${artifactId}.zip`);
    console.log(`PERSISTENT_ARCHIVE_VERIFIED artifact=${artifactId} asset=${pin.asset} sha256=${pin.release_sha256}`);
  } catch (error) {
    fs.rmSync(archive, {force: true});
    throw error;
  } finally {
    fs.closeSync(fd);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [repository, artifactId, destination] = process.argv.slice(2);
  if (!destination) throw new Error('usage: download_pinned.mjs repository artifact-id destination');
  fs.mkdirSync(destination, {recursive: true});
  const scratch = fs.mkdtempSync(path.join(path.dirname(path.resolve(destination)), '.pinned-'));
  try {
    const archive = path.join(scratch, 'input.zip');
    downloadPinned(repository, artifactId, archive);
    const result = spawnSync('unzip', ['-q', archive, '-d', destination], {stdio: 'inherit'});
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error('PERSISTENT_ARCHIVE_EXTRACT_FAILED');
  } finally { fs.rmSync(scratch, {recursive: true, force: true}); }
}
