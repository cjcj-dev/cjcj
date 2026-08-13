import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  SOURCE_PROVENANCE_RESOLVED,
  SOURCE_PROVENANCE_UNRESOLVED,
  validateBaseSdkProvenance,
} from './release-component-provenance.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  gateApparatusManifestSection,
  readGateApparatusProvenance,
} from './release-gate-apparatus.mjs';

export const RELEASE_MANIFEST = 'RELEASE-MANIFEST.jsonl';
export const RELEASE_SIGNATURE_POLICY = 'SHA_ONLY';

// G14 主控裁决（0811 07:3x）：取 A —— 保留 FULL_YOUNG_SCAN + census。
//
// B 的判据是「撤 FYS 前，每一次 minor 都 remsetMiss=0 且 missBare=0」。今晚的 remset
// 修法把它从中位 13.2/minor 压到中位 0，但仍有离群：FYS=1 时 4/29、FYS=0 时 2/30
// （fysdecide，256MB，e75cdefd）。「每一次都 0」是严格的，所以 B 不成立。
//
// A 原文要求「用启动日志证明启用」，而产品路径没有那一行；实际有的是每次 minor 的
// [GCV2][setbitmap] ... fullYoung=1，并且有对照臂（FYS=0 时 fullYoung=0、set_n=0）。
// 每 minor 一次加对照臂比一行启动日志更强，所以这里改的是判据的形式而不是它的实质。
export const IDLE_WRITER_POLICY = 'FYS_CENSUS';

const STRUCTURAL_NOT_APPLICABLE_COMPONENTS = new Set(['base-sdk', GATE_APPARATUS_COMPONENT]);

function requireText(value, label) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) throw new Error(`${label} is empty`);
  return text;
}

function sourceCommit(value, component) {
  const commit = typeof value === 'string' ? value.trim() : '';
  if (!/^[0-9a-f]{40}(?:-dirty)?$/.test(commit)) {
    throw new Error(`${component} source commit must be a 40-character SHA; actual=${commit || '<empty>'}`);
  }
  return commit;
}

export function validateReleaseManifestSource(sourceValue, component) {
  const status = typeof sourceValue?.status === 'string'
    ? sourceValue.status.trim()
    : SOURCE_PROVENANCE_UNRESOLVED;
  if (status === SOURCE_PROVENANCE_UNRESOLVED) {
    throw new Error(`${component}.source.status is ${SOURCE_PROVENANCE_UNRESOLVED}; release provenance must resolve or explicitly be not applicable`);
  }
  if (status === SOURCE_PROVENANCE_NOT_APPLICABLE) {
    if (!STRUCTURAL_NOT_APPLICABLE_COMPONENTS.has(component) && !component.startsWith('tool-')) {
      throw new Error(`${component}.source.status must be ${SOURCE_PROVENANCE_RESOLVED}; got ${status}`);
    }
    if (sourceValue.repository !== SOURCE_PROVENANCE_NOT_APPLICABLE ||
        sourceValue.commit !== SOURCE_PROVENANCE_NOT_APPLICABLE) {
      throw new Error(`${component}.source repository and commit must both be ${SOURCE_PROVENANCE_NOT_APPLICABLE}`);
    }
    requireText(sourceValue.reason, `${component}.source.reason`);
    requireText(sourceValue.release_repository, `${component}.source.release_repository`);
    requireText(sourceValue.version, `${component}.source.version`);
    requireText(sourceValue.download_url, `${component}.source.download_url`);
    return sourceValue;
  }
  if (status !== SOURCE_PROVENANCE_RESOLVED) {
    throw new Error(`${component}.source.status must be ${SOURCE_PROVENANCE_RESOLVED}; got ${status}`);
  }
  const repository = requireText(sourceValue.repository, `${component}.source.repository`);
  const commit = requireText(sourceValue.commit, `${component}.source.commit`);
  if (/^unavailable:/i.test(repository) || /^unavailable:/i.test(commit)) {
    throw new Error(`${component}.source uses the forbidden legacy unavailable value`);
  }
  const expectedCommit = component === 'python' ? /^3\.11\.\d+$/ : /^[0-9a-f]{40}(?:-dirty)?$/;
  if (!expectedCommit.test(commit)) {
    throw new Error(`${component}.source.commit is invalid for resolved provenance: ${commit}`);
  }
  return sourceValue;
}

