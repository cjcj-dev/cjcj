import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {aggregateSums, parseSums, sumsFileName, writePlatformSums} from './package_checksums.mjs';

const script = path.resolve(import.meta.dirname, 'package_checksums.mjs');
const sha = text => crypto.createHash('sha256').update(text).digest('hex');

// One packaged platform as scripts/package_sdk.mjs leaves it in dist/.
function fakePackage(dist, version, platform, {archive = 'tar.gz', body = `archive ${platform}`} = {}) {
  const stem = `cjcj-${version}-${platform}`;
  fs.mkdirSync(dist, {recursive: true});
  fs.writeFileSync(path.join(dist, `${stem}.${archive}`), body);
  fs.writeFileSync(path.join(dist, `${stem}.${archive}.sha256`), `${sha(body)}  ${stem}.${archive}\n`);
  fs.writeFileSync(path.join(dist, `${stem}.RELEASE-MANIFEST.jsonl`), `{"platform":"${platform}"}\n`);
  return stem;
}

test('write lists archive and manifest with digests that match the packager sidecar', () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'sums-'));
  const stem = fakePackage(dist, '0.0.2', 'linux-x64');
  const {file, entries} = writePlatformSums({dist, version: '0.0.2', platform: 'linux-x64'});
  assert.equal(path.basename(file), sumsFileName('0.0.2', 'linux-x64'));
  assert.deepEqual(entries.map(entry => entry.name), [`${stem}.tar.gz`, `${stem}.RELEASE-MANIFEST.jsonl`]);
  assert.equal(entries[0].sha256, sha('archive linux-x64'));
  assert.deepEqual(parseSums(fs.readFileSync(file, 'utf8')), entries);
});

test('write refuses an archive whose bytes no longer match the sidecar, and a platform with no archive', () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'sums-'));
  const stem = fakePackage(dist, '0.0.2', 'windows-x64', {archive: 'zip'});
  fs.appendFileSync(path.join(dist, `${stem}.zip`), 'tampered');
  assert.throws(() => writePlatformSums({dist, version: '0.0.2', platform: 'windows-x64'}), /sidecar .*\.zip\.sha256 records [0-9a-f]{64} .*archive hashes to/);
  assert.throws(() => writePlatformSums({dist, version: '0.0.2', platform: 'darwin-x64'}), /no package archive for darwin-x64: expected cjcj-0\.0\.2-darwin-x64\.tar\.gz or .*\.zip/);
});

test('aggregate combines every expected platform and names the one that has no package', () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'sums-'));
  for (const platform of ['linux-x64', 'linux-aarch64']) {
    fakePackage(dist, '0.0.2', platform);
    writePlatformSums({dist, version: '0.0.2', platform});
  }
  const {file, entries} = aggregateSums({dist, version: '0.0.2', expect: ['linux-x64', 'linux-aarch64']});
  assert.equal(path.basename(file), 'SHA256SUMS');
  assert.equal(entries.length, 4);
  assert.throws(
    () => aggregateSums({dist, version: '0.0.2', expect: ['linux-x64', 'linux-aarch64', 'darwin-arm64']}),
    /darwin-arm64: cjcj-0\.0\.2-darwin-arm64\.SHA256SUMS not in .*\(its package job did not succeed\)/,
  );
});

test('aggregate refuses a listed file that changed or vanished after its SHA256SUMS was written', () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'sums-'));
  const stem = fakePackage(dist, '0.0.2', 'darwin-arm64');
  writePlatformSums({dist, version: '0.0.2', platform: 'darwin-arm64'});
  fs.writeFileSync(path.join(dist, `${stem}.RELEASE-MANIFEST.jsonl`), 'rewritten\n');
  assert.throws(() => aggregateSums({dist, version: '0.0.2', expect: ['darwin-arm64']}), /darwin-arm64: .*RELEASE-MANIFEST\.jsonl hashes to [0-9a-f]{64}, SHA256SUMS says/);
  fs.rmSync(path.join(dist, `${stem}.tar.gz`));
  assert.throws(() => aggregateSums({dist, version: '0.0.2', expect: ['darwin-arm64']}), /darwin-arm64: .*\.tar\.gz listed in .* but absent/);
});

test('the CLI exits 1 on an incomplete aggregate and 0 on a complete one', () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'sums-'));
  fakePackage(dist, '0.0.2', 'linux-x64');
  const write = spawnSync(process.execPath, [script, 'write', '--dist', dist, '--platform', 'linux-x64', '--version', '0.0.2'], {encoding: 'utf8'});
  assert.equal(write.status, 0, write.stderr);
  assert.match(write.stdout, /SHA256SUMS .*cjcj-0\.0\.2-linux-x64\.SHA256SUMS/);
  const incomplete = spawnSync(process.execPath, [script, 'aggregate', '--dist', dist, '--version', '0.0.2', '--expect', 'linux-x64,linux-aarch64'], {encoding: 'utf8'});
  assert.equal(incomplete.status, 1);
  assert.match(incomplete.stderr, /linux-aarch64: .*not in/);
  assert.ok(!fs.existsSync(path.join(dist, 'SHA256SUMS')), 'an incomplete aggregate writes nothing');
  const complete = spawnSync(process.execPath, [script, 'aggregate', '--dist', dist, '--version', '0.0.2', '--expect', 'linux-x64'], {encoding: 'utf8'});
  assert.equal(complete.status, 0, complete.stderr);
  assert.equal(parseSums(fs.readFileSync(path.join(dist, 'SHA256SUMS'), 'utf8')).length, 2);
});
