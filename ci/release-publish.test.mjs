import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';
import {getReleasePlatform} from '../build/lib/targets.mjs';
import {expectedArchiveKeys, releaseWorkflowProblems, verifyAssets, verifyCiRun, verifyNeeds} from './release-publish.mjs';

const root = path.resolve(import.meta.dirname, '..');
const releaseText = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
const sha = 'a'.repeat(40);
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

test('release.yml satisfies the publish contract and packages exactly the 15 archiveKeys', () => {
  assert.deepEqual(releaseWorkflowProblems(releaseText), []);
  const jobs = loadYaml(releaseText).jobs;
  const packaged = Object.values(jobs).filter(job => job.with?.mode === 'package')
    .map(job => getReleasePlatform(job.with.release_key).archiveKey).sort();
  assert.deepEqual(packaged, expectedArchiveKeys());
  assert.equal(expectedArchiveKeys().length, 15);
  assert.ok(!expectedArchiveKeys().some(key => key.startsWith('diagnosis')));
});

// Each red cut is applied to the real workflow text and must be named precisely.
const cuts = [
  ['always() restored', text => text.replace("if: inputs.phase == 'publish' && !inputs.dry_run", "if: always() && inputs.phase == 'publish' && !inputs.dry_run"), /must not use always/],
  ['--target dropped', text => text.replace('flags=(--target "$GITHUB_SHA" ', 'flags=('), /lacks --target/],
  ['--latest=false dropped', text => text.replace('--prerelease --latest=false', '--prerelease'), /lacks --prerelease --latest=false/],
  ['existing release check dropped', text => text.replaceAll('RELEASE_ALREADY_EXISTS', 'RELEASE_SEEN'), /existing release check/],
  ['existing tag check dropped', text => text.replaceAll('TAG_ALREADY_EXISTS', 'TAG_SEEN'), /existing tag check/],
  ['one need removed', text => text.replace(', package-win32-x64-wasm, package-linux-x64-ohos', ', package-linux-x64-ohos'), /publish needs 19 jobs/],
  ['win32 wasm loses its native switch', text => {
    const start = text.indexOf('  package-win32-x64-wasm:');
    const end = text.indexOf('secrets: inherit', start);
    return text.slice(0, start) + text.slice(start, end).replace(/\n      native_runtime_artifact: .*/, '') + text.slice(end);
  }, /package-win32-x64-wasm does not pass native_runtime_artifact/],
  ['phase default publish', text => text.replace('default: prepare', 'default: publish'), /phase must be a choice/],
];
for (const [name, cut, expected] of cuts) {
  test(`red cut: ${name}`, () => {
    const mutated = cut(releaseText);
    assert.notEqual(mutated, releaseText, `cut ${name} did not apply`);
    const problems = releaseWorkflowProblems(mutated);
    assert.ok(problems.some(problem => expected.test(problem)), JSON.stringify(problems));
  });
}

function fixtureDist(t, version = '0.0.2') {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'release-publish-'));
  t.after(() => fs.rmSync(dist, {recursive: true, force: true}));
  for (const key of expectedArchiveKeys()) {
    const stem = `cjcj-${version}-${key}`;
    const staging = path.join(dist, '.stage', key, 'cangjie');
    fs.mkdirSync(staging, {recursive: true});
    const manifest = `{"key":"${key}"}\n`;
    fs.writeFileSync(path.join(staging, 'RELEASE-MANIFEST.jsonl'), manifest);
    const zip = key.startsWith('win') || key.startsWith('windows');
    const archive = `${stem}.${zip ? 'zip' : 'tar.gz'}`;
    const result = zip
      ? spawnSync('zip', ['-qr', path.join(dist, archive), 'cangjie'], {cwd: path.dirname(staging)})
      : spawnSync('tar', ['-czf', path.join(dist, archive), '-C', path.dirname(staging), 'cangjie']);
    assert.equal(result.status, 0, String(result.stderr));
    const hash = digest(path.join(dist, archive));
    fs.writeFileSync(path.join(dist, `${archive}.sha256`), `${hash}  ${archive}\n`);
    fs.writeFileSync(path.join(dist, `${stem}.SHA256SUMS`), `${hash}  ${archive}\n`);
    fs.writeFileSync(path.join(dist, `${stem}.RELEASE-MANIFEST.jsonl`), manifest);
  }
  fs.rmSync(path.join(dist, '.stage'), {recursive: true, force: true});
  return dist;
}