export function validateReleaseManifestArtifact(artifactValue, component) {
  const artifactPath = requireText(artifactValue?.path, `${component}.artifact.path`);
  const artifactSha256 = requireText(artifactValue?.sha256, `${component}.artifact.sha256`);
  if (/^unavailable:/i.test(artifactPath) || /^unavailable:/i.test(artifactSha256)) {
    throw new Error(`${component}.artifact uses the forbidden legacy unavailable value`);
  }
  if (!/^[0-9a-f]{64}$/.test(artifactSha256)) {
    throw new Error(`${component}.artifact.sha256 is invalid: ${artifactSha256}`);
  }
  return artifactValue;
}

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

async function fileExists(file) {
  if (!file) return false;
  try { return (await fs.stat(file)).isFile(); } catch { return false; }
}

function embeddedStamp(buffer, prefixes) {
  const values = new Set();
  const occurrences = Object.fromEntries(prefixes.map(prefix => [prefix, []]));
  for (const prefix of prefixes) {
    const marker = Buffer.from(`${prefix}:`);
    let offset = 0;
    while (offset < buffer.length) {
      const found = buffer.indexOf(marker, offset);
      if (found < 0) break;
      const begin = found + marker.length;
      let end = begin;
      while (end < buffer.length && /[0-9A-Za-z._-]/.test(String.fromCharCode(buffer[end]))) end += 1;
      const value = buffer.subarray(begin, end).toString('ascii');
      occurrences[prefix].push(value);
      if (value) values.add(`${prefix}:${value}`);
      offset = begin;
    }
  }
  let value;
  if (values.size === 0) value = 'no-stamp';
  else if (values.size === 1) [value] = values;
  else throw new Error(`conflicting embedded stamps (${[...values].sort().join(',')})`);
  return {value, occurrences};
}

function frozenCommit(value, component) {
  const commit = typeof value === 'string' ? value.trim() : '';
  if (!/^[0-9a-f]{40}$/.test(commit)) {
    throw new Error(`${component} frozen SHA must be a clean 40-character commit SHA; ` +
      `actual=${commit || '<empty>'}`);
  }
  return commit;
}

function stdCommit(text) {
  return text.match(/^STD_SOURCE_COMMIT\s*=\s*([0-9a-f]{40}(?:-dirty)?)$/m)?.[1] || '';
}

function assertFrozenStamp(artifactValue, component, prefix, frozen) {
  const occurrences = artifactValue.stamp_occurrences[prefix] || [];
  const rendered = occurrences.length
    ? occurrences.map(value => `${prefix}:${value || '<empty>'}`).join(', ')
    : '<none>';
  if (occurrences.length !== 1) {
    throw new Error(`${component} ${prefix} occurrence must be exactly 1; ` +
      `actual count=${occurrences.length}; actual stamps=${rendered}`);
  }
  const [actual] = occurrences;
  if (actual.endsWith('-dirty')) {
    throw new Error(`${component} ${prefix} must not be dirty; actual=${prefix}:${actual}`);
  }
  if (actual !== frozen) {
    throw new Error(`${component} ${prefix} must equal frozen SHA; ` +
      `actual=${actual || '<empty>'}; frozen=${frozen}`);
  }
}

// ── Cangjie-written components ────────────────────────────────────────────────
// A packaged executable is Cangjie-written when it references the runtime entry
// points the compiler emits. That is a structural property of the emitted code,
// not a name: `CJ_MCC_` cannot be renamed without breaking the load-time symbol
// contract, so it cannot drift the way a hard-coded artifact list does. Measured
// against the factory SDK (cjcj-pin-937877c8), this splits exactly the way the
// scope determination did: cjcov/cjpm/cjtrace-recover/hle carry the references,
// cjc/chir-dis/cjfmt/cjlint/cjprof/cjdb/LSPServer/LSPMacroServer carry none.
const CJ_RUNTIME_ENTRY_MARKER = Buffer.from('CJ_MCC_');
const TOOL_STAMP_PREFIX = 'CJTOOL-COMMIT';

function isCangjieBinary(bytes) {
  return bytes.indexOf(CJ_RUNTIME_ENTRY_MARKER) >= 0;
}

