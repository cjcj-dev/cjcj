import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export const GATE_APPARATUS_PROVENANCE = 'GATE-APPARATUS.json';
export const GATE_APPARATUS_COMPONENT = 'acceptance-apparatus';
export const REVIEWED_GATE_HOST_TOOLCHAIN = 'nightly-1.2.0-alpha.20260721165458';
export const GATE_HOST_MASK_SYMBOL = 'g_cjLoadBadMask';
export const EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT = 0;

export const KNOWN_GATE_APPARATUS_LIMITATIONS = Object.freeze({
  text: [
    'The acceptance gates run the self-host compiler on the 2026-07-21 nightly host runtime.',
    'That runtime predates the survivor gate and GCLOG, and its PostTraceBarrier::ReadReference',
    'checks IsCurrentPointer(tmpField); current cangjie-runtime main uses !IsOldPointer instead',
    '(zc9fix, ASSERT_TOO_NARROW). Parallel bcgate and codegen smoke failures were captured in',
    'that host runtime. Replacing it with the current-generation uncoloured host changed smoke',
    'from 13/15 to 0/15, so the gate remains on the previous released toolchain. This record is',
    'apparatus provenance only: it does not classify future failures or relax difftest or VERIFY.',
  ].join(' '),
  evidence: [
    {
      report: 'REPORT-gateconc.md',
      core: '/root/nilclass-run/cores/core.3293700',
      fact: 'pc_mod=libcangjie-runtime.so@0721; PostTraceBarrier::ReadReference; IsCurrentPointer(tmpField)',
    },
    {
      report: 'REPORT-codegensmoke.md',
      core: '/root/codegensmoke-run/crashes/cand_r2_gdb.txt',
      fact: 'candidate 5/5 failed; four core/gdb captures ended in 0721 StackOverflow, RegionManager, or FormatLog; none entered pinbuild ff2339b5 mask1',
    },
    {
      report: 'REPORT-gatehost.md',
      core: '/root/gatehost-run/evidence/smoke_newhost/',
      fact: 'current-generation uncoloured host changed smoke from 13/15 to 0/15',
    },
  ],
  unchanged_absolute_gates: 'difftest TOTAL==PASS and MISMATCH=0 and FAIL=0; VERIFY-EXIT=0',
});

