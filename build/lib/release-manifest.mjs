import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {
  GATE_APPARATUS_COMPONENT,
  gateApparatusManifestSection,
  readGateApparatusProvenance,
} from './release-gate-apparatus.mjs';

export const RELEASE_MANIFEST = 'RELEASE-MANIFEST.jsonl';
export const RELEASE_SIGNATURE_POLICY = 'SHA_ONLY';

const unavailable = reason => `unavailable: ${reason}`;

function present(value, reason) {
  const text = typeof value === 'string' ? value.trim() : '';
  return text || unavailable(reason);
}

function sourceCommit(value, reason) {
  const commit = typeof value === 'string' ? value.trim() : '';
  return /^[0-9a-f]{40}(?:-dirty)?$/.test(commit) ? commit : unavailable(reason);
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
  else value = unavailable(`conflicting embedded stamps (${[...values].sort().join(',')})`);
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

function packagedPath(stage, file) {
  return path.relative(stage, file).split(path.sep).join('/');
}

async function artifact(stage, file, reason, prefixes = []) {
  if (!await fileExists(file)) {
    return {
      path: unavailable(reason),
      sha256: unavailable(reason),
      embedded_stamp: 'no-stamp',
      stamp_occurrences: Object.fromEntries(prefixes.map(prefix => [prefix, []])),
    };
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

function source(repository, commit, repoReason, commitReason) {
  return {
    repository: present(repository, repoReason),
    commit: sourceCommit(commit, commitReason),
  };
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
  const cjpm = await artifact(stage, cjpmFile, 'packaged cjpm is missing');
  const python = await artifact(stage, pythonArtifact, `packaged Python ${pythonVersion} is missing`);
  const pythonProvenance = await artifact(stage, pythonMetadataArtifact, 'packaged Python provenance is missing');
  assertFrozenStamp(cjcjArtifact, 'cjc', 'CJCJ-COMMIT', frozen.cjcj);
  assertFrozenStamp(runtime, 'runtime', 'CJRT-COMMIT', frozen.runtime);
  assertFrozenStamp(llc, 'llvm-llc', 'CJLLVM-COMMIT', frozen.llvm);
  assertFrozenStamp(opt, 'llvm-opt', 'CJLLVM-COMMIT', frozen.llvm);
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
  const hasBaseSdkProvenance = baseSdkProvenance?.schema === 1 &&
    baseSdkProvenance?.component === 'base-sdk' &&
    typeof baseSdkProvenance?.release?.repository === 'string' &&
    typeof baseSdkProvenance?.release?.version === 'string' &&
    typeof baseSdkProvenance?.release?.download_url === 'string' &&
    typeof baseSdkProvenance?.artifact?.path === 'string' &&
    /^[0-9a-f]{64}$/.test(baseSdkProvenance?.artifact?.sha256 || '');

  const rows = [
    {
      schema: 1,
      platform,
      component: 'base-sdk',
      source: {
        ...source('', '',
          `official SDK ${baseSdkId || '<unknown>'} has no source repository metadata`,
          `official SDK ${baseSdkId || '<unknown>'} has no source commit metadata`),
        ...(hasBaseSdkProvenance ? {
          release_repository: baseSdkProvenance.release.repository,
          version: baseSdkProvenance.release.version,
          download_url: baseSdkProvenance.release.download_url,
        } : {}),
      },
      artifact: hasBaseSdkProvenance ? {
        path: baseSdkProvenance.artifact.path,
        sha256: baseSdkProvenance.artifact.sha256,
      } : {
        path: unavailable('base SDK was supplied as an unpacked directory'),
        sha256: unavailable('base SDK was supplied as an unpacked directory'),
      },
      embedded_stamp: 'no-stamp',
    },
    {
      schema: 1,
      platform,
      component: GATE_APPARATUS_COMPONENT,
      source: {
        repository: gateApparatus.base_sdk.release_repository,
        commit: unavailable(`official gate host toolchain ${gateApparatus.gate_host_toolchain} has no source commit metadata`),
        version: gateApparatus.base_sdk.version,
        download_url: gateApparatus.base_sdk.download_url,
      },
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
      source: source(cjcjRepository, frozen.cjcj,
        'cjcj source repository was not supplied', 'cjcj source commit was neither supplied nor stamped'),
      artifact: {path: cjcjArtifact.path, sha256: cjcjArtifact.sha256},
      embedded_stamp: cjcjArtifact.embedded_stamp,
    },
    {
      schema: 1,
      platform,
      component: 'runtime',
      source: source(runtimeRepository, frozen.runtime,
        'runtime source repository was not supplied', 'runtime source commit was neither supplied nor stamped'),
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
      source: source(llvmRepository, frozen.llvm,
        'LLVM source repository was not supplied',
        'LLVM frozen source commit was not supplied'),
      artifact: {path: tool.path, sha256: tool.sha256},
      embedded_stamp: tool.embedded_stamp,
    })),
    {
      schema: 1,
      platform,
      component: 'std',
      source: source(stdRepository || runtimeRepository, stdCommit(stdText),
        'std source repository was not supplied',
        stdProvenance ? 'std provenance has no valid STD_SOURCE_COMMIT' : 'std PROVENANCE.txt was not supplied'),
      artifact: await (async () => {
        const value = await artifact(stage, stdProvenance, 'std PROVENANCE.txt is missing');
        return {path: value.path, sha256: value.sha256};
      })(),
      embedded_stamp: 'no-stamp',
    },
    {
      schema: 1,
      platform,
      component: 'cjpm',
      source: source(cjpmRepository, cjpmCommit,
        'packaged cjpm has no source repository metadata',
        'packaged cjpm has no source commit metadata'),
      artifact: {path: cjpm.path, sha256: cjpm.sha256},
      embedded_stamp: cjpm.embedded_stamp,
    },
    {
      schema: 1,
      platform,
      component: 'python',
      source: {
        repository: present(pythonRepository, 'Python source repository was not supplied'),
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
