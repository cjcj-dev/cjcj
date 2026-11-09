import {resolveOfficialSdkRoot} from './config.mjs';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {installedInputs} from '../../ci/srcbuild/lib/installed-inputs.mjs';
import {validateReleaseManifestSource} from './release-manifest.mjs';
import {parseHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';

export const PACKAGED_TOOL_NAMES = Object.freeze([
  'cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover',
]);

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const ALLOWED_LINEAGE = new Set(['cjcj-stage2', 'final-std']);
const ARTIFACT_EXT = new Set(['.cjo', '.a', '.so', '.bc']);
const SCAN_ROOTS = Object.freeze(['modules', 'lib', 'runtime/lib']);

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
  return parseHostToolchainPin(text);
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
    for(const suffix of ['', '.exe']){
      let file = path.join(root, 'tools', 'bin', name+suffix);
      if(!await exists(file))continue;
      try{
        const lines=(await fs.readFile(file+'.entry','utf8')).trimEnd().split('\n');
        const rel=lines[2];
        if(lines[0]!=='cjcj-sdk-entry-v1'||!rel||path.isAbsolute(rel)||rel.includes('\\')||rel.split('/').includes('..'))throw new Error('packaged tool entry path '+name);
        file=path.join(root,rel);
        if(!await exists(file))throw new Error('packaged tool product missing '+name);
      }catch(e){if(e.code!=='ENOENT')throw e;}
      files.push(file);
    }
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

const cachedOfficialShas = new Map();

export async function bindOfficialNightlyShas(officialRoot) {
  const root = path.resolve(resolveOfficialSdkRoot(officialRoot) ?? await pinnedOfficialSdkRoot());
  if(cachedOfficialShas.has(root))return cachedOfficialShas.get(root);
  if (!await exists(root, 'dir')) {
    throw new Error(`official nightly pin dir missing: ${root}`);
  }
  const hashes=await collectStdArtifactShas(root);
  cachedOfficialShas.set(root,hashes);
  return hashes;
}

export async function collectContentFindings(sdkRoot, officialShas, {platform} = {}) {
  // Consume the same retained products as packaging. Inspect the digest the
  // existing reader already computed; do not hash the installation again or
  // treat embedded text as a second source of build authority.
  platform ??= JSON.parse(await fs.readFile(path.join(sdkRoot,'STAGE-INPUTS.json'),'utf8')).platform;
  const findings = [], checked = new Set();
  const inputs = await installedInputs(sdkRoot,platform,{checkArtifact:({path:rel,sha256:sha})=>{
    const file=path.join(sdkRoot,rel);
    checked.add(file);
    if(officialShas.has(sha)&&SHA256.test(sha))findings.push({file,sha,
      reasons:[`matches official nightly sha256 ${sha}`]});
  }});
  for(const row of inputs.components)validateReleaseManifestSource(row.source,row.component);
  for(const file of await listPackagedArtifacts(sdkRoot)) {
    if(!checked.has(file))findings.push({file,reasons:['installed producer did not record this product']});
  }
  return findings;
}

function formatFindings(findings) {
  return findings.map(item => `  ${item.file}: ${item.reasons.join('; ')}`).join('\n');
}

export async function inspectPackagedLineage(sdkRoot, {
  allowNightlyStd = false, officialRoot, platform,
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

  const officialShas = await bindOfficialNightlyShas(officialRoot);
  let findings;
  try {
    findings = await collectContentFindings(sdkRoot, officialShas, {platform});
  } catch(error) {
    return {ok:false,code:'installed-lineage',message:'installed-lineage: '+error.message,findings:[]};
  }
  if (allowNightlyStd && findings.every(row=>row.reasons.every(reason=>reason.startsWith('matches official nightly sha256'))) && (findings.length > 0 || provenanceKind === 'official-std')) {
    return {
      ok: true,
      code: 'ok',
      message: 'allow-nightly-std: official content present and explicitly allowed',
      allowedNightly: true,
      findings,
    };
  }
  if (findings.length > 0) {
    const code=findings.some(row=>row.reasons.some(reason=>!reason.startsWith('matches official nightly sha256')))
      ? 'installed-lineage' : 'official-std';
    return {
      ok: false,
      code,
      message: `${code}: content check failed for ${findings.length} file(s)\n${formatFindings(findings)}`,
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
