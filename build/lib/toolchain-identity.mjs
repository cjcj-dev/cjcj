import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export const TOOLCHAIN_IDENTITY = 'TOOLCHAIN_ID.tsv';
export const TOOLCHAIN_IDENTITY_FORMAT = 'toolchain-lineage-v1';

export const TOOLCHAIN_IDENTITY_ARTIFACTS = Object.freeze([
  {name: 'runtime', component: 'runtime', prefix: 'CJRT-COMMIT'},
  {name: 'cjc', component: 'cjcj', prefix: 'CJCJ-COMMIT'},
  {name: 'cjpm', component: 'cjpm', prefix: 'CJTOOL-COMMIT'},
  {name: 'llc', component: 'llvm-llc', prefix: 'CJLLVM-COMMIT'},
  {name: 'opt', component: 'llvm-opt', prefix: 'CJLLVM-COMMIT'},
]);

function requireText(value, label) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text || /[\t\r\n]/.test(text)) throw new Error(`${label} is empty or not TSV-safe`);
  return text;
}

function cleanCommit(value, label) {
  const commit = requireText(value, label);
  if (!/^[0-9a-f]{40}$/.test(commit)) {
    throw new Error(`${label} must be a clean 40-character commit SHA; actual=${commit}`);
  }
  return commit;
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function embeddedStamp(bytes, prefix) {
  const marker = Buffer.from(`${prefix}:`);
  const values = [];
  let offset = 0;
  while (offset < bytes.length) {
    const found = bytes.indexOf(marker, offset);
    if (found < 0) break;
    const begin = found + marker.length;
    let end = begin;
    while (end < bytes.length && /[0-9A-Za-z._-]/.test(String.fromCharCode(bytes[end]))) end += 1;
    values.push(bytes.subarray(begin, end).toString('ascii'));
    offset = begin;
  }
  return values;
}

function artifactPath(stage, relative, label) {
  const normalized = requireText(relative, `${label}.artifact.path`).replaceAll('\\', '/');
  if (path.posix.isAbsolute(normalized) || normalized.split('/').includes('..')) {
    throw new Error(`${label}.artifact.path escapes the SDK: ${normalized}`);
  }
  return {relative: normalized, absolute: path.join(stage, ...normalized.split('/'))};
}

async function inspectArtifact(stage, rows, specification) {
  const row = rows.find(value => value.component === specification.component);
  if (!row) throw new Error(`toolchain identity component is missing: ${specification.component}`);
  if (row.source?.status !== 'resolved') {
    throw new Error(`${specification.component}.source.status must be resolved; actual=${row.source?.status || '<empty>'}`);
  }
  const repository = requireText(row.source.repository, `${specification.component}.source.repository`);
  const commit = cleanCommit(row.source.commit, `${specification.component}.source.commit`);
  const artifact = artifactPath(stage, row.artifact?.path, specification.component);
  const bytes = await fs.readFile(artifact.absolute);
  const digest = sha256(bytes);
  if (row.artifact?.sha256 !== digest) {
    throw new Error(`${specification.component} SHA-256 mismatch: manifest=${row.artifact?.sha256 || '<empty>'} actual=${digest}`);
  }

  const stampValues = embeddedStamp(bytes, specification.prefix);
  const rendered = stampValues.length
    ? stampValues.map(value => `${specification.prefix}:${value || '<empty>'}`).join(', ')
    : '<none>';
  if (stampValues.length !== 1) {
    throw new Error(`${specification.name} ${specification.prefix} occurrence must be exactly 1; ` +
      `actual count=${stampValues.length}; actual stamps=${rendered}`);
  }
  const [stampCommit] = stampValues;
  if (stampCommit.endsWith('-dirty')) {
    throw new Error(`${specification.name} ${specification.prefix} must not be dirty; actual=${rendered}`);
  }
  if (stampCommit !== commit) {
    throw new Error(`${specification.name} ${specification.prefix} must equal source commit; ` +
      `actual=${stampCommit || '<empty>'}; source=${commit}`);
  }
  const stamp = `${specification.prefix}:${stampCommit}`;
  if (row.embedded_stamp !== stamp) {
    throw new Error(`${specification.component}.embedded_stamp mismatch: manifest=${row.embedded_stamp || '<empty>'} actual=${stamp}`);
  }
  return {...specification, repository, commit, path: artifact.relative, sha256: digest, stamp};
}

export async function writeToolchainIdentity({stage, releaseRows}) {
  const sdk = path.resolve(stage);
  const artifacts = [];
  for (const specification of TOOLCHAIN_IDENTITY_ARTIFACTS) {
    artifacts.push(await inspectArtifact(sdk, releaseRows, specification));
  }

  const lines = [
    `format\t${TOOLCHAIN_IDENTITY_FORMAT}`,
    'sdk_root\t.',
    'is_symlink\tno',
    `artifact_count\t${artifacts.length}`,
  ];
  for (const artifact of artifacts) {
    lines.push(
      `${artifact.name}_path\t${artifact.path}`,
      `${artifact.name}_sha\t${artifact.sha256}`,
      `${artifact.name}_repository\t${artifact.repository}`,
      `${artifact.name}_commit\t${artifact.commit}`,
      `${artifact.name}_dirty\tno`,
      `${artifact.name}_lineage\t${artifact.stamp}`,
    );
  }
  const destination = path.join(sdk, TOOLCHAIN_IDENTITY);
  await fs.writeFile(destination, `${lines.join('\n')}\n`);
  return {destination, artifacts};
}
