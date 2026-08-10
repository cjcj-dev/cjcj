import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export const BASE_SDK_PROVENANCE = 'BASE-SDK-PROVENANCE.json';
export const CJPM_PROVENANCE = 'CJPM-PROVENANCE.json';
export const SOURCE_PROVENANCE_RESOLVED = 'resolved';
export const SOURCE_PROVENANCE_NOT_APPLICABLE = 'not-applicable';
export const SOURCE_PROVENANCE_UNRESOLVED = 'unresolved';
export const BASE_SDK_SOURCE_REASON =
  'Official nightly SDKs are multi-repository integration artifacts and do not have a single source commit.';

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const NIGHTLY_RELEASE_REPOSITORY = 'https://gitcode.com/Cangjie/nightly_build';
const NIGHTLY_RELEASE_BASE = `${NIGHTLY_RELEASE_REPOSITORY}/releases/download`;

const baseSdkPlatforms = new Map([
  ['linux-x64', ['linux', 'x64', '.tar.gz']],
  ['linux-aarch64', ['linux', 'aarch64', '.tar.gz']],
  ['darwin-x64', ['mac', 'x64', '.tar.gz']],
  ['darwin-arm64', ['mac', 'aarch64', '.tar.gz']],
  ['windows-x64', ['windows', 'x64', '.zip']],
]);

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${label} is empty`);
  return value.trim();
}

function requireMatch(value, pattern, label) {
  const text = requireString(value, label);
  if (!pattern.test(text)) throw new Error(`${label} is invalid: ${text}`);
  return text;
}

async function fileSha256(file) {
  const hash = crypto.createHash('sha256');
  const handle = await fs.open(file, 'r');
  try {
    for await (const chunk of handle.createReadStream()) hash.update(chunk);
  } finally {
    await handle.close();
  }
  return hash.digest('hex');
}

async function readJson(file, label) {
  let text;
  try {
    text = await fs.readFile(file, 'utf8');
  } catch (error) {
    throw new Error(`${label} is missing: ${file} (${error.code || error.message})`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`${label} is not valid JSON: ${file} (${error.message})`);
  }
}

function requireIdentity(value, {component, platform}, label) {
  if (value?.schema !== 1) throw new Error(`${label}.schema must be 1`);
  if (value?.component !== component) throw new Error(`${label}.component must be ${component}`);
  if (value?.platform !== platform) {
    throw new Error(`${label}.platform mismatch: ${value?.platform || '<empty>'} != ${platform}`);
  }
}

export function baseSdkDownload(platform, toolchain) {
  const tuple = baseSdkPlatforms.get(platform);
  if (!tuple) throw new Error(`unsupported base SDK platform: ${platform}`);
  const version = requireString(toolchain, 'base SDK toolchain').replace(/^nightly-/, '');
  const [os, arch, extension] = tuple;
  const archive = `cangjie-sdk-${os}-${arch}-${version}${extension}`;
  return {
    archive,
    url: `${NIGHTLY_RELEASE_BASE}/${version}/${archive}`,
    releaseRepository: NIGHTLY_RELEASE_REPOSITORY,
    version,
  };
}

export async function writeBaseSdkProvenance({archive, destination, platform, toolchain}) {
  const expected = baseSdkDownload(platform, toolchain);
  if (path.basename(archive) !== expected.archive) {
    throw new Error(`base SDK archive name mismatch: ${path.basename(archive)} != ${expected.archive}`);
  }
  const value = {
    schema: 1,
    component: 'base-sdk',
    platform,
    source: {
      status: SOURCE_PROVENANCE_NOT_APPLICABLE,
      reason: BASE_SDK_SOURCE_REASON,
    },
    release: {
      repository: expected.releaseRepository,
      version: expected.version,
      download_url: expected.url,
    },
    artifact: {
      path: expected.archive,
      sha256: await fileSha256(archive),
    },
  };
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

export function validateBaseSdkProvenance(value, {platform, toolchain, label = 'base SDK provenance'}) {
  const expected = baseSdkDownload(platform, toolchain);
  requireIdentity(value, {component: 'base-sdk', platform}, label);
  if (value.source?.status !== SOURCE_PROVENANCE_NOT_APPLICABLE) {
    throw new Error(`${label}.source.status must be ${SOURCE_PROVENANCE_NOT_APPLICABLE}; got ${
      value.source?.status || SOURCE_PROVENANCE_UNRESOLVED}`);
  }
  const reason = requireString(value.source?.reason, `${label}.source.reason`);
  if (reason !== BASE_SDK_SOURCE_REASON) {
    throw new Error(`${label}.source.reason does not describe the official multi-repository SDK`);
  }
  if (value.release?.repository !== expected.releaseRepository ||
      value.release?.version !== expected.version ||
      value.release?.download_url !== expected.url) {
    throw new Error(`${label} release identity does not match ${expected.url}`);
  }
  if (value.artifact?.path !== expected.archive) {
    throw new Error(`${label} archive path does not match ${expected.archive}`);
  }
  requireMatch(value.artifact?.sha256, SHA256, `${label}.artifact.sha256`);
  return value;
}

export async function verifyBaseSdkProvenance({archive, sidecar, platform, toolchain}) {
  const label = 'base SDK provenance';
  const expected = baseSdkDownload(platform, toolchain);
  const value = validateBaseSdkProvenance(await readJson(sidecar, label), {platform, toolchain, label});
  if (path.basename(archive) !== expected.archive) {
    throw new Error(`${label} archive path does not match ${expected.archive}`);
  }
  const recorded = requireMatch(value.artifact?.sha256, SHA256, `${label}.artifact.sha256`);
  const actual = await fileSha256(archive);
  if (recorded !== actual) throw new Error(`${label} archive SHA-256 mismatch: ${recorded} != ${actual}`);
  return value;
}

export function parseCjpmPin(text) {
  const values = Object.fromEntries(text.split(/\r?\n/).filter(Boolean).map(line => {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid cjpm pin line: ${line}`);
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
  return {
    repository: requireString(values.CJPM_FORK_URL, 'CJPM_FORK_URL'),
    commit: requireMatch(values.CJPM_FORK_REF, SHA40, 'CJPM_FORK_REF'),
  };
}

