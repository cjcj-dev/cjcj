import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {digest} from './bootstrap_store.mjs';

// Only the remote transport is simulated; execute the production publisher CLI,
// its artifact extraction, validation and output pin without reimplementing them.
function fixture(check) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap-publish-'));
  try {
    const root = path.join(dir, 'payload');
    fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
    const bytes = Buffer.from('#!/bin/sh\necho bootstrap-fixture\n');
    fs.writeFileSync(path.join(root, 'bin/llc'), bytes);
    const list = [{path: 'bin/llc', mode: 0o755, sha256: digest(bytes)}];
    fs.writeFileSync(path.join(dir, 'files.json'), JSON.stringify(list));
    const zip = spawnSync('zip', ['-q', path.join(dir, 'artifact.zip'), 'bin/llc'], {cwd: root});
    assert.equal(zip.status, 0, zip.stderr?.toString());
    const preload = path.join(dir, 'transport.mjs');
    fs.writeFileSync(preload, `
import fs from 'node:fs';
const dir = process.env.FIXTURE_DIR;
const record = value => fs.appendFileSync(dir + '/requests.jsonl', JSON.stringify(value) + '\\n');
globalThis.fetch = async (url, options = {}) => {
  record({url, method: options.method || 'GET', body: options.body && typeof options.body === 'string' ? JSON.parse(options.body) : undefined});
  const reply = body => new Response(JSON.stringify(body));
  if (url.endsWith('/actions/runs/123') || url.endsWith('/actions/runs/123/attempts/1'))
    return reply({head_sha: 'a'.repeat(40), run_attempt: 1});
  if (url.endsWith('/actions/artifacts/456'))
    return reply({expired: false, workflow_run: {id: 123, head_sha: 'a'.repeat(40)}});
  if (url.endsWith('/actions/artifacts/456/zip')) return new Response(fs.readFileSync(dir + '/artifact.zip'));
  if (url.endsWith('/releases') && options.method === 'POST') {
    record({release: JSON.parse(options.body)});
    return reply({id: 789, upload_url: 'https://uploads.github.com/fixture{?name}'});
  }
  if (url.startsWith('https://uploads.github.com/fixture?')) {
    fs.writeFileSync(dir + '/uploaded', options.body);
    return reply({id: 101});
  }
  if (url.endsWith('/releases/assets/101')) return new Response(
    process.env.CORRUPT_RELEASE ? 'replaced' : fs.readFileSync(dir + '/uploaded'));
  if (url.endsWith('/releases/789') && options.method === 'PATCH') return reply({id: 789});
  throw new Error('unexpected fixture request: ' + url);
};
`);
    const run = (extra = {}) => spawnSync(process.execPath, ['--import', preload,
      new URL('./publish_bootstrap_inputs.mjs', import.meta.url).pathname,
      root, path.join(dir, 'files.json'), path.join(dir, 'pin.json')], {
      encoding: 'utf8', env: {...process.env, GITHUB_REPOSITORY: 'cjcj-dev/cjcj',
        GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1', GITHUB_SHA: 'a'.repeat(40),
        BOOTSTRAP_ARTIFACT_ID: '456', GITHUB_TOKEN: '', FIXTURE_DIR: dir, ...extra}});
    check({dir, root, bytes, run});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

test('publisher reads back both stores before emitting equal pinned digests', () => fixture(({dir, bytes, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  const pin = JSON.parse(fs.readFileSync(path.join(dir, 'pin.json')));
  assert.deepEqual(pin.files, [{path: 'bin/llc', mode: 0o755, asset: 101,
    artifact_sha256: digest(bytes), release_sha256: digest(bytes)}]);
  const requests = fs.readFileSync(path.join(dir, 'requests.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  const urls = requests.filter(r => r.url).map(r => r.url);
  assert.ok(urls.findIndex(u => u.endsWith('/456/zip')) < urls.findIndex(u => u.endsWith('/releases')));
  assert.ok(urls.findIndex(u => u.endsWith('/assets/101')) < urls.findIndex(u => u.endsWith('/releases/789')));
  assert.equal(requests.find(r => r.release).release.draft, true);
  const release = requests.find(r => r.release).release;
  assert.equal(release.prerelease, true);
  assert.equal(release.make_latest, 'false');
  assert.match(release.tag_name, /-prerelease$/);
  assert.deepEqual(requests.find(r => r.method === 'PATCH').body, {draft: false, prerelease: true, make_latest: 'false'});
  console.log('ASSERT publisher pin digests and readback-before-publication executed');
}));

test('publisher replaced release bytes reject at named digest before pin or publication', () => fixture(({dir, run}) => {
  const result = run({CORRUPT_RELEASE: '1'});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: bin\/llc/);
  assert.equal(fs.existsSync(path.join(dir, 'pin.json')), false);
  assert.doesNotMatch(fs.readFileSync(path.join(dir, 'requests.jsonl'), 'utf8'), /"method":"PATCH"/);
  console.log('ASSERT publisher replaced-release digest rejection executed');
}));

test('publisher fixed-artifact readback rejects changed input before creating a release', () => fixture(({dir, root, run}) => {
  fs.writeFileSync(path.join(root, 'bin/llc'), 'changed after artifact upload');
  fs.writeFileSync(path.join(dir, 'files.json'), JSON.stringify([{path: 'bin/llc', mode: 0o755,
    sha256: digest(Buffer.from('changed after artifact upload'))}]));
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: bin\/llc/);
  assert.doesNotMatch(fs.readFileSync(path.join(dir, 'requests.jsonl'), 'utf8'), /"method":"POST"/);
  console.log('ASSERT publisher fixed-artifact identity rejection executed');
}));
