import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// The runner and the acquisition step read the same reviewed declaration.
// Artifact metadata identifies the producer; downloaded bytes never set a pin.
export function hostIdentity() {
  const target = process.env.CJCJ_SRCBUILD_TARGET
    || `${process.platform}-${process.platform === 'linux' && process.arch === 'arm64' ? 'aarch64' : process.arch}`;
  const cells = {
    'linux-x64': {platform: 'linux_x86_64', library: 'libLLVM-15.so'},
    'linux-aarch64': {platform: 'linux_aarch64', library: 'libLLVM-15.so'},
    'darwin-arm64': {platform: 'darwin_aarch64', library: 'libLLVM.dylib'},
    'darwin-x64': {platform: 'darwin_x86_64', library: 'libLLVM.dylib'},
  };
  const cell = cells[target];
  if (!cell) throw new Error(`HOST_LLVM_TARGET_UNSUPPORTED target=${target}`);
  const identities = process.env.STAGE1_HOST_IDENTITIES
    || new URL('../bootstrap/stage1_host_identities.txt', import.meta.url);
  const lines = fs.readFileSync(identities, 'utf8').split('\n');
  const linux = cell.platform.startsWith('linux_');
  const hashes = lines.map(line => line.trim().split(/\s+/))
    .filter(fields => fields[0] === cell.platform && fields[1] === cell.library);
  const records = lines.filter(line => line.startsWith('# HOST_LLVM_PROVENANCE '))
    .map(line => JSON.parse(line.slice('# HOST_LLVM_PROVENANCE '.length)))
    .filter(record => record.platform === cell.platform);
  if (records.length !== 1 || (linux && (hashes.length !== 1 || hashes[0].length !== 3))) throw new Error('HOST_LLVM_PIN_MISSING');
  const sha256 = linux ? hashes[0][2] : records[0].sha256;
  const pin = {...records[0], sha256, library: cell.library};
  const source = fs.readFileSync(new URL('../bootstrap/host_llvm_source.env', import.meta.url), 'utf8')
    .match(new RegExp(`^HOST_LLVM_SOURCE_SHA_${cell.platform}=([a-f0-9]{40})$`, 'm'))?.[1];
  if (!/^[a-f0-9]{64}$/.test(sha256) || !source || pin.source_sha !== source
      || pin.repository !== 'cjcj-dev/cjcj' || pin.platform !== cell.platform
      || !/^[a-f0-9]{40}$/.test(pin.producer_sha || '')
      || !['run_id', 'run_attempt', 'artifact_id'].every(key => /^[1-9][0-9]*$/.test(pin[key] || ''))) {
    throw new Error('HOST_LLVM_PIN_INVALID');
  }
  return pin;
}

export function prepareHostLlvm() {
  const pin = hostIdentity();
  const artifact = process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
  if (!artifact) throw new Error('HOST_LLVM_ARTIFACT_MISSING');
  const library = path.join(artifact, pin.library);
  if (!fs.lstatSync(library).isFile()) throw new Error('HOST_LLVM_REGULAR_FILE_REQUIRED');
  const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const actual = digest(library);
  if (actual !== pin.sha256) throw new Error(`HOST_LLVM_SHA256_MISMATCH expected=${pin.sha256} actual=${actual}`);
  const manifest = JSON.parse(fs.readFileSync(path.join(artifact, 'manifest.json'), 'utf8'));
  for (const key of ['source_sha', 'run_id', 'run_attempt', 'producer_sha', 'platform', 'sha256']) {
    if (manifest[key] !== pin[key]) throw new Error(`HOST_LLVM_PROVENANCE_MISMATCH field=${key}`);
  }
  const work = process.env.CJCJ_BOOTSTRAP_HOST_LLVM_WORK || process.env.RUNNER_TEMP || path.dirname(artifact);
  fs.mkdirSync(work, {recursive: true});
  const output = path.join(fs.mkdtempSync(path.join(work, 'verified-host-llvm-')), pin.library);
  fs.copyFileSync(library, output);
  if (digest(output) !== pin.sha256) throw new Error('HOST_LLVM_COPY_MISMATCH');
  console.log(`HOST_LLVM_VERIFIED run=${pin.run_id} artifact=${pin.artifact_id} source=${pin.source_sha} sha256=${pin.sha256} file=${output}`);
  return {file: path.resolve(output), sha256: pin.sha256};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv[2] !== 'env') throw new Error('usage: host_llvm.mjs env');
  const pin = hostIdentity();
  console.log(`HOST_LLVM_RUN_ID=${pin.run_id}\nHOST_LLVM_ARTIFACT_ID=${pin.artifact_id}`);
}
