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