// Discovery, not a list. hle is wired today; cjcov and cjtrace-recover land when
// TOOLS_REF bumps; whatever Cangjie tool ships next is covered the moment it
// appears in the stage. A name list would have to be edited each time, and the
// edit is exactly what gets forgotten (arm-soak's hard-coded artifact name, and
// the four hard-coded counts in kkk2_gate.sh:195, are the same failure).
async function discoverCangjieTools(stage, exeSuffix) {
  const found = [];
  for (const dir of [path.join(stage, 'tools', 'bin'), path.join(stage, 'bin')]) {
    let entries;
    try {
      entries = await fs.readdir(dir, {withFileTypes: true});
    } catch {
      continue;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      if (!entry.isFile()) continue;
      if (exeSuffix && !entry.name.endsWith(exeSuffix)) continue;
      const file = path.join(dir, entry.name);
      const bytes = await fs.readFile(file);
      if (!isCangjieBinary(bytes)) continue;
      const base = exeSuffix ? entry.name.slice(0, -exeSuffix.length) : entry.name;
      found.push({component: `tool-${base}`, file});
    }
  }
  if (found.length === 0) {
    // Zero discovered is not a pass. Every release package ships at least cjpm,
    // so an empty result means the walk looked in the wrong place or the stage
    // is not populated — either way the manifest must not claim coverage.
    throw new Error('no Cangjie-written tool was found under tools/bin or bin; ' +
      'the package always ships at least cjpm, so this is an apparatus failure, not a clean tree');
  }
  return found;
}

// The stamp rule for Cangjie tools, with its own expiry built in.
//
// Today none of them carry CJTOOL-COMMIT: they are compiled by the stock driver
// and nothing injects a marker, so demanding one would fail every package. But
// "report-only until someone remembers" is how an exemption becomes permanent.
// So the exemption is keyed to observable state instead of to a date or a note:
// the moment ANY discovered tool carries the stamp, the build side has started
// stamping, and every one of them must carry a clean one. There is nothing to
// remember and nothing to switch off by hand.
function assertToolStamps(tools, sourceByComponent) {
  const owned = [];
  const unstamped = [];
  for (const tool of tools) {
    const sourceInfo = sourceByComponent.get(tool.component);
    const occurrences = tool.value.stamp_occurrences[TOOL_STAMP_PREFIX] || [];
    if (!sourceInfo) {
      if (occurrences.length) {
        throw new Error(`${tool.component} carries ${TOOL_STAMP_PREFIX} without a declared source`);
      }
      unstamped.push(tool.component);
      continue;
    }
    assertFrozenStamp(tool.value, tool.component, TOOL_STAMP_PREFIX, sourceInfo.commit);
    owned.push(tool.component);
  }
  return {enforced: owned.length > 0, owned, unstamped};
}

// ── std: reconcile the packaged bytes against the block PROVENANCE.txt already
//    carries ───────────────────────────────────────────────────────────────────
// The std row hashes PROVENANCE.txt, and PROVENANCE.txt ends with one
// `<sha256>  <relative path>` line per installed artifact (build/lib/provenance.mjs
// writeStdProvenance). Nothing ever read that block back, so swapping every std
// archive for a factory copy left the manifest byte-identical. The data was
// already there; only the reconciliation was missing.
//
// The comparison is by content, deliberately not by path: package_sdk.mjs owns
// the install-prefix -> stage mapping, and re-deriving it here would be a second
// copy of that logic that drifts away from the first.
function provenanceArtifactHashes(text) {
  const marker = text.indexOf('ARTIFACT-SHA256:');
  if (marker < 0) return null;
  const hashes = new Set();
  for (const line of text.slice(marker).split('\n').slice(1)) {
    const match = line.match(/^([0-9a-f]{64})\s\s(.+)$/);
    if (match) hashes.add(match[1]);
  }
  return hashes;
}

async function stagedStdFiles(stage) {
  const roots = [path.join(stage, 'modules'), path.join(stage, 'lib'), path.join(stage, 'runtime', 'lib')];
  const files = [];
  const walk = async dir => {
    let entries;
    try {
      entries = await fs.readdir(dir, {withFileTypes: true});
    } catch {
      return;
    }
    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(file);
      else if (entry.isFile() && /(^|[/\\])(std|libcangjie-std)/.test(file)) files.push(file);
    }
  };
  for (const root of roots) await walk(root);
  return files.sort();
}

