import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const PACKAGED_TOOL_NAMES = Object.freeze([
  'cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover',
]);

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const ALLOWED_LINEAGE = new Set(['cjcj-stage2', 'final-std']);
const ARTIFACT_EXT = new Set(['.cjo', '.a', '.so', '.bc']);
const SCAN_ROOTS = Object.freeze(['modules', 'lib', 'runtime/lib']);
const DYE_LABELS = Object.freeze([
  'CJCJ-COMMIT',
  'CJTOOL-COMMIT',
  'CJLLVM-COMMIT',
  'CJRT-COMMIT',
  'g_cjStoreBadMask',
]);

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

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

export function hostSdkPinPath() {
  return path.join(REPO_ROOT, 'ci', 'host_sdk_pin.env');
}

export async function readHostSdkPinToolchain(pinFile = hostSdkPinPath()) {
  const text = await fs.readFile(pinFile, 'utf8');
  const match = text.match(/^CJCJ_TOOLCHAIN=(\S+)$/m);
  if (!match) throw new Error(`CJCJ_TOOLCHAIN missing from ${pinFile}`);
  return match[1];
}

export async function pinnedOfficialSdkRoot(pinFile = hostSdkPinPath()) {
  const toolchain = await readHostSdkPinToolchain(pinFile);
  return path.join(os.homedir(), '.cjv', 'toolchains', toolchain);
}

export function isPackagedArtifact(file) {
  return ARTIFACT_EXT.has(path.extname(file));
}

export async function listPackagedArtifacts(root) {
  const files = [];
  async function walk(dir) {
    if (!await exists(dir, 'dir')) return;
    for (const entry of await fs.readdir(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
        continue;
      }
      if (entry.isFile() && isPackagedArtifact(full)) files.push(full);
    }
  }
  for (const rel of SCAN_ROOTS) await walk(path.join(root, rel));
  for (const name of PACKAGED_TOOL_NAMES) {
    const file = path.join(root, 'tools', 'bin', name);
    if (await exists(file)) files.push(file);
  }
  files.sort();
  return files;
}

export async function collectStdArtifactShas(root) {
  const shas = new Set();
  for (const file of await listPackagedArtifacts(root)) {
    shas.add(await fileSha256(file));
  }
  return shas;
}

export function contentSignals(buffer) {
  const text = Buffer.isBuffer(buffer) ? buffer.toString('latin1') : String(buffer);
  const found = [];
  if (/CJCJ-COMMIT:[0-9a-f]{40}/.test(text)) found.push('CJCJ-COMMIT');
  if (/CJTOOL-COMMIT:[0-9a-f]{40}/.test(text)) found.push('CJTOOL-COMMIT');
  if (/CJLLVM-COMMIT:[0-9a-f]{40}/.test(text)) found.push('CJLLVM-COMMIT');
  if (/CJRT-COMMIT:[0-9a-f]{40}/.test(text)) found.push('CJRT-COMMIT');
  if (text.includes('g_cjStoreBadMask')) found.push('g_cjStoreBadMask');
  return found;
}

let cachedOfficialShas;

export async function bindOfficialNightlyShas() {
  if (cachedOfficialShas) return cachedOfficialShas;
  const root = await pinnedOfficialSdkRoot();
  if (!await exists(root, 'dir')) {
    throw new Error(`official nightly pin dir missing: ${root}`);
  }
  cachedOfficialShas = await collectStdArtifactShas(root);
  return cachedOfficialShas;
}

export async function collectContentFindings(sdkRoot, officialShas) {
  const findings = [];
  for (const file of await listPackagedArtifacts(sdkRoot)) {
    const sha = await fileSha256(file);
    const buffer = await fs.readFile(file);
    const dyes = contentSignals(buffer);
    const reasons = [];
    if (officialShas.has(sha) && SHA256.test(sha)) {
      reasons.push(`matches official nightly sha256 ${sha}`);
    }
    if (dyes.length === 0) reasons.push(`missing rebuilt dye signal (${DYE_LABELS.join('/')})`);
    if (reasons.length > 0) {
      findings.push({file, sha, reasons, dyes});
    }
  }
  return findings;
}

function formatFindings(findings) {
  return findings.map(item => `  ${item.file}: ${item.reasons.join('; ')}`).join('\n');
}

export async function inspectPackagedLineage(sdkRoot, {
  allowNightlyStd = false,
} = {}) {
  const provenancePath = path.join(sdkRoot, 'PROVENANCE.txt');
  let provenanceKind = 'unknown';
  if (await exists(provenancePath)) {
    const provenanceText = await fs.readFile(provenancePath, 'utf8');
    provenanceKind = classifyProvenanceText(provenanceText);
  }

  if (provenanceKind === 'bootstrap-intermediate') {
    return {
      ok: false,
      code: 'bootstrap-intermediate',
      message: 'bootstrap-intermediate: std provenance names stdlib-stage1',
      findings: [],
    };
  }

  const officialShas = await bindOfficialNightlyShas();
  const findings = await collectContentFindings(sdkRoot, officialShas);
  if (allowNightlyStd && (findings.length > 0 || provenanceKind === 'official-std')) {
    return {
      ok: true,
      code: 'ok',
      message: 'allow-nightly-std: official content present and explicitly allowed',
      allowedNightly: true,
      findings,
    };
  }
  if (findings.length > 0) {
    return {
      ok: false,
      code: 'official-std',
      message: `official-std: content check failed for ${findings.length} file(s)\n${formatFindings(findings)}`,
      findings,
    };
  }
  if (provenanceKind === 'official-std') {
    return {
      ok: false,
      code: 'official-std',
      message: 'official-std: provenance names official nightly std',
      findings: [],
    };
  }

  return {ok: true, code: 'ok', message: `lineage ${provenanceKind}`, findings: []};
}

export async function assertPackagedLineage(sdkRoot, options = {}) {
  const result = await inspectPackagedLineage(sdkRoot, options);
  if (!result.ok) {
    const error = new Error(result.message);
    error.code = result.code;
    error.findings = result.findings;
    throw error;
  }
  return result;
}
