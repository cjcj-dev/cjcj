import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sha = value => /^[a-f0-9]{64}$/.test(value);
export function verify(bytes, expected, name) {
  if (!sha(expected) || digest(bytes) !== expected) throw new Error(`bootstrap digest mismatch: ${name}`);
}
export function validatePin(pin) {
  if (pin.version !== 1 || !/^[\w.-]+\/[\w.-]+$/.test(pin.repository)
      || !Number.isSafeInteger(pin.run) || pin.run < 1 || !Number.isSafeInteger(pin.attempt) || pin.attempt < 1
      || !Number.isSafeInteger(pin.artifact) || pin.artifact < 1 || !/^[a-f0-9]{40}$/.test(pin.commit)
      || !Array.isArray(pin.files) || !pin.files.length) throw new Error('invalid bootstrap source pin');
  const names = new Set();
  for (const file of pin.files) {
    if (!/^[\w.-]+(?:\/[\w.-]+)*$/.test(file.path) || file.path.split('/').some(p => p === '.' || p === '..')
        || ![0o644, 0o755].includes(file.mode)
        || names.has(file.path) || !sha(file.artifact_sha256) || file.release_sha256 !== file.artifact_sha256
        || !Number.isSafeInteger(file.asset) || file.asset < 1) throw new Error(`invalid bootstrap file pin: ${file.path}`);
    names.add(file.path);
  }
}
export async function api(route, options = {}) {
  const response = await fetch(`https://api.github.com${route}`, {
    ...options, headers: {Accept: 'application/vnd.github+json',
      ...(process.env.GITHUB_TOKEN ? {Authorization: `Bearer ${process.env.GITHUB_TOKEN}`} : {}),
      ...options.headers},
  });
  if (!response.ok) throw new Error(`bootstrap GitHub request failed: ${response.status} ${route}`);
  return response;
}
export async function asset(repository, id) {
  return Buffer.from(await (await api(`/repos/${repository}/releases/assets/${id}`,
    {headers: {Accept: 'application/octet-stream'}})).arrayBuffer());
}
export async function acquire(pin, destination, {mode = 'release', reason = '', depot = ''} = {}) {
  validatePin(pin);
  if (!['release', 'artifact', 'depot'].includes(mode)) throw new Error('invalid bootstrap source mode');
  if (mode !== 'release' && !reason.trim()) throw new Error('explicit bootstrap fallback requires a reason');
  console.log(`BOOTSTRAP_SOURCE mode=${mode} reason=${JSON.stringify(reason || 'default persistent source')} run=${pin.run} attempt=${pin.attempt}`);
  fs.mkdirSync(destination, {recursive: true});
  const staging = fs.mkdtempSync(path.join(destination, '.acquire-'));
  try {
    if (mode === 'artifact') {
      const run = await (await api(`/repos/${pin.repository}/actions/runs/${pin.run}/attempts/${pin.attempt}`)).json();
      const metadata = await (await api(`/repos/${pin.repository}/actions/artifacts/${pin.artifact}`)).json();
      if (run.head_sha !== pin.commit || metadata.workflow_run?.id !== pin.run
          || metadata.workflow_run?.head_sha !== pin.commit || metadata.expired) throw new Error('bootstrap artifact provenance mismatch');
      const archive = Buffer.from(await (await api(`/repos/${pin.repository}/actions/artifacts/${pin.artifact}/zip`)).arrayBuffer());
      const zip = path.join(staging, 'input.zip');
      fs.writeFileSync(zip, archive);
      for (const file of pin.files) {
        const result = spawnSync('unzip', ['-p', zip, file.path], {maxBuffer: 1024 * 1024 * 1024});
        if (result.status !== 0) throw new Error(`bootstrap artifact member missing: ${file.path}`);
        verify(result.stdout, file.artifact_sha256, file.path);
        const target = path.join(staging, 'files', file.path);
        fs.mkdirSync(path.dirname(target), {recursive: true});
        fs.writeFileSync(target, result.stdout);
        fs.chmodSync(target, file.mode);
      }
    } else {
      for (const file of pin.files) {
        let bytes;
        if (mode === 'release') bytes = await asset(pin.repository, file.asset);
        else {
          if (!depot) throw new Error('bootstrap depot path required');
          const source = path.join(depot, file.path);
          if (!fs.lstatSync(source).isFile()) throw new Error(`bootstrap depot payload is not a regular file: ${file.path}`);
          bytes = fs.readFileSync(source);
        }
        verify(bytes, mode === 'release' ? file.release_sha256 : file.artifact_sha256, file.path);
        const target = path.join(staging, 'files', file.path);
        fs.mkdirSync(path.dirname(target), {recursive: true});
        fs.writeFileSync(target, bytes);
        fs.chmodSync(target, file.mode);
      }
    }
    // Nothing becomes consumable before the entire selected source verifies.
    const result = path.join(staging, 'files');
    for (const file of pin.files) console.log(`BOOTSTRAP_VERIFIED ${file.path} ${file.artifact_sha256}`);
    return result;
  } catch (error) {
    fs.rmSync(staging, {recursive: true, force: true});
    throw error;
  }
}
