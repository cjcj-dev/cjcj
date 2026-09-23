import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fixture} from './prepare_bootstrap_fixture.mjs';

test('workflow acquisition coordinates come from the runner identity declaration', () => fixture(({env}) => {
  const result = spawnSync(process.execPath, [new URL('./host_llvm.mjs', import.meta.url).pathname, 'env'], {env, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, 'HOST_LLVM_RUN_ID=123\nHOST_LLVM_ARTIFACT_ID=456\n');
  console.log('ASSERT host workflow acquisition coordinates executed');
}));

test('prepare exports a verified physical host artifact copy and declared digest', () => fixture(({env, so, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  const output = /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(result.stdout)?.[1];
  assert.ok(output, result.stdout);
  const source = path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'libLLVM-15.so');
  assert.notEqual(output, source);
  assert.notEqual(output, so);
  assert.ok(fs.lstatSync(output).isFile());
  assert.notEqual(fs.statSync(output).ino, fs.statSync(source).ino);
  assert.deepEqual(fs.readFileSync(output), fs.readFileSync(source));
  const sha = JSON.parse(fs.readFileSync(path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'manifest.json'))).sha256;
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=${sha}\n`));
  console.log('ASSERT host artifact bytes and declared digest exported');
}));

test('prepare rejects a one-digit host identity cut before exporting environment', () => fixture(({env, run}) => {
  const identities = fs.readFileSync(env.STAGE1_HOST_IDENTITIES, 'utf8');
  fs.writeFileSync(env.STAGE1_HOST_IDENTITIES, identities.replace(/(libLLVM-15.so )([a-f0-9])/, (_, prefix, digit) => prefix + (digit === '0' ? '1' : '0')));
  const result = run();
  assert.match(result.stderr, /HOST_LLVM_SHA256_MISMATCH expected=[a-f0-9]{64} actual=[a-f0-9]{64}/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=/m);
  console.log('ASSERT host one-digit pin mismatch executed');
}));

test('prepare rejects altered host bytes despite an available nightly fallback', () => fixture(({env, run}) => {
  fs.writeFileSync(path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'libLLVM-15.so'), 'nightly original');
  const result = run();
  assert.match(result.stderr, /HOST_LLVM_SHA256_MISMATCH/);
  assert.notEqual(result.status, 0);
}));

for (const field of ['source_sha', 'run_id', 'run_attempt', 'producer_sha', 'platform', 'sha256']) {
  test(`prepare binds host provenance ${field}`, () => fixture(({env, run}) => {
    const file = path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'manifest.json');
    const manifest = JSON.parse(fs.readFileSync(file));
    manifest[field] = 'different';
    fs.writeFileSync(file, JSON.stringify(manifest));
    const result = run();
    assert.match(result.stderr, new RegExp(`HOST_LLVM_PROVENANCE_MISMATCH field=${field}`));
    assert.notEqual(result.status, 0);
  }));
}

test('missing host artifact cannot select the available nightly library', () => fixture(({env, run}) => {
  delete env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
  const result = run();
  assert.match(result.stderr, /HOST_LLVM_ARTIFACT_MISSING/);
  assert.notEqual(result.status, 0);
}));

// Exercise the same target value that srcbuild.yml puts into every CLI step.
for (const target of ['linux-aarch64', 'darwin-arm64', 'darwin-x64']) {
  test(`source ${target} resolves its native SDK without the x64 download`, () => fixture(({env, so, run}) => {
    env.CJCJ_SRCBUILD_TARGET = target;
    delete env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
    delete env.CJCJ_BOOTSTRAP_HOST_LLVM_SO;
    const file = path.join(env.CJCJ_SRCBUILD_HOST_SDK, 'third_party/llvm/lib',
      target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so');
    fs.mkdirSync(path.dirname(file), {recursive: true});
    const bytes = `${target} native library`;
    fs.writeFileSync(file, bytes);
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`^CJCJ_BOOTSTRAP_HOST_LLVM_SO=${file}$`, 'm'));
    const declared = crypto.createHash('sha256').update(bytes).digest('hex');
    assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=${declared}\n`));
    console.log(`ASSERT target=${target} native SDK path and digest exported`);
  }));

  test(`source ${target} cannot consume an accidentally supplied x64 artifact`, () => fixture(({env, so, run}) => {
    env.CJCJ_SRCBUILD_TARGET = target;
    fs.writeFileSync(path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'libLLVM-15.so'), 'foreign x64 library');
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_LLVM_SO=${so}\n`));
    console.log(`ASSERT target=${target} ignores foreign x64 input`);
  }));
}

test('workflow supplies the target to the shared CLI and downloads host LLVM only for x64', () => {
  const workflow = fs.readFileSync(new URL('../../.github/workflows/srcbuild.yml', import.meta.url), 'utf8');
  assert.ok(workflow.includes('CJCJ_SRCBUILD_TARGET: ${{ matrix.target }}'));
  for (const name of ['Load immutable bootstrap host LLVM provenance', 'Download pinned bootstrap host LLVM']) {
    const step = workflow.split(`- name: ${name}\n`)[1]?.split('\n      - name:')[0];
    assert.ok(step, name);
    assert.match(step, /if: matrix.target == 'linux-x64'/);
  }
  assert.ok(workflow.includes('node ci/release/prepare_bootstrap_inputs.mjs'));
});
