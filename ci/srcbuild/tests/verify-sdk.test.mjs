import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../../..');
const entry = path.join(root, 'ci/srcbuild/steps/verify.mjs');
const target = {
  'linux/x64': 'linux-x64', 'linux/arm64': 'linux-aarch64',
  'darwin/x64': 'mac-x64', 'darwin/arm64': 'mac-aarch64',
}[`${process.platform}/${process.arch}`];

test('bootstrap SDK verification retains exactly the SDK-owned phases', async () => {
  const source = await fs.readFile(entry, 'utf8');
  assert.deepEqual([...source.matchAll(/await phase\('([^']+)'/g)].map(match => match[1]),
    ['lineage', 'smoke', 'selfcheck', 'selfdet']);
});

async function runEntry(t, {compiler = true} = {}) {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'verify-sdk-contract-'));
  t.after(() => fs.rm(work, {recursive: true, force: true}));
  const sdk = path.join(work, 'sdk');
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  // An intentionally rejected SDK lets the real lineage phase expose its
  // result without running any compiler. There is no source compiler tree.
  await fs.writeFile(path.join(sdk, 'PROVENANCE.txt'), 'LINEAGE: stdlib-stage1\n');
  if (compiler) {
    await fs.writeFile(path.join(sdk, 'bin/cjc'), '#!/bin/sh\necho UNEXPECTED_COMPILER_EXECUTION >&2\nexit 93\n', {mode: 0o755});
  }
  const env = {...process.env, CANGJIE_WORKSPACE: work, CJCJ_SRCBUILD_TARGET: target,
    RUNNER_TEMP: work, TMPDIR: work, CJCJ_VERIFY_NO_FAIL_FAST: '0'};
  delete env.CJCJ_ALLOW_NIGHTLY_STD;
  const result = spawnSync('npx', ['--yes', 'zx@8', entry, sdk], {
    cwd: root, env, encoding: 'utf8', timeout: 120_000,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null, result.stderr);
  return {...result, output: result.stdout + result.stderr};
}

test('verify reaches the SDK lineage verdict without a source C++ oracle', {skip: !target}, async t => {
  const result = await runEntry(t);
  assert.equal(result.status, 1, result.output);
  // This is the target assertion: the actual entry must reach and propagate
  // the SDK lineage result, rather than fail at an orphaned prerequisite.
  assert.match(result.output, /bootstrap-intermediate: std provenance names stdlib-stage1/);
  assert.doesNotMatch(result.output, /UNEXPECTED_COMPILER_EXECUTION/);
  console.log('VERIFY_SDK_LINEAGE_OBSERVED exit=1 source-oracle=absent');
});

test('verify still rejects a missing deployed compiler before SDK phases', {skip: !target}, async t => {
  const result = await runEntry(t, {compiler: false});
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /test -x .*sdk\/bin\/cjc/);
  assert.doesNotMatch(result.output, /bootstrap-intermediate: std provenance/);
});
