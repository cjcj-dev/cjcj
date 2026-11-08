import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {digest} from './bootstrap_store.mjs';

// Only GitHub transport (fetch and the gh asset download) is simulated. The
// production selector, publisher, consumer downloader and package unpack run.
const entry = new URL('./persist_native_sdk.mjs', import.meta.url).pathname;
const downloader = new URL('./download_pinned.mjs', import.meta.url).pathname;
const SHA = 'a'.repeat(40);
const HEAD = 'd'.repeat(40);
const VERSION = '1.2.3';
const NAME = `cjcj-srcbuild-linux-x64-${VERSION}`;
const TAG = `native-sdk-linux-x64-${VERSION}-456-77-1-prerelease`;
const OLD = 'native-sdk-linux-x64-1.2.2-400-70-1-prerelease';

function fixture(check, {logsOnly = false, oldEntry = true} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'native-sdk-persist-'));
  try {
    const sdkRoot = path.join(dir, 'sdk', 'cangjie');
    fs.mkdirSync(sdkRoot, {recursive: true});
    fs.writeFileSync(path.join(sdkRoot, 'BUILD-MANIFEST.json'), JSON.stringify({target: 'linux-x64', version: VERSION,
      consumption: {status: 'EXECUTED', platform: 'linux_x86_64'}}));
    const payload = path.join(dir, 'payload'); fs.mkdirSync(payload);
    const archive = `cangjie-sdk-linux-x64-${VERSION}-cjcj.tar.gz`;
    assert.equal(spawnSync('tar', ['-czf', path.join(payload, archive), '-C', path.join(dir, 'sdk'), 'cangjie']).status, 0);
    fs.writeFileSync(path.join(payload, `${archive}.sha256`), `${digest(fs.readFileSync(path.join(payload, archive)))}  ${archive}\n`);
    fs.writeFileSync(path.join(payload, 'verify.log'), 'gate log\n');
    const members = logsOnly ? ['verify.log'] : [archive, `${archive}.sha256`, 'verify.log'];
    assert.equal(spawnSync('zip', ['-q', path.join(dir, 'artifact.zip'), ...members], {cwd: payload}).status, 0);
    const zipSha = digest(fs.readFileSync(path.join(dir, 'artifact.zip')));
    const registry = path.join(dir, 'registry.json');
    const artifacts = {111: {repository: 'cjcj-dev/cjcj', asset: 5, prerelease: true, release_sha256: 'b'.repeat(64), tag: 'llvm-dylib-x-prerelease'}};
    if (oldEntry) artifacts[400] = {repository: 'cjcj-dev/cjcj', asset: 6, prerelease: true, release_sha256: 'c'.repeat(64), tag: OLD,
      native_sdk: {target: 'linux-x64', version: '1.2.2'}};
    fs.writeFileSync(registry, JSON.stringify({version: 1, artifacts}));
    const preload = path.join(dir, 'transport.mjs');
    fs.writeFileSync(preload, `
import fs from 'node:fs';
const dir = process.env.FIXTURE_DIR;
const record = value => fs.appendFileSync(dir + '/requests.jsonl', JSON.stringify(value) + '\\n');
let next = 900;
globalThis.fetch = async (url, options = {}) => {
  const method = options.method || 'GET';
  const body = typeof options.body === 'string' ? JSON.parse(options.body) : undefined;
  record({url, method, body});
  const reply = (value, status = 200) => new Response(JSON.stringify(value), {status});
  const api = 'https://api.github.com/repos/cjcj-dev/cjcj';
  if (url === api + '/actions/runs/123/artifacts?name=${NAME}&per_page=100') return reply({artifacts: [{id: 456, name: '${NAME}', expired: false}]});
  if (url === api + '/actions/artifacts/456') return reply({id: 456, name: '${NAME}', expired: process.env.EXPIRED === '1',
    workflow_run: {id: 123, head_sha: '${SHA}'}, digest: 'sha256:${zipSha}', size_in_bytes: Number(process.env.ARTIFACT_SIZE || 1),
    created_at: process.env.ARTIFACT_CREATED || '2026-01-01T00:10:00Z', expires_at: '2026-04-01T00:00:00Z'});
  // Another artifact of the same producer run (e.g. diagnosis logs).
  if (url === api + '/actions/artifacts/458') return reply({id: 458, name: '${NAME}-diagnosis', expired: false,
    workflow_run: {id: 123, head_sha: '${SHA}'}, digest: 'sha256:${'f'.repeat(64)}', size_in_bytes: 1, created_at: '2026-01-01T00:10:00Z'});
  if (url === api + '/actions/artifacts/456/zip') return new Response(fs.readFileSync(dir + '/artifact.zip'));
  // Producer run on its second attempt (a rerun); the gate job of that attempt ran 00:00-00:20.
  if (url === api + '/actions/runs/123') return reply({id: 123, head_sha: '${SHA}', run_attempt: 2, status: 'completed', event: 'workflow_dispatch',
    path: process.env.PRODUCER_PATH || '.github/workflows/release.yml', head_repository: {full_name: 'cjcj-dev/cjcj'}});
  if (url === api + '/actions/runs/123/attempts/2/jobs?per_page=100&page=1') return reply({jobs: [
    {id: 9, name: 'srcbuild / linux-x64 / source SDK / linux-x64 / srcbuild', run_id: 123, run_attempt: Number(process.env.JOB_ATTEMPT || 2),
      head_sha: '${SHA}', status: 'completed', conclusion: process.env.PRODUCER_CONCLUSION || 'success',
      started_at: '2026-01-01T00:00:00Z', completed_at: '2026-01-01T00:20:00Z'},
    {id: 10, name: 'srcbuild / linux-aarch64 / source SDK / linux-aarch64 / srcbuild', run_id: 123, run_attempt: 2, conclusion: 'failure'}]});
  if (url === api + '/compare/${SHA}...${HEAD}') return reply({status: process.env.COMPARE_STATUS || 'ahead'});
  if (url === api + '/releases?per_page=100&page=1') return reply([{id: 11, tag_name: '${OLD}'}, {id: 12, tag_name: 'llvm-dylib-x-prerelease'},
    ...(process.env.TAG_TAKEN ? [{id: 13, tag_name: '${TAG}', draft: true}] : [])]);
  if (url === api + '/git/ref/tags/${TAG}') return reply({message: 'Not Found'}, 404);
  if (url === api + '/releases' && method === 'POST') return reply({id: 789, upload_url: 'https://uploads.github.com/fixture{?name,label}'});
  if (url.startsWith('https://uploads.github.com/fixture?name=')) {
    const id = next++;
    fs.writeFileSync(dir + '/asset-' + id, Buffer.from(options.body));
    fs.appendFileSync(dir + '/assets.jsonl', JSON.stringify({id, name: decodeURIComponent(url.split('name=')[1])}) + '\\n');
    return reply({id});
  }
  const assetMatch = url.match(/\\/releases\\/assets\\/(\\d+)$/);
  if (assetMatch) return new Response(process.env.CORRUPT_RELEASE ? 'replaced' : fs.readFileSync(dir + '/asset-' + assetMatch[1]));
  if (url === api + '/releases/789' && method === 'PATCH') return reply({id: 789});
  if (url === api + '/releases/789') return reply({id: 789, draft: false, prerelease: true, tag_name: '${TAG}',
    assets: fs.readFileSync(dir + '/assets.jsonl', 'utf8').trim().split('\\n').map(line => JSON.parse(line))});
  if (url === api + '/releases/latest') return reply({message: 'Not Found'}, 404);
  throw new Error('unexpected fixture request: ' + method + ' ' + url);
};
`);
    const bin = path.join(dir, 'bin'); fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'gh'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.FIXTURE_DIR + '/gh.jsonl', JSON.stringify(args) + '\\n');
