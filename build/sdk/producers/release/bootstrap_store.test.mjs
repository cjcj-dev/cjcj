import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {acquire, digest} from './bootstrap_store.mjs';

const bytes = Buffer.from('reviewed payload');
function pin() { return {version: 1, repository: 'cjcj-dev/cjcj', run: 123, attempt: 1,
  artifact: 456, commit: 'a'.repeat(40), files: [{path: 'bin/llc', mode: 0o755, asset: 789,
    artifact_sha256: digest(bytes), release_sha256: digest(bytes)}]}; }
async function fixture(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap-store-'));
  const original = globalThis.fetch;
  try { await fn(dir); } finally { globalThis.fetch = original; fs.rmSync(dir, {recursive: true, force: true}); }
}
test('persistent source ignores unavailable fixed run and returns verified product bytes', () => fixture(async dir => {
  const p = pin(); p.run = 999999999;
  const requests = [];
  globalThis.fetch = async url => { requests.push(url); return new Response(bytes); };
  const result = await acquire(p, dir);
  assert.deepEqual(fs.readFileSync(path.join(result, 'bin/llc')), bytes);
  assert.equal(fs.statSync(path.join(result, 'bin/llc')).mode & 0o777, 0o755);
  assert.deepEqual(requests, ['https://api.github.com/repos/cjcj-dev/cjcj/releases/assets/789']);
  console.log('ASSERT persistent product bytes reached consumer');
}));
test('persistent corruption fails the named digest without trying another source', () => fixture(async dir => {
  let requests = 0;
  globalThis.fetch = async () => { requests++; return new Response('changed'); };
  await assert.rejects(acquire(pin(), dir), /bootstrap digest mismatch: bin\/llc/);
  assert.equal(requests, 1);
  assert.deepEqual(fs.readdirSync(dir), []);
  console.log('ASSERT persistent corruption rejected at digest');
}));
test('persistent unavailable fails without falling through', () => fixture(async dir => {
  let requests = 0;
  globalThis.fetch = async () => { requests++; return new Response('', {status: 404}); };
  await assert.rejects(acquire(pin(), dir), /404/);
  assert.equal(requests, 1);
}));
test('explicit depot copies verified bytes and records its reason', () => fixture(async dir => {
  const depot = path.join(dir, 'depot'); fs.mkdirSync(path.join(depot, 'bin'), {recursive: true});
  fs.writeFileSync(path.join(depot, 'bin/llc'), bytes);
  const result = await acquire(pin(), dir, {mode: 'depot', reason: 'offline recovery', depot});
  assert.deepEqual(fs.readFileSync(path.join(result, 'bin/llc')), bytes);
  assert.notEqual(fs.statSync(path.join(result, 'bin/llc')).ino, fs.statSync(path.join(depot, 'bin/llc')).ino);
}));
test('fallback requires an explicit reason', () => fixture(async dir => {
  await assert.rejects(acquire(pin(), dir, {mode: 'artifact'}), /requires a reason/);
}));
test('pin refuses unequal location digests before any request', () => fixture(async dir => {
  const p = pin(); p.files[0].release_sha256 = 'f'.repeat(64);
  await assert.rejects(acquire(p, dir), /invalid bootstrap file pin/);
}));

test('depot corruption rejects without exposing a partial input directory', () => fixture(async dir => {
  const depot = path.join(dir, 'depot'); fs.mkdirSync(path.join(depot, 'bin'), {recursive: true});
  fs.writeFileSync(path.join(depot, 'bin/llc'), 'changed');
  await assert.rejects(acquire(pin(), dir, {mode: 'depot', reason: 'fixture', depot}), /bootstrap digest mismatch: bin\/llc/);
  assert.deepEqual(fs.readdirSync(dir), ['depot']);
}));

test('artifact wrong provenance stops before archive retrieval', () => fixture(async dir => {
  const requests = [];
  globalThis.fetch = async url => {
    requests.push(url);
    return new Response(JSON.stringify(url.includes('/runs/') ? {head_sha: 'a'.repeat(40)}
      : {workflow_run: {id: 999, head_sha: 'a'.repeat(40)}, expired: false}));
  };
  await assert.rejects(acquire(pin(), dir, {mode: 'artifact', reason: 'fixture'}), /provenance mismatch/);
  assert.equal(requests.length, 2);
  assert.ok(requests.every(url => !url.endsWith('/zip')));
}));

test('pin rejects paths and modes outside the regular-file contract', () => fixture(async dir => {
  for (const change of [{path: '../llc'}, {path: '/llc'}, {mode: 0o777}, {mode: undefined}]) {
    const p = pin(); Object.assign(p.files[0], change);
    await assert.rejects(acquire(p, dir), /invalid bootstrap file pin/);
  }
}));
