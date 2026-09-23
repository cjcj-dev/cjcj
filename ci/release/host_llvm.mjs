import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// The runner and the acquisition step read the same reviewed declaration.
// Artifact metadata identifies the producer; downloaded bytes never set a pin.
export function hostIdentity() {
  const identities = process.env.STAGE1_HOST_IDENTITIES
    || new URL('../bootstrap/stage1_host_identities.txt', import.meta.url);
  const lines = fs.readFileSync(identities, 'utf8').split('\n');
  const hashes = lines.filter(line => /^libLLVM-15\.so\s/.test(line));
  const records = lines.filter(line => line.startsWith('# HOST_LLVM_PROVENANCE '));
  if (hashes.length !== 1 || records.length !== 1) throw new Error('HOST_LLVM_PIN_MISSING');
  const sha256 = hashes[0].trim().split(/\s+/)[1];
  const pin = {...JSON.parse(records[0].slice('# HOST_LLVM_PROVENANCE '.length)), sha256};
  const source = fs.readFileSync(new URL('../bootstrap/host_llvm_source.env', import.meta.url), 'utf8')
    .match(/^HOST_LLVM_SOURCE_SHA=([a-f0-9]{40})$/m)?.[1];
  if (!/^[a-f0-9]{64}$/.test(sha256) || !source || pin.source_sha !== source
      || pin.repository !== 'cjcj-dev/cjcj' || pin.platform !== 'linux_x86_64'
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
  const library = path.join(artifact, 'libLLVM-15.so');
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
  const output = path.join(fs.mkdtempSync(path.join(work, 'verified-host-llvm-')), 'libLLVM-15.so');
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
