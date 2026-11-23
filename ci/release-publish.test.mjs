import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';
import {getReleasePlatform} from '../build/lib/targets.mjs';
import {expectedArchiveKeys, releaseWorkflowProblems, selectPackageArtifacts, verifyAssets, verifyCiRun, verifyNeeds} from './release-publish.mjs';

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
  ['tag claim moved off GITHUB_SHA', text => text.replace('-f sha="$GITHUB_SHA"', '-f sha="$TAG_SHA"'), /lacks atomic tag claim/],
  ['--verify-tag dropped', text => text.replace('flags=(--verify-tag ', 'flags=('), /lacks --verify-tag/],
  ['formal release refusal dropped', text => text.replaceAll('PUBLISH_FORMAL_RELEASE_NOT_AUTHORIZED', 'FORMAL'), /formal release refusal/],
  ['tag readback dropped', text => text.replaceAll('PUBLISH_READBACK_TAG', 'TAG_OK'), /tag readback/],
  ['release readback dropped', text => text.replaceAll('PUBLISH_READBACK_RELEASE', 'REL_OK'), /release readback/],
  ['merged package download restored', text => text.replace('merge-multiple: false', 'merge-multiple: true'), /per-artifact directories/],
  ['name-based selection dropped', text => text.replace('node ci/release-publish.mjs select-packages', 'true'), /name-based package artifact selection/],
  ['approval environment dropped', text => text.replace('    environment: release-publish\n', ''), /deployment environment/],
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

test('select-packages takes pkg-<key> artifacts by name and never a diagnosis artifact', t => {
  const from = fs.mkdtempSync(path.join(os.tmpdir(), 'release-artifacts-'));
  t.after(() => fs.rmSync(from, {recursive: true, force: true}));
  const keys = expectedArchiveKeys();
  for (const key of keys) {
    fs.mkdirSync(path.join(from, `pkg-${key}`));
    fs.writeFileSync(path.join(from, `pkg-${key}`, `cjcj-0.0.2-${key}.tar.gz`), key);
  }
  // A diagnosis artifact may hold same-named files; selection is by artifact name.
  fs.mkdirSync(path.join(from, `pkg-diagnosis-${keys[0]}-1`));
  fs.writeFileSync(path.join(from, `pkg-diagnosis-${keys[0]}-1`, `cjcj-0.0.2-${keys[0]}.tar.gz`), 'diagnosis');
  const to = path.join(from, '..', path.basename(from) + '-dist');
  t.after(() => fs.rmSync(to, {recursive: true, force: true}));
  const result = selectPackageArtifacts({from, to});
  assert.equal(result.selected.length, 15);
  assert.deepEqual(result.excluded, [`pkg-diagnosis-${keys[0]}-1`]);
  assert.equal(fs.readFileSync(path.join(to, `cjcj-0.0.2-${keys[0]}.tar.gz`), 'utf8'), keys[0]);
  fs.mkdirSync(path.join(from, 'pkg-extra'));
  assert.throws(() => selectPackageArtifacts({from, to: to + '2'}), /PUBLISH_ARTIFACT_UNEXPECTED pkg-extra/);
  fs.rmSync(path.join(from, 'pkg-extra'), {recursive: true});
  fs.rmSync(path.join(from, `pkg-${keys[1]}`), {recursive: true});
  assert.throws(() => selectPackageArtifacts({from, to: to + '3'}), new RegExp(`PUBLISH_ARTIFACT_MISSING ${keys[1]}`));
});