async function reconcileStdArtifacts(stage, stdText) {
  const hashes = provenanceArtifactHashes(stdText);
  if (hashes === null) {
    throw new Error('std PROVENANCE.txt has no ARTIFACT-SHA256 block; ' +
      'the packaged std bytes cannot be tied to the build that produced them');
  }
  if (hashes.size === 0) {
    throw new Error('std PROVENANCE.txt ARTIFACT-SHA256 block is empty');
  }
  const staged = await stagedStdFiles(stage);
  const unmatched = [];
  let matched = 0;
  for (const file of staged) {
    if (hashes.has(await sha256(file))) matched += 1;
    else unmatched.push(packagedPath(stage, file));
  }
  if (matched === 0) {
    // Same shape as the empty-population guard: nothing verified is not a pass.
    throw new Error('no packaged std artifact matched PROVENANCE.txt ARTIFACT-SHA256; ' +
      `staged=${staged.length} provenance_entries=${hashes.size}`);
  }
  if (unmatched.length) {
    throw new Error(`${unmatched.length} packaged std artifact(s) are not in PROVENANCE.txt ` +
      `ARTIFACT-SHA256, so they are not from this std build: ${unmatched.slice(0, 8).join(', ')}` +
      `${unmatched.length > 8 ? ` (+${unmatched.length - 8} more)` : ''}`);
  }
  return {verified: matched, provenance_entries: hashes.size};
}

function packagedPath(stage, file) {
  return path.relative(stage, file).split(path.sep).join('/');
}

async function artifact(stage, file, reason, prefixes = []) {
  if (!await fileExists(file)) {
    throw new Error(`${reason}: ${file || '<empty>'}`);
  }
  const bytes = await fs.readFile(file);
  const stamps = embeddedStamp(bytes, prefixes);
  return {
    path: packagedPath(stage, file),
    sha256: await sha256(file),
    embedded_stamp: stamps.value,
    stamp_occurrences: stamps.occurrences,
  };
}

function source(repository, commit, component) {
  return {
    status: SOURCE_PROVENANCE_RESOLVED,
    repository: requireText(repository, `${component}.source.repository`),
    commit: sourceCommit(commit, component),
  };
}

function notApplicableSource(reason, extra = {}) {
  return {
    status: SOURCE_PROVENANCE_NOT_APPLICABLE,
    repository: SOURCE_PROVENANCE_NOT_APPLICABLE,
    commit: SOURCE_PROVENANCE_NOT_APPLICABLE,
    reason: requireText(reason, 'not-applicable source reason'),
    ...extra,
  };
}

function inheritedToolSource(baseSdk, component) {
  return notApplicableSource(`inherited unchanged from the base SDK: ${component}`, {
    release_repository: baseSdk.release.repository,
    version: baseSdk.release.version,
    download_url: baseSdk.release.download_url,
  });
}

function findExecutable(root, relative, exeSuffix) {
  return path.join(root, `${relative}${exeSuffix}`);
}