const match = args[1] && args[1].match(/^repos\\/cjcj-dev\\/cjcj\\/releases\\/assets\\/(\\d+)$/);
if (args[0] !== 'api' || !match || args[3] !== 'Accept: application/octet-stream') process.exit(91);
process.stdout.write(fs.readFileSync(process.env.FIXTURE_DIR + '/asset-' + match[1]));
`, {mode: 0o755});
    const env = {...process.env, FIXTURE_DIR: dir, PATH: `${bin}:${process.env.PATH}`, BOOTSTRAP_ARCHIVES_PIN: registry,
      GITHUB_REPOSITORY: 'cjcj-dev/cjcj', GITHUB_TOKEN: 'fixture-token', GH_TOKEN: 'fixture-token', GITHUB_RUN_ID: '77',
      GITHUB_RUN_ATTEMPT: '1', GITHUB_SHA: HEAD, NATIVE_SDK_ARTIFACT_ID: '456', NATIVE_SDK_RUN_ID: '123',
      NATIVE_SDK_VERSION: VERSION, NATIVE_SDK_ACCEPTED_DIGEST: `sha256:${zipSha}`, ACCEPTANCE_JOB: 'package-tests'};
    for (const key of ['CANDIDATE_RUN', 'CANDIDATE_VERSION', 'CANDIDATE_ARTIFACT', 'EXPIRED', 'PRODUCER_CONCLUSION', 'CORRUPT_RELEASE', 'TAG_TAKEN',
      'ARTIFACT_SIZE', 'ARTIFACT_CREATED', 'PRODUCER_PATH', 'JOB_ATTEMPT', 'COMPARE_STATUS']) delete env[key];
    const run = (args, extra = {}) => {
      const result = spawnSync(process.execPath, ['--import', preload, entry, ...args], {env: {...env, ...extra}, encoding: 'utf8'});
      const read = name => fs.existsSync(path.join(dir, name))
        ? fs.readFileSync(path.join(dir, name), 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)) : [];
      return {...result, requests: read('requests.jsonl'), assets: read('assets.jsonl'), gh: read('gh.jsonl')};
    };
    check({dir, run, registry, env, zipSha});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

test('accepted candidate is persisted, read back through the consumer and never made latest', () => fixture(({dir, run, registry, env, zipSha}) => {
  const out = path.join(dir, 'out');
  const result = run(['publish', 'linux-x64', out]);
  assert.equal(result.status, 0, result.stderr + result.stdout);
  const create = result.requests.find(item => item.method === 'POST' && item.url.endsWith('/releases'));
  assert.deepEqual({...create.body, body: undefined}, {tag_name: TAG, target_commitish: SHA, name: TAG, draft: true,
    prerelease: true, make_latest: 'false', body: undefined});
  const patchIndex = result.requests.findIndex(item => item.method === 'PATCH');
  assert.deepEqual(result.requests[patchIndex].body, {draft: false, prerelease: true, make_latest: 'false'});
  assert(!result.requests.some(item => item.method === 'DELETE'));
  // Every asset is read back before the draft becomes visible.
  const lastAssetRead = result.requests.map(item => item.url).findLastIndex(url => /\/releases\/assets\/\d+$/.test(url));
  assert(lastAssetRead < patchIndex);
  assert.deepEqual(result.assets.map(item => item.name), [`${NAME}.zip`, `${NAME}.gate-logs.zip`, `${NAME}.provenance.json`]);
  assert.equal(digest(fs.readFileSync(path.join(dir, `asset-${result.assets[0].id}`))), zipSha);
  assert.deepEqual(result.gh, [['api', `repos/cjcj-dev/cjcj/releases/assets/${result.assets[0].id}`, '-H', 'Accept: application/octet-stream']]);
  const written = JSON.parse(fs.readFileSync(path.join(out, 'registry-entry.json'), 'utf8'));
  assert.deepEqual(written, {456: {repository: 'cjcj-dev/cjcj', asset: result.assets[0].id, release_sha256: zipSha, prerelease: true,
    tag: TAG, native_sdk: {target: 'linux-x64', version: VERSION, producer_run: 123, acceptance_run: 77}}});
  const provenance = JSON.parse(fs.readFileSync(path.join(out, 'provenance.json'), 'utf8'));
  assert.equal(provenance.producer.job.name, 'srcbuild / linux-x64 / source SDK / linux-x64 / srcbuild');
  // Bound to the exact producer attempt and to the bytes package-tests accepted.
  assert.deepEqual([provenance.producer.workflow, provenance.producer.attempt, provenance.producer.job.attempt, provenance.producer.commit],
    ['.github/workflows/release.yml', 2, 2, SHA]);
  assert.equal(provenance.acceptance.digest, `sha256:${zipSha}`);
  assert(!result.requests.some(item => /filter=latest|artifacts\?name=/.test(item.url)));
  assert.equal(provenance.readback.facts.version, VERSION);
  assert.deepEqual(provenance.retention.candidates, [{id: 11, tag: OLD, current: true}]);
  assert.match(result.stdout, new RegExp(`NATIVE_SDK_RETIRE_CANDIDATE tag=${OLD} release=11 current=true action=kept`));
  assert.match(result.stdout, new RegExp(`NATIVE_SDK_PERSISTED tag=${TAG} release=789 artifact=456`));
  // The committed registry is untouched; after a reviewed switch the consumer selects only the new entry.
  const before = JSON.parse(fs.readFileSync(registry, 'utf8'));
  assert.equal(before.artifacts[400].tag, OLD);
  delete before.artifacts[400];
  fs.writeFileSync(registry, JSON.stringify({...before, artifacts: {...before.artifacts, ...written}}));
  const selected = spawnSync(process.execPath, [downloader, '--select-native-sdk', 'linux-x64', 'cjcj-dev/cjcj'], {env, encoding: 'utf8'});
  assert.equal(selected.stdout, `artifact=456\nversion=${VERSION}\ntag=${TAG}\n`, selected.stderr);
}));

for (const [label, extra, options, code] of [
  ['producer gate job failed', {PRODUCER_CONCLUSION: 'failure'}, {}, /NATIVE_SDK_PRODUCER_GATE_NOT_PASSED/],
  ['artifact holds only logs', {}, {logsOnly: true}, /NATIVE_SDK_ARTIFACT_PACKAGE_MISSING/],
  ['artifact expired', {EXPIRED: '1'}, {}, /NATIVE_SDK_ARTIFACT_IDENTITY_MISMATCH/],
  ['tag already used', {TAG_TAKEN: '1'}, {}, /NATIVE_SDK_TAG_EXISTS/],
  ['artifact was created by another attempt', {ARTIFACT_CREATED: '2025-12-31T23:50:00Z'}, {}, /NATIVE_SDK_ARTIFACT_ATTEMPT_MISMATCH artifact=456/],
  ['gate job success belongs to another attempt', {JOB_ATTEMPT: '1'}, {}, /NATIVE_SDK_PRODUCER_GATE_NOT_PASSED attempt=2/],
  ['producer workflow is not an allowed srcbuild caller', {PRODUCER_PATH: '.github/workflows/ci.yml'}, {}, /NATIVE_SDK_PRODUCER_RUN_NOT_ALLOWED/],
  ['producer head is outside the accepted history', {COMPARE_STATUS: 'diverged'}, {}, /NATIVE_SDK_PRODUCER_HEAD_NOT_ANCESTOR/],
  ['artifact digest differs from the accepted digest', {NATIVE_SDK_ACCEPTED_DIGEST: `sha256:${'e'.repeat(64)}`}, {}, /NATIVE_SDK_ACCEPTED_DIGEST_MISMATCH/],
  ['artifact exceeds the release asset limit', {ARTIFACT_SIZE: String(2 * 1024 ** 3)}, {}, /NATIVE_SDK_ARTIFACT_SIZE_INVALID/],
]) {
  test(`no release is created when ${label}`, () => fixture(({dir, run}) => {
    const result = run(['publish', 'linux-x64', path.join(dir, 'out')], extra);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, code);
    assert(!result.requests.some(item => item.method !== 'GET'), JSON.stringify(result.requests.filter(item => item.method !== 'GET')));
    assert(fs.existsSync(path.join(dir, 'out', 'provenance.json')));
  }, options));
}

test('corrupt release readback keeps the draft unpublished', () => fixture(({dir, run}) => {
  const result = run(['publish', 'linux-x64', path.join(dir, 'out')], {CORRUPT_RELEASE: '1'});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch/);
  assert(result.requests.some(item => item.method === 'POST' && item.url.endsWith('/releases')));
  assert(!result.requests.some(item => item.method === 'PATCH' || item.method === 'DELETE'));
}));

test('selection: persisted entry by default, explicit candidate only, no silent fallback', () => fixture(({run, registry}) => {
  const persisted = run(['select', 'linux-x64']);
  assert.equal(persisted.status, 0, persisted.stderr);
  assert.equal(persisted.stdout, `mode=persisted\nartifact=400\nversion=1.2.2\nrun=\ntag=${OLD}\n`);
  assert.deepEqual(persisted.requests, []);
  const candidate = run(['select', 'linux-x64'], {CANDIDATE_RUN: '123', CANDIDATE_VERSION: VERSION});
  assert.equal(candidate.stdout, `mode=candidate\nartifact=456\nversion=${VERSION}\nrun=123\ntag=\n`, candidate.stderr);
  const partial = run(['select', 'linux-x64'], {CANDIDATE_RUN: '123'});
  assert.notEqual(partial.status, 0);
  assert.match(partial.stderr, /NATIVE_SDK_CANDIDATE_INPUT_INCOMPLETE/);
  const pins = JSON.parse(fs.readFileSync(registry, 'utf8'));
  pins.artifacts[401] = {...pins.artifacts[400], asset: 7};
  fs.writeFileSync(registry, JSON.stringify(pins));
  assert.match(run(['select', 'linux-x64']).stderr, /NATIVE_SDK_PERSISTENT_PIN_AMBIGUOUS target=linux-x64 count=2/);
}));

test('selection without an accepted SDK names the missing producer chain', () => fixture(({run}) => {
  const result = run(['select', 'linux-x64']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /NATIVE_SDK_PERSISTENT_PIN_MISSING target=linux-x64: no accepted full native SDK is persisted/);
  assert.deepEqual(result.requests, []);
}, {oldEntry: false}));

test('candidate acceptance downloads the exact selected artifact ID and reports its digest', () => fixture(({dir, run, zipSha}) => {
  const candidate = {CANDIDATE_ARTIFACT: '456', CANDIDATE_RUN: '123', CANDIDATE_VERSION: VERSION};
  const dest = path.join(dir, 'received');
  const result = run(['receive-candidate', 'linux-x64', dest], candidate);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `digest=sha256:${zipSha}\n`);
  const archive = `cangjie-sdk-linux-x64-${VERSION}-cjcj.tar.gz`;
  assert.deepEqual(fs.readdirSync(dest).sort(), [archive, `${archive}.sha256`, 'verify.log']);
  assert(result.requests.some(item => item.url.endsWith('/actions/artifacts/456/zip')));
  assert(!result.requests.some(item => item.method !== 'GET' || /artifacts\?name=|filter=latest/.test(item.url)));
  // A different artifact of the same producer run is refused before any byte is fetched.
  const other = run(['receive-candidate', 'linux-x64', path.join(dir, 'other')], {...candidate, CANDIDATE_ARTIFACT: '458'});
  assert.notEqual(other.status, 0);
  assert.match(other.stderr, /NATIVE_SDK_ARTIFACT_IDENTITY_MISMATCH artifact=458/);
  assert(!other.requests.some(item => item.url.endsWith('/actions/artifacts/458/zip')));
  // An artifact left by a failed earlier attempt is not acceptance input either.
  const stale = run(['receive-candidate', 'linux-x64', path.join(dir, 'stale')], {...candidate, ARTIFACT_CREATED: '2025-12-31T23:50:00Z'});
  assert.notEqual(stale.status, 0);
  assert.match(stale.stderr, /NATIVE_SDK_ARTIFACT_ATTEMPT_MISMATCH/);
  assert(!fs.existsSync(path.join(dir, 'stale')));
}));