// The real "Publish GitHub release" run block against a gh stub: every arm
// executes the shipped shell, so a red cut reaches the asserted guard.
const publishScript = loadYaml(releaseText).jobs.publish.steps.find(step => step.name === 'Publish GitHub release').run;
function publishArm(t, overrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-gh-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  fs.mkdirSync(path.join(dir, 'bin'));
  fs.writeFileSync(path.join(dir, 'bin/gh'), `#!/bin/bash
echo "$*" >> "$STUB_DIR/calls"
tag=refs/tags/v0.0.2
case "$*" in
  "api repos/o/r/releases/tags/v0.0.2")
    [ "$STUB_RELEASE" = 404 ] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    [ "$STUB_RELEASE" = 503 ] && { echo 'gh: Service Unavailable (HTTP 503)' >&2; exit 1; }
    echo '{}';;
  "api repos/o/r/git/ref/tags/v0.0.2 --jq"*)
    if [[ "$*" == *'.object.type'* ]]; then echo "commit $STUB_READBACK_SHA"; else echo "$STUB_READBACK_SHA"; fi;;
  "api repos/o/r/git/ref/tags/v0.0.2")
    [ "$STUB_TAG" = 404 ] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    echo '{}';;
  "api -X POST repos/o/r/git/refs -f ref=$tag -f sha="*)
    [ "$STUB_CLAIM" = 422 ] && { echo 'Reference already exists (HTTP 422)' >&2; exit 1; }
    exit 0;;
  "api -X DELETE repos/o/r/git/refs/tags/v0.0.2") exit 0;;
  "release create v0.0.2 "*) [ "$STUB_CREATE" = fail ] && exit 1; exit 0;;
  "release view v0.0.2 "*) echo "$STUB_VIEW";;
  *) echo "unexpected gh $*" >&2; exit 9;;
esac
`, {mode: 0o755});
  fs.writeFileSync(path.join(dir, 'publish-assets.txt'), Array.from({length: 60}, (_, i) => `dist/a${i}`).join('\n') + '\n');
  fs.writeFileSync(path.join(dir, 'release-notes.md'), 'notes\n');
  const env = {PATH: `${path.join(dir, 'bin')}:${process.env.PATH}`, STUB_DIR: dir, RUNNER_TEMP: dir,
    GITHUB_REPOSITORY: 'o/r', GITHUB_SHA: sha, RELEASE_VERSION: '0.0.2', RELEASE_PRERELEASE: 'true', RELEASE_DRAFT: 'false',
    STUB_RELEASE: '404', STUB_TAG: '404', STUB_CLAIM: 'ok', STUB_CREATE: 'ok', STUB_READBACK_SHA: sha, STUB_VIEW: 'true 60', ...overrides};
  const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', publishScript], {env, encoding: 'utf8'});
  const calls = fs.existsSync(path.join(dir, 'calls')) ? fs.readFileSync(path.join(dir, 'calls'), 'utf8') : '';
  return {rc: result.status, out: result.stdout + result.stderr, calls};
}
test('publish shell: prerelease only, atomic tag claim at GITHUB_SHA, readback of tag and release', t => {
  const ok = publishArm(t);
  assert.equal(ok.rc, 0, ok.out);
  assert.match(ok.calls, new RegExp(`api -X POST repos/o/r/git/refs -f ref=refs/tags/v0.0.2 -f sha=${sha}`));
  assert.match(ok.calls, /release create v0\.0\.2 --verify-tag .*--prerelease --latest=false/);
  const arms = [
    [{RELEASE_PRERELEASE: 'false'}, /PUBLISH_FORMAL_RELEASE_NOT_AUTHORIZED/],
    [{STUB_RELEASE: '200'}, /RELEASE_ALREADY_EXISTS/],
    [{STUB_RELEASE: '503'}, /RELEASE_LOOKUP_FAILED/],
    [{STUB_TAG: '200'}, /TAG_ALREADY_EXISTS v0\.0\.2$/m],
    [{STUB_CLAIM: '422'}, /TAG_ALREADY_EXISTS v0\.0\.2 \(claim refused\)/],
    [{STUB_READBACK_SHA: 'b'.repeat(40)}, /PUBLISH_READBACK_TAG/],
    [{STUB_VIEW: 'true 59'}, /PUBLISH_READBACK_RELEASE/],
    [{STUB_CREATE: 'fail'}, /PUBLISH_RELEASE_CREATE_FAILED/],
  ];
  for (const [overrides, expected] of arms) {
    const arm = publishArm(t, overrides);
    assert.equal(arm.rc, 1, JSON.stringify(overrides) + arm.out);
    assert.match(arm.out, expected, JSON.stringify(overrides));
    if (overrides.RELEASE_PRERELEASE || overrides.STUB_RELEASE || overrides.STUB_TAG || overrides.STUB_CLAIM)
      assert.doesNotMatch(arm.calls, /release create/, JSON.stringify(overrides));
  }
  // A failed creation releases only this run's own claim.
  assert.match(publishArm(t, {STUB_CREATE: 'fail'}).calls, /api -X DELETE repos\/o\/r\/git\/refs\/tags\/v0\.0\.2/);
  assert.doesNotMatch(publishArm(t, {STUB_CREATE: 'fail', STUB_READBACK_SHA: 'c'.repeat(40)}).calls, /DELETE/);
});
