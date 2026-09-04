import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export const PACKAGED_TOOL_NAMES = Object.freeze([
  'cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover',
]);

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const ALLOWED_LINEAGE = new Set(['cjcj-stage2', 'final-std']);

export async function fileSha256(file) {
  const hash = crypto.createHash('sha256');
  const handle = await fs.open(file, 'r');
  try {
    for await (const chunk of handle.createReadStream()) hash.update(chunk);
  } finally {
    await handle.close();
  }
  return hash.digest('hex');
}

async function exists(file, kind = 'file') {
  try {
    const stat = await fs.stat(file);
    return kind === 'dir' ? stat.isDirectory() : stat.isFile();
  } catch {
    return false;
  }
}

export function classifyProvenanceText(text) {
  const body = String(text || '');
  if (/\bstdlib-stage1\b/.test(body)
    || /BOOTSTRAP-STAGE\s*[:=]\s*stage1\b/.test(body)
    || /LINEAGE\s*[:=]\s*bootstrap-intermediate\b/.test(body)
    || /LINEAGE\s*[:=]\s*stdlib-stage1\b/.test(body)) {
    return 'bootstrap-intermediate';
  }
  if (/\bofficial-std\b/.test(body)
    || /LINEAGE\s*[:=]\s*official-nightly\b/.test(body)
    || /LINEAGE\s*[:=]\s*official-std\b/.test(body)
    || /BUILT-WITH-SDK\s*[:=]\s*nightly-/.test(body)) {
    return 'official-std';
  }
  const lineage = body.match(/LINEAGE\s*[:=]\s*(\S+)/);
  if (lineage && ALLOWED_LINEAGE.has(lineage[1])) return lineage[1];
  const built = body.match(/BUILT-BY:([0-9a-f]{40})/);
  const commit = body.match(/CJSTD-COMMIT:([0-9a-f]{40})/);
  if (built && commit && SHA40.test(built[1]) && SHA40.test(commit[1])) return 'cjcj-stage2';
  return 'unknown';
}

export async function collectStdArtifactShas(root) {
  const shas = new Set();
  if (!await exists(root, 'dir')) return shas;
  const modules = path.join(root, 'modules');
  if (await exists(modules, 'dir')) {
    for (const tuple of await fs.readdir(modules, {withFileTypes: true})) {
      if (!tuple.isDirectory()) continue;
      const std = path.join(modules, tuple.name, 'std');
      if (!await exists(std, 'dir')) continue;
      for (const name of await fs.readdir(std)) {
        const file = path.join(std, name);
        if ((await fs.stat(file)).isFile()) shas.add(await fileSha256(file));
      }
    }
  }
  const lib = path.join(root, 'lib');
  if (await exists(lib, 'dir')) {
    for (const tuple of await fs.readdir(lib, {withFileTypes: true})) {
      if (!tuple.isDirectory()) continue;
      for (const name of await fs.readdir(path.join(lib, tuple.name))) {
        if (!name.startsWith('libcangjie-std')) continue;
        const file = path.join(lib, tuple.name, name);
        if ((await fs.stat(file)).isFile()) shas.add(await fileSha256(file));
      }
    }
  }
  return shas;
}

async function scanStdFiles(root) {
  const files = [];
  const modules = path.join(root, 'modules');
  if (!await exists(modules, 'dir')) return files;
  for (const tuple of await fs.readdir(modules, {withFileTypes: true})) {
    if (!tuple.isDirectory()) continue;
    const std = path.join(modules, tuple.name, 'std');
    if (!await exists(std, 'dir')) continue;
    for (const name of await fs.readdir(std)) {
      const file = path.join(std, name);
      if ((await fs.stat(file)).isFile()) files.push(file);
    }
  }
  return files;
}

function stampCommit(buffer, label) {
  const text = buffer.toString('latin1');
  const match = text.match(new RegExp(`${label}:([0-9a-f]{40})`));
  return match ? match[1] : '';
}

export async function inspectPackagedLineage(sdkRoot, {
  officialStdShas = new Set(),
  allowNightlyStd = false,
} = {}) {
  const provenancePath = path.join(sdkRoot, 'PROVENANCE.txt');
  let provenanceKind = 'unknown';
  let provenanceText = '';
  if (await exists(provenancePath)) {
    provenanceText = await fs.readFile(provenancePath, 'utf8');
    provenanceKind = classifyProvenanceText(provenanceText);
  }

  if (provenanceKind === 'bootstrap-intermediate') {
    return {
      ok: false,
      code: 'bootstrap-intermediate',
      message: 'bootstrap-intermediate: std provenance names stdlib-stage1',
    };
  }

  const stdFiles = await scanStdFiles(sdkRoot);
  const matchingOfficial = [];
  for (const file of stdFiles) {
    const sha = await fileSha256(file);
    if (officialStdShas.has(sha) && SHA256.test(sha)) matchingOfficial.push({file, sha});
  }

  const looksOfficial = provenanceKind === 'official-std' || matchingOfficial.length > 0;
  if (looksOfficial && !allowNightlyStd) {
    return {
      ok: false,
      code: 'official-std',
      message: matchingOfficial.length > 0
        ? `official-std: ${matchingOfficial.length} packaged std file(s) match official nightly sha`
        : 'official-std: provenance names official nightly std',
    };
  }

  if (looksOfficial && allowNightlyStd) {
    return {
      ok: true,
      code: 'ok',
      message: 'allow-nightly-std: official std hashes present and explicitly allowed',
      allowedNightly: true,
    };
  }

  for (const name of PACKAGED_TOOL_NAMES) {
    const file = path.join(sdkRoot, 'tools', 'bin', name);
    if (!await exists(file)) continue;
    const buffer = await fs.readFile(file);
    const tool = stampCommit(buffer, 'CJTOOL-COMMIT') || stampCommit(buffer, 'CJCJ-COMMIT');
    if (!SHA40.test(tool)) {
      return {
        ok: false,
        code: 'official-std',
        message: `official-std: tools/bin/${name} has no cjcj-stage2/final-std stamp`,
      };
    }
  }

  if (provenanceKind === 'unknown' && stdFiles.length > 0) {
    return {
      ok: false,
      code: 'official-std',
      message: 'official-std: std present but provenance is not cjcj-stage2 or final-std',
    };
  }

  return {ok: true, code: 'ok', message: `lineage ${provenanceKind}`};
}

export async function assertPackagedLineage(sdkRoot, options = {}) {
  const result = await inspectPackagedLineage(sdkRoot, options);
  if (!result.ok) {
    const error = new Error(result.message);
    error.code = result.code;
    throw error;
  }
  return result;
}
