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
  assert.deepEqual(collectRelativePaths(official), [
    {relativePath: 'bin', type: 'dir', symlinkTarget: null},
    {relativePath: 'bin/cjc', type: 'file', symlinkTarget: null},
    {relativePath: 'bin/cjc-frontend', type: 'symlink', symlinkTarget: 'cjc'},
  ]);
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

test('replacing one required symlink with a same-name file turns red on exactly that path', async t => {
  const {official, candidate} = fixture(t);
  put(official, 'bin/cjc');
  put(candidate, 'bin/cjc', 'rebuilt');
  fs.symlinkSync('cjc', path.join(official, 'bin', 'cjc-frontend'));
  put(candidate, 'bin/cjc-frontend', 'copied binary');

  const result = compareSdkPathSets(official, candidate);
  assert.deepEqual(result.missingInCandidate, []);
  assert.deepEqual(result.typeMismatches, [{
    relativePath: 'bin/cjc-frontend',
    officialType: 'symlink',
    candidateType: 'file',
    officialSymlinkTarget: 'cjc',
    candidateSymlinkTarget: null,
  }]);
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: official}),
    error => error.stage === 'package.sdk-path-parity'
      && /type-mismatch\tbin\/cjc-frontend\tofficial=symlink->cjc\tcandidate=file/.test(error.message)
      && !/missing-official-path/.test(error.message),
  );
});

test('matching entry types and symlink targets do not turn the parity gate red', async t => {
  const {official, candidate} = fixture(t);
  put(official, 'bin/cjc');
  put(candidate, 'bin/cjc', 'rebuilt');
  fs.symlinkSync('cjc', path.join(official, 'bin', 'cjc-frontend'));
  fs.symlinkSync('cjc', path.join(candidate, 'bin', 'cjc-frontend'));

  const result = await assertSdkPathParity(candidate, {officialRoot: official});
  assert.deepEqual(result.missingInCandidate, []);
  assert.deepEqual(result.typeMismatches, []);
});

test('changing one required symlink target reports only that path as a type mismatch', async t => {
  const {official, candidate} = fixture(t);
  for (const root of [official, candidate]) {
    put(root, 'bin/cjc');
    put(root, 'bin/cjc-alt');
  }
  fs.symlinkSync('cjc', path.join(official, 'bin', 'cjc-frontend'));
  fs.symlinkSync('cjc-alt', path.join(candidate, 'bin', 'cjc-frontend'));

  const result = compareSdkPathSets(official, candidate);
  assert.deepEqual(result.typeMismatches.map(mismatch => mismatch.relativePath), ['bin/cjc-frontend']);
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: official}),
    /type-mismatch\tbin\/cjc-frontend\tofficial=symlink->cjc\tcandidate=symlink->cjc-alt/,
  );
});

test('missing or non-directory official samples fail closed', async t => {
  const {root, candidate} = fixture(t);
  await assert.rejects(
    assertSdkPathParity(candidate, {officialRoot: path.join(root, 'absent')}),
    /SDK directory missing/,
  );
});


test('compiler alias exception requires both relative entries and the physical stage producer', async t => {
  const {official, candidate} = fixture(t);
  put(official, 'bin/cjc');
  fs.symlinkSync('cjc', path.join(official, 'bin/cjc-frontend'));
  put(candidate, 'bin/cjcj-stage1');
  for (const name of ['cjc', 'cjc-frontend']) fs.symlinkSync('cjcj-stage1', path.join(candidate, 'bin', name));
  await assertSdkPathParity(candidate, {officialRoot: official});
  fs.unlinkSync(path.join(candidate, 'bin/cjc-frontend'));
  put(candidate, 'bin/cjc-frontend');
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot: official}), /type-mismatch\tbin\/cjc\t/);
});

test('native Linux parity excludes the complete Windows closure but retains native and unspecified requirements', async t => {
  const {official, candidate} = fixture(t);
  for (const rel of ['runtime/lib/windows_x86_64_cjnative/runtime.dll', 'third_party/mingw/lib/crt2.o',
    'lib/libstdFFI.dll', 'lib/libstdFFI.dll.a']) put(official, rel);
  for (const rel of ['LICENSE', 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so']) {
    put(official, rel); put(candidate, rel);
  }
  for (const rel of ['lib', 'third_party']) fs.mkdirSync(path.join(candidate, rel), {recursive:true});
  await assertSdkPathParity(candidate, {officialRoot:official, target:'linux-x64'});
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot:official}), /missing-official-path\tlib\/libstdFFI.dll/);
  fs.unlinkSync(path.join(candidate, 'LICENSE'));
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot:official, target:'linux-x64'}), /missing-official-path\tLICENSE/);
});

test('file interfaces accept internal relative file links, retaining broken, outside and directory rejection', async t => {
  const {root, official, candidate} = fixture(t);
  put(official, 'third_party/llvm/lib/libxml2.so');
  const lib = 'third_party/llvm/lib/';
  put(candidate, lib + 'libxml2.so.16.1.4');
  fs.symlinkSync('libxml2.so.16.1.4', path.join(candidate, lib, 'libxml2.so'));
  await assertSdkPathParity(candidate, {officialRoot:official});
  fs.unlinkSync(path.join(candidate, lib, 'libxml2.so.16.1.4'));
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot:official}), /package-link-invalid/);
  fs.mkdirSync(path.join(candidate, lib, 'libxml2.so.16.1.4'));
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot:official}), /type-mismatch/);
  fs.unlinkSync(path.join(candidate, lib, 'libxml2.so'));
  const outside = put(root, 'outside.so');
  fs.symlinkSync(outside, path.join(candidate, lib, 'libxml2.so'));
  await assert.rejects(assertSdkPathParity(candidate, {officialRoot:official}), /package-link-outside/);
});

test('private cjlint config requires its actual entry and every former config; current cjprof needs its payload', async t => {
  const {official, candidate} = fixture(t);
  for (const name of ['cjlint', 'cjprof']) {
    const retained = name === 'cjlint' ? '.target-tools/tools/cjlint/bin/cjlint' : '.target-tools/tools/bin/cjprof';
    put(candidate, 'tools/bin/' + name);
    put(candidate, retained);
    put(candidate, 'tools/bin/' + name + '.entry', 'cjcj-sdk-entry-v1\n2\n' + retained + '\nlinux\nnative-target:x64\n');
    put(official, 'tools/lib/lib' + name + '.so');
  }
  put(official, 'tools/config/cjlint_rule_list.json');
  put(candidate, '.target-tools/tools/cjlint/config/cjlint_rule_list.json');
  put(candidate, '.target-tools/tools/cjlint/modules/parser.cjo');
  for (const rel of ['tools/lib/libcjprof-cangjie.so', 'tools/lib/libcjprof-jni.so', 'tools/share/java/cjprof.jar']) put(candidate, rel);
  // Common directories are still real interfaces, not excluded wholesale.
  fs.mkdirSync(path.join(candidate, 'tools/config'), {recursive:true});
  const options = {officialRoot:official, target:'linux-x64'};
  await assertSdkPathParity(candidate, options);
  fs.unlinkSync(path.join(candidate, 'tools/lib/libcjprof-jni.so'));
  await assert.rejects(assertSdkPathParity(candidate, options), /missing-official-path\ttools\/lib\/libcjprof.so/);
  put(candidate, 'tools/lib/libcjprof-jni.so');
  fs.unlinkSync(path.join(candidate, '.target-tools/tools/cjlint/config/cjlint_rule_list.json'));
  await assert.rejects(assertSdkPathParity(candidate, options), /missing-official-path\ttools\/config\/cjlint_rule_list.json/);
});