export async function writeReleaseManifest({
  stage,
  platform,
  exeSuffix = '',
  runtimeArtifact,
  stdProvenance = '',
  baseSdkId = '',
  baseSdkProvenance = undefined,
  gateApparatusArtifact = '',
  cjcjRepository = 'https://github.com/cjcj-dev/cjcj.git',
  cjcjCommit = '',
  runtimeRepository = 'https://github.com/cjcj-dev/cangjie-runtime.git',
  runtimeCommit = '',
  llvmRepository = 'https://github.com/cjcj-dev/cjcj-llvm.git',
  llvmCommit = '',
  stdRepository = '',
  cjpmRepository = '',
  cjpmCommit = '',
  // Supplied once TOOLS_REF lands; until then the discovered tools carry the
  // repository they were built from only if the caller says so, and the stamp
  // rule below falls back to "any clean SHA" rather than inventing one.
  toolsRepository = '',
  toolsCommit = '',
  // Per-tool source rows keep the forked cjpm pin distinct from TOOLS_REF used
  // by hle. A missing entry means the binary is inherited from the base SDK.
  toolSources = {},
  pythonArtifact = '',
  pythonMetadata = {},
  pythonMetadataArtifact = '',
  pythonRepository = 'https://github.com/python/cpython.git',
  pythonVersion = '',
  signaturePolicy = RELEASE_SIGNATURE_POLICY,
}) {
  const normalizedSignaturePolicy = typeof signaturePolicy === 'string' ? signaturePolicy.trim() : '';
  if (normalizedSignaturePolicy !== RELEASE_SIGNATURE_POLICY) {
    throw new Error(`signature_policy must be ${RELEASE_SIGNATURE_POLICY}, got ${normalizedSignaturePolicy || '<empty>'}`);
  }
  const frozen = {
    cjcj: frozenCommit(cjcjCommit, 'cjcj'),
    runtime: frozenCommit(runtimeCommit, 'runtime'),
    llvm: frozenCommit(llvmCommit, 'LLVM'),
  };
  if (!/^3\.11\.\d+$/.test(pythonVersion)) {
    throw new Error(`python version must be exact 3.11.x, got ${pythonVersion || '<empty>'}`);
  }
  if (!await fileExists(pythonArtifact)) {
    throw new Error(`packaged Python ${pythonVersion} artifact is missing: ${pythonArtifact || '<empty>'}`);
  }
  if (!await fileExists(pythonMetadataArtifact)) {
    throw new Error(`packaged Python provenance is missing: ${pythonMetadataArtifact || '<empty>'}`);
  }
  for (const [name, value] of Object.entries({
    source_type: pythonMetadata.source_type,
    source_url: pythonMetadata.source_url,
    source_sha256: pythonMetadata.source_sha256,
    configure_args: pythonMetadata.configure_args,
    configure_environment: pythonMetadata.configure_environment,
  })) {
    if (typeof value !== 'string' || value.length === 0) throw new Error(`python metadata ${name} is empty`);
  }
  if (!/^[0-9a-f]{64}$/.test(pythonMetadata.source_sha256)) {
    throw new Error(`python metadata source_sha256 is invalid: ${pythonMetadata.source_sha256}`);
  }
  const cjcjFile = findExecutable(stage, 'bin/cjc', exeSuffix);
  const llcFile = findExecutable(stage, 'third_party/llvm/bin/llc', exeSuffix);
  const optFile = findExecutable(stage, 'third_party/llvm/bin/opt', exeSuffix);
  const cjpmFile = findExecutable(stage, 'tools/bin/cjpm', exeSuffix);
  const cjcjArtifact = await artifact(stage, cjcjFile, 'packaged cjc is missing', ['CJCJ-COMMIT']);
  const runtime = await artifact(stage, runtimeArtifact, 'canonical packaged runtime is missing', ['CJRT-COMMIT']);
  const llc = await artifact(stage, llcFile, 'packaged llc is missing', ['CJLLVM-COMMIT']);
  const opt = await artifact(stage, optFile, 'packaged opt is missing', ['CJLLVM-COMMIT']);
  const cjpm = await artifact(stage, cjpmFile, 'packaged cjpm is missing', [TOOL_STAMP_PREFIX]);
  const python = await artifact(stage, pythonArtifact, `packaged Python ${pythonVersion} is missing`);
  const pythonProvenance = await artifact(stage, pythonMetadataArtifact, 'packaged Python provenance is missing');
  assertFrozenStamp(cjcjArtifact, 'cjc', 'CJCJ-COMMIT', frozen.cjcj);
  assertFrozenStamp(runtime, 'runtime', 'CJRT-COMMIT', frozen.runtime);
  assertFrozenStamp(llc, 'llvm-llc', 'CJLLVM-COMMIT', frozen.llvm);
  assertFrozenStamp(opt, 'llvm-opt', 'CJLLVM-COMMIT', frozen.llvm);
  // Every Cangjie-written tool the stage actually contains, found by structure
  // rather than by name. cjpm resolves through the same path, so it is covered
  // by the same rule instead of by a special case.
  const discovered = await discoverCangjieTools(stage, exeSuffix);
  const tools = [];
  for (const {component, file} of discovered) {
    tools.push({
      component,
      file,
      value: file === cjpmFile ? cjpm : await artifact(stage, file, `packaged ${component} is missing`, [TOOL_STAMP_PREFIX]),
    });
  }
  const sourceByComponent = new Map(Object.entries(toolSources).map(([component, value]) => [component, {
    repository: requireText(value.repository, `${component}.source.repository`),
    commit: sourceCommit(value.commit, component),
  }]));
  if (toolsRepository && toolsCommit) {
    for (const tool of tools) {
      if (tool.component !== 'cjpm' && !sourceByComponent.has(tool.component)) {
        sourceByComponent.set(tool.component, {
          repository: requireText(toolsRepository, `${tool.component}.source.repository`),
          commit: sourceCommit(toolsCommit, tool.component),
        });
      }
    }
  }
  const toolStamps = assertToolStamps(tools, sourceByComponent);
  if (!toolStamps.enforced) {
    // Named, not silent. A limitation nobody can read is indistinguishable from
    // no limitation, which is how "known issue, does not affect the release"
    // text gets written; these names go to stderr and into each row's build
    // section so the limitation is recomputable from the package itself.
    console.error(`[release-manifest] WARNING no declared source-owned Cangjie tool carries ${TOOL_STAMP_PREFIX}; ` +
      `inherited tools remain base-SDK records: ${toolStamps.unstamped.join(', ')}`);
  }
  if (!await fileExists(gateApparatusArtifact)) {
    throw new Error(`packaged gate apparatus provenance is missing: ${gateApparatusArtifact || '<empty>'}`);
  }
  const gateApparatus = await readGateApparatusProvenance({
    file: gateApparatusArtifact,
    platform,
    expectedToolchain: baseSdkId,
  });
  const gateApparatusArtifactValue = await artifact(stage, gateApparatusArtifact,
    'packaged gate apparatus provenance is missing');

  const stdText = await fileExists(stdProvenance) ? await fs.readFile(stdProvenance, 'utf8') : '';
  const verifiedBaseSdk = validateBaseSdkProvenance(baseSdkProvenance, {
    platform,
    toolchain: baseSdkId,
    label: 'release manifest base SDK provenance',
  });
  const sourceForTool = tool => {
    const sourceInfo = sourceByComponent.get(tool.component);
    return sourceInfo
      ? source(sourceInfo.repository, sourceInfo.commit, tool.component)
      : inheritedToolSource(verifiedBaseSdk, tool.component);
  };

  const rows = [
    {
      schema: 1,
      platform,
      component: 'base-sdk',
      source: notApplicableSource(verifiedBaseSdk.source.reason, {
        release_repository: verifiedBaseSdk.release.repository,
        version: verifiedBaseSdk.release.version,
        download_url: verifiedBaseSdk.release.download_url,
      }),
      artifact: {
        path: verifiedBaseSdk.artifact.path,
        sha256: verifiedBaseSdk.artifact.sha256,
      },
      embedded_stamp: 'no-stamp',
    },
    {
      schema: 1,
      platform,
      component: GATE_APPARATUS_COMPONENT,
      source: notApplicableSource(gateApparatus.base_sdk.source.reason, {
        release_repository: gateApparatus.base_sdk.release_repository,
        version: gateApparatus.base_sdk.version,
        download_url: gateApparatus.base_sdk.download_url,
      }),
      artifact: {
        path: gateApparatusArtifactValue.path,
        sha256: gateApparatusArtifactValue.sha256,
      },
      embedded_stamp: 'no-stamp',
      acceptance_apparatus: gateApparatusManifestSection(gateApparatus, platform),
    },
    {
      schema: 1,
      platform,
      component: 'cjcj',
      source: source(cjcjRepository, frozen.cjcj, 'cjcj'),
      artifact: {path: cjcjArtifact.path, sha256: cjcjArtifact.sha256},
      embedded_stamp: cjcjArtifact.embedded_stamp,
    },
    {
      schema: 1,
      platform,
      component: 'runtime',
      source: source(runtimeRepository, frozen.runtime, 'runtime'),
      artifact: {path: runtime.path, sha256: runtime.sha256},
      embedded_stamp: runtime.embedded_stamp,
    },
    ...[
      ['llvm-llc', llc],
      ['llvm-opt', opt],
    ].map(([component, tool]) => ({
      schema: 1,
      platform,
      component,
      source: source(llvmRepository, frozen.llvm, component),
      artifact: {path: tool.path, sha256: tool.sha256},
      embedded_stamp: tool.embedded_stamp,
    })),
    {
      schema: 1,
      platform,
      component: 'std',
      source: source(stdRepository || runtimeRepository, stdCommit(stdText), 'std'),
      artifact: await (async () => {
        const value = await artifact(stage, stdProvenance, 'std PROVENANCE.txt is missing');
        return {path: value.path, sha256: value.sha256};
      })(),
      embedded_stamp: 'no-stamp',
      // std ships as many archives and shared objects, none of which can carry an
      // embedded stamp of its own. Their identity lives in PROVENANCE.txt's
      // ARTIFACT-SHA256 block, and this records that the packaged bytes were
      // actually reconciled against it rather than merely accompanied by it.
      build: await reconcileStdArtifacts(stage, stdText),
    },
    {
      schema: 1,
      platform,
      component: 'cjpm',
      source: source(cjpmRepository, cjpmCommit, 'cjpm'),
      artifact: {path: cjpm.path, sha256: cjpm.sha256},
      embedded_stamp: cjpm.embedded_stamp,
      build: {identity_rule: sourceByComponent.has('tool-cjpm') ? 'enforced' : 'report-only-until-first-stamp'},
    },
    // One row per Cangjie-written tool the stage actually contains, minus cjpm
    // which keeps its own component name for downstream readers.
    ...tools
      .filter(tool => tool.file !== cjpmFile)
      .map(tool => ({
        schema: 1,
        platform,
        component: tool.component,
        source: sourceForTool(tool),
        artifact: {path: tool.value.path, sha256: tool.value.sha256},
        embedded_stamp: tool.value.embedded_stamp,
        build: {
          identity_rule: sourceByComponent.has(tool.component) ? 'enforced' : 'inherited-base-sdk',
          source_provenance: sourceByComponent.has(tool.component) ? 'supplied' : 'base-sdk',
        },
      })),
    {
      schema: 1,
      platform,
      component: 'python',
      source: {
        status: SOURCE_PROVENANCE_RESOLVED,
        repository: requireText(pythonRepository, 'python.source.repository'),
        commit: pythonVersion,
        download_url: pythonMetadata.source_url,
        archive_sha256: pythonMetadata.source_sha256,
      },
      artifact: {path: python.path, sha256: python.sha256},
      embedded_stamp: `PYTHON-VERSION:${pythonVersion}`,
      build: {
        source_type: pythonMetadata.source_type,
        configure_args: pythonMetadata.configure_args,
        configure_environment: pythonMetadata.configure_environment,
        provenance_path: pythonProvenance.path,
        provenance_sha256: pythonProvenance.sha256,
      },
    },
  ].map(row => ({...row, signature_policy: normalizedSignaturePolicy}));

  for (const row of rows) {
    validateReleaseManifestSource(row.source, row.component);
    validateReleaseManifestArtifact(row.artifact, row.component);
    for (const [name, value] of Object.entries({
      platform: row.platform,
      component: row.component,
      source_repository: row.source.repository,
      source_commit: row.source.commit,
      artifact_path: row.artifact.path,
      artifact_sha256: row.artifact.sha256,
      embedded_stamp: row.embedded_stamp,
      signature_policy: row.signature_policy,
    })) {
      if (typeof value !== 'string' || value.length === 0) throw new Error(`${row.component}.${name} is empty`);
      if (/^unavailable:/i.test(value)) {
        throw new Error(`${row.component}.${name} uses the forbidden legacy unavailable value`);
      }
    }
    if (row.component === 'python') {
      for (const [name, value] of Object.entries({
        source_download_url: row.source.download_url,
        source_archive_sha256: row.source.archive_sha256,
        build_source_type: row.build.source_type,
        build_configure_args: row.build.configure_args,
        build_configure_environment: row.build.configure_environment,
        build_provenance_path: row.build.provenance_path,
        build_provenance_sha256: row.build.provenance_sha256,
      })) {
        if (typeof value !== 'string' || value.length === 0) throw new Error(`python.${name} is empty`);
      }
    }
  }

  const destination = path.join(stage, RELEASE_MANIFEST);
  await fs.writeFile(destination, `${rows.map(row => JSON.stringify(row)).join('\n')}\n`);
  return {destination, rows};
}
