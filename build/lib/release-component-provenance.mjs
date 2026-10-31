import {TOOL_NAMES,TOOL_PUBLIC_NAMES} from '../srcbuild/tool-layout.mjs';
import {sourceToolPayloads} from '../../ci/release/source-tool-payloads.mjs';
import {getTarget} from './targets.mjs';
import {sdkPlatform,entryPlatformName} from '../../ci/bootstrap/sdk-platform.mjs';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {readHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';

export const BASE_SDK_PROVENANCE = 'BASE-SDK-PROVENANCE.json';
export const CJPM_PROVENANCE = 'CJPM-PROVENANCE.json';
export const HLE_PROVENANCE = 'HLE-PROVENANCE.json';
// Required shared-tool products include their target native support payloads.
export const SOURCE_TOOLS_NATIVE = Object.freeze(TOOL_NAMES.filter(name=>!['cjpm','hle'].includes(name)).map(name=>TOOL_PUBLIC_NAMES[name]??name));
export const SOURCE_TOOLS_WINDOWS = SOURCE_TOOLS_NATIVE;

// hle and cjpm retain their dedicated producer/install paths.
export function sourceOwnedTools(isWindows) {
  return [...(isWindows ? SOURCE_TOOLS_WINDOWS : SOURCE_TOOLS_NATIVE), 'hle'];
}
export const SOURCE_PROVENANCE_RESOLVED = 'resolved';
export const SOURCE_PROVENANCE_NOT_APPLICABLE = 'not-applicable';
export const SOURCE_PROVENANCE_UNRESOLVED = 'unresolved';
export const BASE_SDK_SOURCE_REASON =
  'Official nightly SDKs are multi-repository integration artifacts and do not have a single source commit.';

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const NIGHTLY_RELEASE_REPOSITORY = 'https://gitcode.com/Cangjie/nightly_build';
const NIGHTLY_RELEASE_BASE = `${NIGHTLY_RELEASE_REPOSITORY}/releases/download`;
export const RELEASE_HOST_TOOLCHAIN = readHostToolchainPin();
const baseSdkIdentities = JSON.parse(await fs.readFile(
  new URL('../../ci/release/base-sdk-identities.json', import.meta.url), 'utf8',
));
const baseSdkPlatforms = new Map(Object.entries(baseSdkIdentities.platforms));

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

export function baseSdkDownload(platform, toolchain, {selectedHost = false} = {}) {
  const tuple = baseSdkPlatforms.get(platform);
  if (!tuple) throw new Error(`unsupported base SDK platform: ${platform}`);
  const version = requireString(toolchain, 'base SDK toolchain').replace(/^nightly-/, '');
  const current = version === readHostToolchainPin(platform).replace(/^nightly-/, '') && version === (tuple.version || baseSdkIdentities.version);
  const identity = current ? tuple : selectedHost && tuple.registeredHosts?.[version];
  if (!identity) {
    throw new Error(`base SDK release has no pinned archive identity: ${version}`);
  }
  const {spec} = getTarget(platform);
  const archive = `cangjie-sdk-${spec.sdkName}-${version}.${spec.archiveFormat}`;
  return {
    archive,
    url: `${NIGHTLY_RELEASE_BASE}/${version}/${archive}`,
    releaseRepository: NIGHTLY_RELEASE_REPOSITORY,
    version,
    size: identity.size,
    sha256: identity.sha256,
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

// CJPM and HLE are packages of the same selected cjcj-tools source.
export function parseCjpmPin(text) { return parseToolsPin(text); }

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

export async function safePayloadPath(root, relative) {
  if (typeof relative !== 'string' || !relative || path.isAbsolute(relative) || path.win32.isAbsolute(relative)
      || relative.includes('\\') || relative.includes('\0') || relative.split('/').some(p => !p || p === '.' || p === '..')) {
    throw new Error(`unsafe payload path: ${relative}`);
  }
  root = await fs.realpath(root);
  let current=root;
  for (const part of relative.split('/')) {
    current=path.join(current,part);
    const stat=await fs.lstat(current).catch(e=>{if(e.code==='ENOENT')return null;throw e;});
    if(stat?.isSymbolicLink())throw new Error(`payload path contains a link: ${current}`);
  }
  return current;
}
export async function artifactSourceBinary(binary,sdk,platform) {
  const recipe=await fs.readFile(binary+'.entry','utf8').catch(e=>{if(e.code==='ENOENT')return null;throw e;});
  if(recipe===null)return binary;
  const lines=recipe.trimEnd().split('\n');
  const target=getTarget(platform).spec.llvmPlatform;
  if(lines[0]!=='cjcj-sdk-entry-v1'||lines[3]!==entryPlatformName(target)||lines[4]!=='native-target:'+sdkPlatform(target).arch)throw new Error('artifact target recipe mismatch');
  let root=path.dirname(await fs.realpath(binary));
  const ascent=Number(lines[1]);
  if(!Number.isInteger(ascent)||ascent<0||ascent>32)throw new Error('artifact recipe ascent');
  for(let i=0;i<ascent;i++)root=path.dirname(root);
  if(root!==await fs.realpath(sdk))throw new Error('artifact recipe SDK root mismatch');
  return safePayloadPath(root,lines[2]);
}

export function requireToolPayloads(component, platform, payloads) {
  if (!Array.isArray(payloads)) throw new Error(`${component} payloads must be an array`);
  const paths=payloads.map(p=>p.path);
  if(new Set(paths).size!==paths.length)throw new Error(`${component} duplicate payload path`);
  if(component==='cjpm'||component==='compiler')return; // Dedicated producers check their config and final std contracts.
  for(const required of sourceToolPayloads(component,platform)) {
    if(!paths.includes(required))throw new Error(`${component} missing required payload: ${required}`);
  }
}

async function requireHleClosure(root,platform) {
  const suffix=sourceToolPayloads('hle',platform)[1].endsWith('.exe')?'.exe':'';
  for(const relative of ['tools/dtsparser/analysis.js','tools/dtsparser/node_modules/.bin/cjbind'+suffix]) {
    if(!(await fs.lstat(await safePayloadPath(root,relative))).isFile())throw new Error('HLE_DEPENDENCY_FILE '+relative);
  }
  for(const [name,version]of [['typescript','4.9.5'],['https-proxy-agent','7.0.6']]) {
    const prefix='tools/dtsparser/node_modules/'+name+'/';
    const pkg=JSON.parse(await fs.readFile(await safePayloadPath(root,prefix+'package.json'),'utf8'));
    if(pkg.name!==name||pkg.version!==version)throw new Error('HLE_DEPENDENCY_VERSION '+name);
    const main=String(pkg.main||'index.js').replace(/^\.\//,'');
    if(!(await fs.lstat(await safePayloadPath(root,prefix+main))).isFile())throw new Error('HLE_DEPENDENCY_MAIN '+name);
  }
}

// The sidecar shape is the same for every source-built tool we ship; only the
// component name and the binary's name change. cjpm keeps its own entry points
// so its thirty-odd call sites stay untouched.
export async function writeComponentProvenance({component, binary, destination, platform, repository, commit, payloads = []}) {
  requireToolPayloads(component,platform,payloads);
  if(component==='hle')await requireHleClosure(path.dirname(binary),platform);
  for(const entry of payloads) {
    const target=await safePayloadPath(path.dirname(binary),entry.path);
    const stat=await fs.lstat(target);
    if(entry.type==='directory'?!stat.isDirectory():entry.type!=='file'||!stat.isFile()) throw new Error(`invalid payload type: ${entry.path}`);
  }
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
    // The files beside the binary that the tool reads at run time. Recorded by
    // path and content so the consumer can check it received the same ones,
    // rather than only that a file of that name exists.
    payloads: await Promise.all(payloads.map(async entry => ({
      path: requireString(entry.path, `${component} payload path`),
      type: entry.type === 'directory' ? 'directory' : 'file',
      sha256: await payloadDigest(await safePayloadPath(path.dirname(binary), entry.path)),
    }))),
  };
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

// A directory payload is digested over its contents in sorted relative-path
// order, so a differing file or a missing one changes the digest. Returns null
// for an absent path, which the verifier treats as a mismatch rather than as
// "nothing to check".
async function payloadDigest(target) {
  let stat;
  try {
    stat = await fs.lstat(target);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
  if (stat.isFile()) return fileSha256(target);
  if (!stat.isDirectory()) throw new Error(`payload is neither file nor directory: ${target}`);
  const hash = crypto.createHash('sha256');
  const walk = async (directory, prefix) => {
    for (const name of (await fs.readdir(directory)).sort()) {
      const child = path.join(directory, name);
      const childStat = await fs.lstat(child);
      const relative = prefix ? `${prefix}/${name}` : name;
      if (childStat.isDirectory()) {
        hash.update(`d ${relative}\n`);
        await walk(child, relative);
      } else if (childStat.isFile()) {
        hash.update(`f ${relative} ${await fileSha256(child)}\n`);
      } else {
        throw new Error(`payload contains a non-regular file: ${child}`);
      }
    }
  };
  await walk(target, '');
  return hash.digest('hex');
}

export async function verifyComponentProvenance({
  component,
  artifactName,
  binary,
  sidecar,
  platform,
  expectedRepository,
  expectedCommit,
  payloadRoot,
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
  // The binary is not the whole tool. Check the recorded payload digests against
  // what actually arrived, so a package cannot keep the official configuration or
  // implementation library while installing our front end: an absent payload is a
  // mismatch, not an unconstrained one.
  const payloads = value.payloads;
  if (!Array.isArray(payloads)) {
    throw new Error(`${label}.payloads must be an array of {path,type,sha256}`);
  }
  requireToolPayloads(component,platform,payloads);
  if(component==='hle')await requireHleClosure(payloadRoot||path.dirname(binary),platform);
  for (const entry of payloads) {
    const relative = requireString(entry?.path, `${label} payload path`);
    if (entry?.type !== 'file' && entry?.type !== 'directory') {
      throw new Error(`${label} payload ${relative} has invalid type: ${entry?.type}`);
    }
    const expected = requireMatch(entry.sha256, SHA256, `${label} payload ${relative} sha256`);
    const target = await safePayloadPath(payloadRoot || path.dirname(binary), relative);
    const stat = await fs.lstat(target).catch(e=>{if(e.code==='ENOENT')return null;throw e;});
    if(stat && (entry.type==='directory' ? !stat.isDirectory() : !stat.isFile())) throw new Error(`${label} payload type mismatch: ${relative}`);
    const landed = await payloadDigest(target);
    if (landed === null) throw new Error(`${label} payload is missing beside the artifact: ${relative}`);
    if (landed !== expected) {
      throw new Error(`${label} payload ${relative} differs from the recorded content: ${landed} != ${expected}`);
    }
  }
  return value;
}

export async function verifyCjpmProvenance(options) {
  return verifyComponentProvenance({
    component: 'cjpm',
    artifactName: options.platform === 'windows-x64' ? 'cjpm.exe' : 'cjpm',
    ...options,
  });
}