const SHA256 = /^[0-9a-f]{64}$/;
const runtimePaths = new Map([
  ['linux-x64', ['runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so']],
  ['linux-aarch64', ['runtime/lib/linux_aarch64_cjnative/libcangjie-runtime.so']],
  ['darwin-x64', ['runtime/lib/darwin_x86_64_cjnative/libcangjie-runtime.dylib']],
  ['darwin-arm64', ['runtime/lib/darwin_aarch64_cjnative/libcangjie-runtime.dylib']],
  ['windows-x64', [
    'runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll',
    'runtime/lib/windows_x86_64_cjnative/cangjie-runtime.dll',
  ]],
]);

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${label} is empty`);
  return value.trim();
}

function requireSha256(value, label) {
  const text = requireString(value, label);
  if (!SHA256.test(text)) throw new Error(`${label} is invalid: ${text}`);
  return text;
}

function requirePlatform(platform) {
  if (!runtimePaths.has(platform)) throw new Error(`unsupported gate apparatus platform: ${platform}`);
  return platform;
}

function normalizeRelative(value) {
  return value.split(path.sep).join('/');
}

function toolchainVersion(toolchain) {
  return toolchain.replace(/^nightly-/, '');
}

function requireReviewedToolchain(value, label = 'gate host toolchain') {
  const toolchain = requireString(value, label);
  if (toolchain !== REVIEWED_GATE_HOST_TOOLCHAIN) {
    throw new Error(`${label} has no reviewed apparatus record: ${toolchain} != ${REVIEWED_GATE_HOST_TOOLCHAIN}`);
  }
  return toolchain;
}

function probeArguments(platform) {
  if (platform.startsWith('linux-')) return ['-D', '--defined-only'];
  if (platform.startsWith('darwin-')) return ['-gU'];
  if (platform === 'windows-x64') return ['-g', '--defined-only'];
  throw new Error(`unsupported gate apparatus platform: ${platform}`);
}

function probeCommand(platform) {
  return ['nm', ...probeArguments(platform)].join(' ');
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

function requireKnownLimitations(value, label) {
  if (JSON.stringify(value) !== JSON.stringify(KNOWN_GATE_APPARATUS_LIMITATIONS)) {
    throw new Error(`${label} does not match the reviewed G8 apparatus evidence`);
  }
  return value;
}

function requireBaseSdk(value, {platform, toolchain}, label) {
  if (value?.schema !== 1 || value?.component !== 'base-sdk' || value?.platform !== platform) {
    throw new Error(`${label} does not identify base-sdk for ${platform}`);
  }
  if (value.release?.version !== toolchainVersion(toolchain)) {
    throw new Error(`${label}.release.version does not match ${toolchain}`);
  }
  return {
    release_repository: requireString(value.release?.repository, `${label}.release.repository`),
    version: value.release.version,
    download_url: requireString(value.release?.download_url, `${label}.release.download_url`),
    archive_path: requireString(value.artifact?.path, `${label}.artifact.path`),
    archive_sha256: requireSha256(value.artifact?.sha256, `${label}.artifact.sha256`),
  };
}

export function parseGateHostToolchain(text) {
  const values = new Map();
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^([A-Z][A-Z0-9_]*)=(.*)$/);
    if (!match) throw new Error(`invalid toolchain pin line: ${raw}`);
    values.set(match[1], match[2]);
  }
  return requireReviewedToolchain(values.get('CJCJ_TOOLCHAIN'), 'CJCJ_TOOLCHAIN');
}

export async function resolveGateHostRuntime({sdk, platform}) {
  requirePlatform(platform);
  const root = path.resolve(sdk);
  for (const relative of runtimePaths.get(platform)) {
    const file = path.join(root, ...relative.split('/'));
    try {
      if ((await fs.stat(file)).isFile()) return {file, relative};
    } catch {}
  }
  throw new Error(`gate host runtime is missing under ${root}: ${runtimePaths.get(platform).join(' or ')}`);
}

export function probeGateHostMaskSymbol({runtime, platform}) {
  requirePlatform(platform);
  const args = [...probeArguments(platform), runtime];
  const result = spawnSync('nm', args, {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  if (result.status !== 0) {
    throw new Error(`gate host symbol probe failed (${probeCommand(platform)}): ${
      (result.stderr || result.stdout || `status=${result.status}`).trim()}`);
  }
  const symbols = result.stdout.split(/\r?\n/).filter(Boolean);
  if (symbols.length === 0) throw new Error(`gate host symbol probe returned no symbols: ${runtime}`);
  return {
    command: probeCommand(platform),
    count: symbols.filter(line => line.includes(GATE_HOST_MASK_SYMBOL)).length,
  };
}

export function validateGateApparatusProvenance(value, {platform, expectedToolchain = ''} = {}) {
  const label = 'gate apparatus provenance';
  requirePlatform(platform);
  if (value?.schema !== 1) throw new Error(`${label}.schema must be 1`);
  if (value?.component !== GATE_APPARATUS_COMPONENT) {
    throw new Error(`${label}.component must be ${GATE_APPARATUS_COMPONENT}`);
  }
  if (value?.platform !== platform) {
    throw new Error(`${label}.platform mismatch: ${value?.platform || '<empty>'} != ${platform}`);
  }
  const toolchain = requireReviewedToolchain(value.gate_host_toolchain);
  if (expectedToolchain && toolchain !== expectedToolchain) {
    throw new Error(`${label}.gate_host_toolchain mismatch: ${toolchain} != ${expectedToolchain}`);
  }
  const allowedRuntimePaths = runtimePaths.get(platform);
  const runtimePath = requireString(value.host_runtime?.path, `${label}.host_runtime.path`);
  if (!allowedRuntimePaths.includes(runtimePath)) {
    throw new Error(`${label}.host_runtime.path is not canonical for ${platform}: ${runtimePath}`);
  }
  requireSha256(value.host_runtime?.sha256, `${label}.host_runtime.sha256`);
  if (value.host_runtime?.g_cjLoadBadMask_count !== EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT) {
    throw new Error(`${label}.host_runtime.g_cjLoadBadMask_count must be ${EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT}`);
  }
  if (value.host_runtime?.symbol_probe !== probeCommand(platform)) {
    throw new Error(`${label}.host_runtime.symbol_probe mismatch: ${value.host_runtime?.symbol_probe || '<empty>'}`);
  }
  const baseSdk = value.base_sdk;
  if (baseSdk?.version !== toolchainVersion(toolchain)) {
    throw new Error(`${label}.base_sdk.version does not match ${toolchain}`);
  }
  for (const name of ['release_repository', 'download_url', 'archive_path']) {
    requireString(baseSdk?.[name], `${label}.base_sdk.${name}`);
  }
  requireSha256(baseSdk?.archive_sha256, `${label}.base_sdk.archive_sha256`);
  requireKnownLimitations(value.known_apparatus_limitations, `${label}.known_apparatus_limitations`);
  return value;
}

export async function readGateApparatusProvenance({file, platform, expectedToolchain = ''}) {
  return validateGateApparatusProvenance(await readJson(file, 'gate apparatus provenance'), {
    platform,
    expectedToolchain,
  });
}

export async function writeGateApparatusProvenance({
  runtime,
  runtimePath,
  destination,
  platform,
  toolchain,
  baseSdkProvenance,
}) {
  requirePlatform(platform);
  const reviewedToolchain = requireReviewedToolchain(toolchain);
  const normalizedRuntimePath = normalizeRelative(runtimePath);
  if (!runtimePaths.get(platform).includes(normalizedRuntimePath)) {
    throw new Error(`gate host runtime path is not canonical for ${platform}: ${normalizedRuntimePath}`);
  }
  const probe = probeGateHostMaskSymbol({runtime, platform});
  if (probe.count !== EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT) {
    throw new Error(`gate host ${GATE_HOST_MASK_SYMBOL} count must be ${EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT}, got ${probe.count}`);
  }
  const value = {
    schema: 1,
    component: GATE_APPARATUS_COMPONENT,
    platform,
    gate_host_toolchain: reviewedToolchain,
    base_sdk: requireBaseSdk(baseSdkProvenance, {platform, toolchain: reviewedToolchain}, 'base SDK provenance'),
    host_runtime: {
      path: normalizedRuntimePath,
      sha256: await fileSha256(runtime),
      g_cjLoadBadMask_count: probe.count,
      symbol_probe: probe.command,
    },
    known_apparatus_limitations: KNOWN_GATE_APPARATUS_LIMITATIONS,
  };
  validateGateApparatusProvenance(value, {platform, expectedToolchain: reviewedToolchain});
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return value;
}

export async function verifyGateApparatusProvenance({
  runtime,
  sidecar,
  platform,
  expectedToolchain,
  expectedBaseSdkArchiveSha256,
}) {
  const value = await readGateApparatusProvenance({file: sidecar, platform, expectedToolchain});
  if (value.base_sdk.archive_sha256 !== expectedBaseSdkArchiveSha256) {
    throw new Error(`gate apparatus base SDK SHA-256 mismatch: ${value.base_sdk.archive_sha256} != ${expectedBaseSdkArchiveSha256}`);
  }
  const actualSha256 = await fileSha256(runtime);
  if (value.host_runtime.sha256 !== actualSha256) {
    throw new Error(`gate apparatus host runtime SHA-256 mismatch: ${value.host_runtime.sha256} != ${actualSha256}`);
  }
  const probe = probeGateHostMaskSymbol({runtime, platform});
  if (probe.count !== value.host_runtime.g_cjLoadBadMask_count) {
    throw new Error(`gate apparatus ${GATE_HOST_MASK_SYMBOL} count mismatch: ${value.host_runtime.g_cjLoadBadMask_count} != ${probe.count}`);
  }
  return value;
}

export function gateApparatusManifestSection(value, platform) {
  validateGateApparatusProvenance(value, {platform});
  return {
    gate_host_toolchain: value.gate_host_toolchain,
    host_runtime: value.host_runtime,
    known_apparatus_limitations: value.known_apparatus_limitations,
  };
}

export function validateGateApparatusManifestSection(value, platform) {
  requirePlatform(platform);
  requireReviewedToolchain(value?.gate_host_toolchain, 'acceptance_apparatus.gate_host_toolchain');
  const runtimePath = requireString(value?.host_runtime?.path, 'acceptance_apparatus.host_runtime.path');
  if (!runtimePaths.get(platform).includes(runtimePath)) {
    throw new Error(`acceptance_apparatus.host_runtime.path is not canonical for ${platform}: ${runtimePath}`);
  }
  requireSha256(value?.host_runtime?.sha256, 'acceptance_apparatus.host_runtime.sha256');
  if (value?.host_runtime?.g_cjLoadBadMask_count !== EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT) {
    throw new Error(`acceptance_apparatus.host_runtime.g_cjLoadBadMask_count must be ${EXPECTED_GATE_HOST_MASK_SYMBOL_COUNT}`);
  }
  if (value?.host_runtime?.symbol_probe !== probeCommand(platform)) {
    throw new Error(`acceptance_apparatus.host_runtime.symbol_probe mismatch: ${
      value?.host_runtime?.symbol_probe || '<empty>'}`);
  }
  requireKnownLimitations(value?.known_apparatus_limitations,
    'acceptance_apparatus.known_apparatus_limitations');
  return value;
}
