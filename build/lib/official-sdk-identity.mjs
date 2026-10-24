#!/usr/bin/env zx
// Original download integrity and the selected compiler version; no tree inventory.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {baseSdkDownload} from './release-component-provenance.mjs';
import {hostToolchainFromCjcVersion} from '../../ci/host-toolchain-pin.mjs';
import {getTarget} from './targets.mjs';
import {cleanSdkEnvironment} from '../../ci/bootstrap/sdk-platform.mjs';

const execute = promisify(execFile);
async function digest(file) {
  const hash = crypto.createHash('sha256');
  const handle = await fs.open(file, 'r');
  try { for await (const chunk of handle.createReadStream()) hash.update(chunk); }
  finally { await handle.close(); }
  return hash.digest('hex');
}
export async function verifyOfficialSdkIdentity({root, version, archive, platform, selectedHost = false, env = process.env}) {
  // The selected version must match the original download and actual compiler.
  const expected = baseSdkDownload(platform, version, {selectedHost});
  if (version.replace(/^nightly-/, '') !== expected.version) throw new Error('OFFICIAL_IDENTITY requested version is not the release version');
  if (!archive || !path.isAbsolute(archive) || path.basename(archive) !== expected.archive) {
    throw new Error('OFFICIAL_IDENTITY original archive locator/name required');
  }
  const stat = await fs.stat(archive);
  if (!stat.isFile() || stat.size !== expected.size || await digest(archive) !== expected.sha256) {
    throw new Error('OFFICIAL_IDENTITY original archive differs from pinned release');
  }
  const {spec} = getTarget(platform);
  root = await fs.realpath(root);
  const binary = path.join(root, 'bin', `cjc${spec.exeSuffix}`);
  if (!(await fs.realpath(binary)).startsWith(root+path.sep)) throw new Error('OFFICIAL_HOST_COMPILER_ESCAPE');
  const environment = cleanSdkEnvironment(root, spec.llvmPlatform, env);
  let result;
  try { result = await execute(binary, ['--version'],
    {env: environment, timeout: 30000, maxBuffer: 1024 * 1024}); }
  catch (error) {
    error.rc = Number.isInteger(error.code) ? error.code : 1;
    console.error(JSON.stringify({argv:[binary,'--version'],rc:error.rc,signal:error.signal || null,
      stdout:error.stdout || '',stderr:error.stderr || ''}));
    throw error;
  }
  const actualVersion = hostToolchainFromCjcVersion(result.stdout).slice('nightly-'.length);
  if (actualVersion !== expected.version) throw new Error(`OFFICIAL_IDENTITY compiler mismatch: requested=${version} actual=${actualVersion}`);
  return {root, platform, version: expected.version,
    archive: {path: archive, sha256: expected.sha256, size: expected.size,
      repository: expected.releaseRepository, url: expected.url},
    compiler: {path:binary, argv:[binary,'--version'], version:actualVersion, stdout:result.stdout, stderr:result.stderr, rc:0}};
}