test('verify-assets accepts exactly 15 complete cells (60 assets) and rejects each defect', t => {
  const dist = fixtureDist(t);
  assert.equal(verifyAssets({dist, version: '0.0.2'}).length, 60);
  const archive = fs.readdirSync(dist).find(file => file.endsWith('-linux-x64.tar.gz'));
  const sidecar = path.join(dist, 'cjcj-0.0.2-linux-x64.RELEASE-MANIFEST.jsonl');
  const original = fs.readFileSync(sidecar);
  fs.writeFileSync(sidecar, '{"key":"other"}\n');
  assert.throws(() => verifyAssets({dist, version: '0.0.2'}), /^Error: PUBLISH_MANIFEST_MISMATCH linux-x64/);
  fs.writeFileSync(sidecar, original);
  fs.writeFileSync(path.join(dist, 'pkg-diagnosis-linux-x64-1.json'), '{}');
  assert.throws(() => verifyAssets({dist, version: '0.0.2'}), /^Error: PUBLISH_DIAGNOSIS_ASSET/);
  fs.rmSync(path.join(dist, 'pkg-diagnosis-linux-x64-1.json'));
  fs.writeFileSync(path.join(dist, 'extra.txt'), 'x');
  assert.throws(() => verifyAssets({dist, version: '0.0.2'}), /^Error: PUBLISH_STRAY_ASSET extra.txt/);
  fs.rmSync(path.join(dist, 'extra.txt'));
  const sums = path.join(dist, `${archive}.sha256`);
  const good = fs.readFileSync(sums);
  fs.writeFileSync(sums, `${'0'.repeat(64)}  ${archive}\n`);
  assert.throws(() => verifyAssets({dist, version: '0.0.2'}), /^Error: PUBLISH_SHA256 /);
  fs.writeFileSync(sums, good);
  for (const file of fs.readdirSync(dist).filter(file => file.includes('-darwin-x64.'))) fs.rmSync(path.join(dist, file));
  assert.throws(() => verifyAssets({dist, version: '0.0.2'}), /^Error: PUBLISH_ARCHIVE_CELL darwin-x64 has 0 archives/);
});

test('verify-needs requires all 20 direct needs to be success', () => {
  const needs = Object.fromEntries(Array.from({length: 20}, (_, index) => [`job-${index}`, {result: 'success'}]));
  assert.equal(verifyNeeds(needs), 20);
  assert.throws(() => verifyNeeds({...needs, 'job-3': {result: 'skipped'}}), /^Error: PUBLISH_NEEDS_NOT_SUCCESS job-3=skipped/);
  assert.throws(() => verifyNeeds({...needs, 'job-4': {result: 'cancelled'}}), /^Error: PUBLISH_NEEDS_NOT_SUCCESS job-4=cancelled/);
  const {['job-0']: _, ...nineteen} = needs;
  assert.throws(() => verifyNeeds(nineteen), /^Error: PUBLISH_NEEDS_COUNT 19/);
});

test('verify-ci-run binds the CI run to this commit and to success', () => {
  const run = {id: 7, head_sha: sha, status: 'completed', conclusion: 'success', path: '.github/workflows/ci.yml'};
  assert.equal(verifyCiRun(run, sha), 7);
  assert.throws(() => verifyCiRun({...run, head_sha: 'b'.repeat(40)}, sha), /^Error: PUBLISH_CI_HEAD_SHA/);
  assert.throws(() => verifyCiRun({...run, conclusion: 'failure'}, sha), /^Error: PUBLISH_CI_CONCLUSION/);
  assert.throws(() => verifyCiRun({...run, path: '.github/workflows/release.yml'}, sha), /^Error: PUBLISH_CI_WORKFLOW/);
});
