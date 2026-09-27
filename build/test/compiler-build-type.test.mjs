import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {compilerBuildTypeToml} from '../../ci/srcbuild/lib/compiler-build-type.mjs';

const toml = fs.readFileSync(new URL('../../packages/cjc/cjpm.toml', import.meta.url), 'utf8');

test('published native and cross recipes all select release', () => {
  for (const targetKey of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64', 'windows-x64']) {
    const config = buildConfig({targetKey});
    console.log(`ASSERT release-recipe target=${targetKey} native=${config.buildType} cross=${config.crossBuildType}`);
    assert.equal(config.buildType, 'release');
    assert.equal(config.crossBuildType, 'release');
  }
});

test('final compiler release options request portable stripping', () => {
  const release = compilerBuildTypeToml(toml, 'release');
  console.log('ASSERT final-compiler-release-options');
  assert.match(release, /^  compile-option = "--strip-all"$/m);
  assert.equal(compilerBuildTypeToml(release, 'release'), release);
  // Diagnostic builds retain symbols, including when reusing a release tree.
  for (const buildType of ['debug', 'relwithdebinfo']) {
    console.log(`ASSERT final-compiler-diagnostic-options type=${buildType}`);
    assert.equal(compilerBuildTypeToml(release, buildType), toml);
    assert.equal(buildConfig({buildType}).buildType, buildType);
  }
});

test('release workflow callers and defaults do not request diagnostic builds', () => {
  const read = name => fs.readFileSync(new URL(`../../.github/workflows/${name}.yml`, import.meta.url), 'utf8');
  const release = read('release');
  assert.doesNotMatch(release, /build_type: (relwithdebinfo|debug)/);
  assert.equal((release.match(/build_type: release/g) || []).length, 4);
  const srcbuild = read('srcbuild');
  assert.doesNotMatch(srcbuild, /default: relwithdebinfo/);
  // A diagnostic selection is available only on a manual dispatch. Called
  // release workflows always select the same release recipe as Windows std.
  for (const line of srcbuild.split('\n').filter(line => line.includes('inputs.build_type'))) {
    assert.match(line, /github.event_name == 'workflow_dispatch' && inputs.build_type \|\| 'release'/);
  }
  assert.doesNotMatch(read('release-matrix'), /default: relwithdebinfo/);
});
