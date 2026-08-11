import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export const BASE_SDK_PROVENANCE = 'BASE-SDK-PROVENANCE.json';
export const CJPM_PROVENANCE = 'CJPM-PROVENANCE.json';
export const HLE_PROVENANCE = 'HLE-PROVENANCE.json';
export const SOURCE_PROVENANCE_RESOLVED = 'resolved';
export const SOURCE_PROVENANCE_NOT_APPLICABLE = 'not-applicable';
export const SOURCE_PROVENANCE_UNRESOLVED = 'unresolved';
export const BASE_SDK_SOURCE_REASON =
  'Official nightly SDKs are multi-repository integration artifacts and do not have a single source commit.';

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const NIGHTLY_RELEASE_REPOSITORY = 'https://gitcode.com/Cangjie/nightly_build';
const NIGHTLY_RELEASE_BASE = `${NIGHTLY_RELEASE_REPOSITORY}/releases/download`;
const PINNED_BASE_SDK_VERSION = '1.2.0-alpha.20260721165458';

const baseSdkPlatforms = new Map([
  ['linux-x64', {
    os: 'linux', arch: 'x64', extension: '.tar.gz', size: 201639272,
    sha256: '4490fd0ac553f4122b90ab6cb0d437bc6a5325fbe81e43643cc01d484a0dc0d6',
  }],
  ['linux-aarch64', {
    os: 'linux', arch: 'aarch64', extension: '.tar.gz', size: 203100802,
    sha256: '461e8d1c2f81b540d9c270c92333e57af60980e8c0e1f59b051f6c8906449320',
  }],
  ['darwin-x64', {
    os: 'mac', arch: 'x64', extension: '.tar.gz', size: 173277379,
    sha256: '7546e5cbf8cffce60d91f65de17c4d7fb88abb960e4238fad0a26765182eef07',
  }],
  ['darwin-arm64', {
    os: 'mac', arch: 'aarch64', extension: '.tar.gz', size: 164273695,
    sha256: '4c2b55321697bcac5da5e8ba349fc4405212c4e0f3e7105cfa78457a14810138',
  }],
  ['windows-x64', {
    os: 'windows', arch: 'x64', extension: '.zip', size: 263516382,
    sha256: 'fa121323c4b411501690fe67169982215a7872e671df8007d85070c8afffa672',
  }],
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

async function fileIdentity(file) {
  const stat = await fs.stat(file);
  if (!stat.isFile()) throw new Error(`base SDK archive is not a file: ${file}`);
  return {size: stat.size, sha256: await fileSha256(file)};
}

async function atomicWriteFile(destination, contents) {
  const directory = path.dirname(destination);
  const temporary = path.join(directory, `.${path.basename(destination)}.${crypto.randomUUID()}.partial`);
  await fs.mkdir(directory, {recursive: true});
  try {
    const handle = await fs.open(temporary, 'wx');
    try {
      await handle.writeFile(contents);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await fs.rename(temporary, destination);
  } catch (error) {
    await fs.rm(temporary, {force: true});
    throw error;
  }
}

async function atomicCopyFile(source, destination) {
  const directory = path.dirname(destination);
  const temporary = path.join(directory, `.${path.basename(destination)}.${crypto.randomUUID()}.partial`);
  await fs.mkdir(directory, {recursive: true});
  try {
    await fs.copyFile(source, temporary);
    const handle = await fs.open(temporary, 'r');
    try {
      await handle.sync();
    } finally {
      await handle.close();
    }
    await fs.rename(temporary, destination);
  } catch (error) {
    await fs.rm(temporary, {force: true});
    throw error;
  }
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
  if (version !== PINNED_BASE_SDK_VERSION) {
    throw new Error(`base SDK release has no pinned archive identity: ${version}`);
  }
  const archive = `cangjie-sdk-${tuple.os}-${tuple.arch}-${version}${tuple.extension}`;
  return {
    archive,
    url: `${NIGHTLY_RELEASE_BASE}/${version}/${archive}`,
    releaseRepository: NIGHTLY_RELEASE_REPOSITORY,
    version,
    size: tuple.size,
    sha256: tuple.sha256,
  };
}

export async function writeBaseSdkProvenance({archive, destination, platform, toolchain}) {
  const expected = baseSdkDownload(platform, toolchain);
  if (path.basename(archive) !== expected.archive) {
    throw new Error(`base SDK archive name mismatch: ${path.basename(archive)} != ${expected.archive}`);
  }
  const actual = await fileIdentity(archive);
  if (actual.sha256 !== expected.sha256) {
    throw new Error(`base SDK archive SHA-256 mismatch for ${platform}: expected ${expected.sha256}, got ${actual.sha256}`);
  }
  if (actual.size !== expected.size) {
    throw new Error(`base SDK archive size mismatch for ${platform}: expected ${expected.size}, got ${actual.size}`);
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
      size: actual.size,
      sha256: actual.sha256,
    },
  };
  await atomicWriteFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

export async function writeCjpmProvenance(options) {
  return writeComponentProvenance({component: 'cjpm', ...options});
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
  if (value.artifact?.size !== undefined &&
      (!Number.isSafeInteger(value.artifact.size) || value.artifact.size < 0)) {
    throw new Error(`${label}.artifact.size is invalid: ${value.artifact.size}`);
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
  const actual = await fileIdentity(archive);
  if (value.artifact.size !== undefined && value.artifact.size !== actual.size) {
    throw new Error(`${label} archive size mismatch: ${value.artifact.size} != ${actual.size}`);
  }
  if (recorded !== actual.sha256) {
    throw new Error(`${label} archive SHA-256 mismatch: ${recorded} != ${actual.sha256}`);
  }
  return value;
}

export async function persistBaseSdkProvenance({archive, sidecar, toolchainDir, platform, toolchain}) {
  const expected = baseSdkDownload(platform, toolchain);
  const value = await verifyBaseSdkProvenance({archive, sidecar, platform, toolchain});
  const root = path.resolve(toolchainDir);
  const rootStat = await fs.stat(root);
  if (!rootStat.isDirectory()) throw new Error(`base SDK toolchain is not a directory: ${root}`);

  const metadata = path.join(root, '.cjv');
  const cacheRelative = path.join('archives', 'sha256', value.artifact.sha256, expected.archive);
  const cachedArchive = path.join(metadata, cacheRelative);
  let cachedIdentity;
  try {
    cachedIdentity = await fileIdentity(cachedArchive);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const archiveSize = value.artifact.size ?? (await fs.stat(archive)).size;
  if (cachedIdentity?.sha256 !== value.artifact.sha256 || cachedIdentity?.size !== archiveSize) {
    await atomicCopyFile(archive, cachedArchive);
    cachedIdentity = await fileIdentity(cachedArchive);
  }
  if (cachedIdentity.sha256 !== value.artifact.sha256 || cachedIdentity.size !== archiveSize) {
    throw new Error(`base SDK content-addressed cache mismatch: ${cachedArchive}`);
  }

  const durable = {
    ...value,
    artifact: {
      ...value.artifact,
      size: archiveSize,
      cache_path: cacheRelative.split(path.sep).join('/'),
    },
  };
  const durableSidecar = path.join(metadata, BASE_SDK_PROVENANCE);
  await atomicWriteFile(durableSidecar, `${JSON.stringify(durable, null, 2)}\n`);
  return {provenance: durable, sidecar: durableSidecar, cachedArchive};
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

// hle is built from the same cangjie-tools checkout the source pin names, so
// its sidecar is pinned the same way cjpm's is.
export function parseToolsPin(text) {
  const values = Object.fromEntries(text.split(/\r?\n/).filter(Boolean).map(line => {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid source pin line: ${line}`);
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
  return {
    repository: requireString(values.TOOLS_SRC_URL, 'TOOLS_SRC_URL'),
    commit: requireMatch(values.TOOLS_REF, SHA40, 'TOOLS_REF'),
  };
}

export async function readToolsPin(pinFile) {
  return parseToolsPin(await fs.readFile(pinFile, 'utf8'));
}

export async function readCjpmPin(pinFile) {
  return parseCjpmPin(await fs.readFile(pinFile, 'utf8'));
}

// The sidecar shape is the same for every source-built tool we ship; only the
// component name and the binary's name change. cjpm keeps its own entry points
// so its thirty-odd call sites stay untouched.
export async function writeComponentProvenance({component, binary, destination, platform, repository, commit}) {
  const value = {
    schema: 1,
    component: requireString(component, 'component'),
    platform,
    source: {
      status: SOURCE_PROVENANCE_RESOLVED,
      repository: requireString(repository, `${component} source repository`),
      commit: requireMatch(commit, SHA40, `${component} source commit`),
    },
    artifact: {
      path: path.basename(binary),
      sha256: await fileSha256(binary),
    },
  };
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

export async function verifyComponentProvenance({
  component,
  artifactName,
  binary,
  sidecar,
  platform,
  expectedRepository,
  expectedCommit,
}) {
  const label = `${component} provenance`;
  const value = await readJson(sidecar, label);
  requireIdentity(value, {component, platform}, label);
  if (value.source?.status !== SOURCE_PROVENANCE_RESOLVED) {
    throw new Error(`${label}.source.status must be ${SOURCE_PROVENANCE_RESOLVED}; got ${
      value.source?.status || SOURCE_PROVENANCE_UNRESOLVED}`);
  }
  const repository = requireString(expectedRepository, `expected ${component} source repository`);
  const commit = requireMatch(expectedCommit, SHA40, `expected ${component} source commit`);
  if (value.source?.repository !== repository || value.source?.commit !== commit) {
    throw new Error(`${label} source mismatch: ${value.source?.repository || '<empty>'}@${value.source?.commit || '<empty>'}`);
  }
  if (value.artifact?.path !== artifactName) {
    throw new Error(`${label} artifact path mismatch: ${value.artifact?.path || '<empty>'} != ${artifactName}`);
  }
  const recorded = requireMatch(value.artifact?.sha256, SHA256, `${label}.artifact.sha256`);
  const actual = await fileSha256(binary);
  if (recorded !== actual) throw new Error(`${label} binary SHA-256 mismatch: ${recorded} != ${actual}`);
  return value;
}

export async function verifyCjpmProvenance(options) {
  return verifyComponentProvenance({
    component: 'cjpm',
    artifactName: options.platform === 'windows-x64' ? 'cjpm.exe' : 'cjpm',
    ...options,
  });
}
