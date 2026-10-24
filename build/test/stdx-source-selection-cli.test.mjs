import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture, run} from './fixtures/stdx-native.mjs';
import {getTarget} from '../lib/targets.mjs';
import {buildConfig, withBuildType} from '../lib/config.mjs';
import {readInstalledStdxInputs} from '../lib/installed-stdx-inputs.mjs';
import {STDX_BUILD_INPUTS} from '../srcbuild/stdx-build-inputs.mjs';

const repository = 'https://example.invalid/fixed-stdx-source.git';
const platform = getTarget('linux-x64').spec.llvmPlatform;
function select(f, selection) {
  fs.writeFileSync(path.join(f.root, '.source-selection.json'), JSON.stringify({stdx: selection}));
}
function originless(f) { run('git', ['-C', f.stdx, 'remote', 'remove', 'origin']); }
function rejected(f, expression) {
  const result = f.build();
  console.log('STDX_SOURCE_REJECTION_ASSERT_REACHED');
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, expression);
  assert.equal(fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)), false);
  assert.equal(fs.existsSync(path.join(f.stdx, 'build_temp/build/CMakeCache.txt')), false);
}

test('public originless producer carries explicit fixed selection through install and relocated CI reader', async t => {
  const f = fixture(t); originless(f); select(f, {url: repository, tag: f.commit});
  const tree = run('git', ['-C', f.stdx, 'rev-parse', 'HEAD^{tree}']).stdout.trim();
  const result = f.build(); assert.equal(result.status, 0, result.stdout + result.stderr);
  const facts = await readInstalledStdxInputs({sdk: f.sdk, platform, requireFull: true});
  console.log('STDX_SELECTED_REPOSITORY_ASSERT_REACHED');
  assert.equal(facts.source.repository, repository);
  assert.equal(facts.source.repositorySource, 'sourceSelection');
  assert.equal(facts.source.commit, f.commit); assert.equal(facts.source.tree, tree);
  assert.equal(facts.source.checkout, fs.realpathSync(f.stdx));
  assert.equal(run('git', ['-C', f.stdx, 'remote']).stdout, '');
  assert.equal(facts.artifacts.length, 24);
  const archive = path.join(f.root, 'installation.tar'), unpack = path.join(f.root, 'unpacked');
  run('tar', ['-cf', archive, '-C', f.sdk, '.']);
  fs.renameSync(f.sdk, f.sdk + '.unreachable');
  fs.renameSync(f.stdx, f.stdx + '.unreachable');
  fs.mkdirSync(unpack); run('tar', ['-xf', archive, '-C', unpack]);
  assert.deepEqual(await readInstalledStdxInputs({sdk: unpack, platform, requireFull: true}), facts);
  const product = facts.artifacts.find(item => item.path.endsWith('.cjo'));
  fs.renameSync(path.join(unpack, product.path), path.join(unpack, product.path)+'.saved');
  await assert.rejects(readInstalledStdxInputs({sdk: unpack, platform, requireFull: true}), /ENOENT/);
});

for (const [name, selection] of [
  ['unknown source', () => null],
  ['URL without fixed revision', () => ({url: repository})],
  ['revision without explicit URL', f => ({tag: f.commit})],
  ['symbolic revision', () => ({url: repository, tag: 'HEAD'})],
]) {
  test('public originless producer rejects ' + name, t => {
    const f = fixture(t); originless(f); const options = selection(f); if (options) select(f, options); else fs.writeFileSync(path.join(f.root, '.source-selection.json'), '{}');
    if (!options) assert.equal(withBuildType(buildConfig({workspace: f.root}), 'release').sourceSelection.stdx, undefined);
    rejected(f, name === 'URL without fixed revision' || name === 'unknown source'
      ? /\[source.identity\] stdx: HEAD [0-9a-f]{40}, expected [0-9a-f]{40}; use a separate workspace/
      : /originless stdx requires explicit repository and fixed source selection/);
  });
}
test('public originless producer rejects selection different from real HEAD', t => {
  const f = fixture(t); originless(f); select(f, {url: repository, tag: '0'.repeat(40)});
  rejected(f, /\[source.identity\] stdx: HEAD [0-9a-f]{40}, expected 0000000000000000000000000000000000000000; use a separate workspace/);
});
test('public origin producer rejects a contradictory repository selection', t => {
  const f = fixture(t); select(f, {url: repository, tag: f.commit});
  rejected(f, /\[source.identity\] stdx: origin https:\/\/gitcode.com\/Cangjie\/cangjie_stdx.git, expected https:\/\/example.invalid\/fixed-stdx-source.git; use a separate workspace/);
});
test('public originless producer rejects an unmaterialized fixed tree', t => {
  const f = fixture(t); originless(f); select(f, {url: repository, tag: f.commit});
  fs.unlinkSync(path.join(f.stdx, 'input.cj'));
  rejected(f, /\[source.identity\] stdx: tracked source differs from HEAD: input.cj; preserve it and use a separate workspace/);
});