export async function readCjpmPin(pinFile) {
  return parseCjpmPin(await fs.readFile(pinFile, 'utf8'));
}

export async function writeCjpmProvenance({binary, destination, platform, repository, commit}) {
  const value = {
    schema: 1,
    component: 'cjpm',
    platform,
    source: {
      status: SOURCE_PROVENANCE_RESOLVED,
      repository: requireString(repository, 'cjpm source repository'),
      commit: requireMatch(commit, SHA40, 'cjpm source commit'),
    },
    artifact: {
      path: path.basename(binary),
      sha256: await fileSha256(binary),
    },
  };
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

export async function verifyCjpmProvenance({
  binary,
  sidecar,
  platform,
  expectedRepository,
  expectedCommit,
}) {
  const label = 'cjpm provenance';
  const value = await readJson(sidecar, label);
  requireIdentity(value, {component: 'cjpm', platform}, label);
  if (value.source?.status !== SOURCE_PROVENANCE_RESOLVED) {
    throw new Error(`${label}.source.status must be ${SOURCE_PROVENANCE_RESOLVED}; got ${
      value.source?.status || SOURCE_PROVENANCE_UNRESOLVED}`);
  }
  const repository = requireString(expectedRepository, 'expected cjpm source repository');
  const commit = requireMatch(expectedCommit, SHA40, 'expected cjpm source commit');
  if (value.source?.repository !== repository || value.source?.commit !== commit) {
    throw new Error(`${label} source mismatch: ${value.source?.repository || '<empty>'}@${value.source?.commit || '<empty>'}`);
  }
  const artifactName = platform === 'windows-x64' ? 'cjpm.exe' : 'cjpm';
  if (value.artifact?.path !== artifactName) {
    throw new Error(`${label} artifact path mismatch: ${value.artifact?.path || '<empty>'} != ${artifactName}`);
  }
  const recorded = requireMatch(value.artifact?.sha256, SHA256, `${label}.artifact.sha256`);
  const actual = await fileSha256(binary);
  if (recorded !== actual) throw new Error(`${label} binary SHA-256 mismatch: ${recorded} != ${actual}`);
  return value;
}
