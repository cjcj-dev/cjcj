import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  assertSdkPathParity,
  collectRelativePaths,
  compareSdkPathSets,
  OFFICIAL_PATH_EXCLUSIONS,
} from '../lib/sdk-path-parity.mjs';

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-path-parity-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const official = path.join(root, 'official');
  const candidate = path.join(root, 'candidate');
  fs.mkdirSync(official);
  fs.mkdirSync(candidate);
  return {root, official, candidate};
}

function put(root, relative, contents = relative) {
  const file = path.join(root, ...relative.split('/'));
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents);
  return file;
}

test('SDK path inventory includes directories, files, and symlinks as normalized relative paths', t => {
  const {official} = fixture(t);
  put(official, 'bin/cjc');
  fs.symlinkSync('cjc', path.join(official, 'bin', 'cjc-frontend'));
  assert.deepEqual(collectRelativePaths(official), ['bin', 'bin/cjc', 'bin/cjc-frontend']);
});

test('candidate may replace contents and add paths while retaining every official path', async t => {
  const {official, candidate} = fixture(t);
  put(official, 'modules/linux/std/std.core.cjo', 'official bytes');
  put(candidate, 'modules/linux/std/std.core.cjo', 'rebuilt bytes');
  put(candidate, 'TOOLCHAIN_ID.tsv', 'lineage');

  const result = await assertSdkPathParity(candidate, {officialRoot: official});
  assert.deepEqual(result.missingInCandidate, []);
  assert.deepEqual(result.extraInCandidate, ['TOOLCHAIN_ID.tsv']);
});

test('only the explicit .cjv installation-metadata subtree is excluded', async t => {
  const {official, candidate} = fixture(t);
  put(official, '.cjv/nightly-release.json');
  put(official, '.cjv-neighbor/required');
  put(candidate, '.cjv-neighbor/required');

  assert.deepEqual(OFFICIAL_PATH_EXCLUSIONS, ['.cjv']);
  const green = await assertSdkPathParity(candidate, {officialRoot: official});
  assert.deepEqual(green.missingInCandidate, []);

  fs.rmSync(path.join(candidate, '.cjv-neighbor', 'required'));
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: official}),
    /missing-official-path\t\.cjv-neighbor\/required/,
  );
});

test('removing one required path from the candidate turns red on exactly that relative path', async t => {
  const {official, candidate} = fixture(t);
  for (const relative of ['tools', 'tools/bin', 'tools/bin/cjpm', 'tools/bin/cjfmt']) {
    const target = path.join(official, ...relative.split('/'));
    const ours = path.join(candidate, ...relative.split('/'));
    if (path.extname(relative) || relative.endsWith('cjpm') || relative.endsWith('cjfmt')) {
      put(official, relative);
      put(candidate, relative, 'rebuilt');
    } else {
      fs.mkdirSync(target, {recursive: true});
      fs.mkdirSync(ours, {recursive: true});
    }
  }
  fs.rmSync(path.join(candidate, 'tools', 'bin', 'cjfmt'));

  const result = compareSdkPathSets(official, candidate);
  assert.deepEqual(result.missingInCandidate, ['tools/bin/cjfmt']);
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: official}),
    error => error.stage === 'package.sdk-path-parity'
      && /missing-official-path\ttools\/bin\/cjfmt/.test(error.message)
      && !/missing-official-path\ttools\/bin\/cjpm/.test(error.message),
  );
});

test('removing a path from the official sample does not reverse the official-minus-candidate gate', async t => {
  const {official, candidate} = fixture(t);
  put(official, 'bin/cjc');
  put(official, 'tools/bin/cjpm');
  put(candidate, 'bin/cjc', 'rebuilt');
  put(candidate, 'tools/bin/cjpm', 'rebuilt');

  fs.rmSync(path.join(official, 'tools', 'bin', 'cjpm'));
  const result = await assertSdkPathParity(candidate, {officialRoot: official});
  assert.deepEqual(result.missingInCandidate, []);
  assert.ok(result.extraInCandidate.includes('tools/bin/cjpm'));
});

test('missing or non-directory official samples fail closed', async t => {
  const {root, candidate} = fixture(t);
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: path.join(root, 'absent')}),
    /SDK directory missing/,
  );
});
