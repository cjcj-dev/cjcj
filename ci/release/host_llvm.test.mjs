import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fixture} from './prepare_bootstrap_fixture.mjs';

for (const downloadFails of [false, true]) {
  test(`shared pinned artifact transport ${downloadFails ? 'fails closed' : 'feeds shared verification'}`, () => fixture(({env, run}) => {
    const root = path.dirname(env.STAGE1_HOST_IDENTITIES);
    const archive = path.join(root, 'artifact.zip');
    const zipped = spawnSync('python3', ['-c', 'import pathlib,sys,zipfile\nwith zipfile.ZipFile(sys.argv[1], "w") as archive:\n for file in pathlib.Path(sys.argv[2]).iterdir(): archive.write(file, file.name)', archive, env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT], {encoding: 'utf8'});
    assert.equal(zipped.status, 0, zipped.stderr);
    const bin = path.join(root, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'gh'), '#!/bin/sh\nprintf "%s\\n" "$*" > "$TRANSPORT_ARGS"\n'
      + (downloadFails ? 'exit 23\n' : 'cat "$TRANSPORT_ARCHIVE"\n'), {mode: 0o755});
    env.PATH = `${bin}:${env.PATH}`;
    env.TRANSPORT_ARCHIVE = archive;
    env.TRANSPORT_ARGS = path.join(root, 'transport.args');
    env.CJCJ_BOOTSTRAP_HOST_LLVM_WORK = path.join(root, 'work');
    delete env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
    const output = path.join(root, 'host-result.json');
    const result = run(['--shell-output', output]);
    assert.equal(fs.readFileSync(env.TRANSPORT_ARGS, 'utf8'), 'api repos/cjcj-dev/cjcj/actions/artifacts/456/zip\n');
    if (downloadFails) {
      assert.equal(result.status, 1);
      assert.match(result.stderr, /ARTIFACT_DOWNLOAD_FAILED artifact=456 status=23/);
      assert.equal(fs.existsSync(output), false);
    } else {
      assert.equal(result.status, 0, result.stderr);
      const actual = {file: /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(result.stdout)?.[1],
        sha256: /^CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=(.+)$/m.exec(result.stdout)?.[1]};
      assert.equal(crypto.createHash('sha256').update(fs.readFileSync(actual.file)).digest('hex'), actual.sha256);
      assert.match(result.stdout, /HOST_LLVM_VERIFIED run=123 artifact=456/);
    }
    console.log(`HOST_LLVM_TRANSPORT_ASSERT failure=${downloadFails} rc=${result.status}`);
  }));
}

test('shell and GHA preparation export the same host artifact digest', () => fixture(({env, run}) => {
  const output = path.join(path.dirname(env.STAGE1_HOST_IDENTITIES), 'kkk2-host.json');
  const kkk2 = run(['--shell-output', output]);
  const gha = run();
  const actual = {file: /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(kkk2.stdout)?.[1],
    sha256: /^CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=(.+)$/m.exec(kkk2.stdout)?.[1]};
  const ghaFile = /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(gha.stdout)?.[1];
  const ghaSha = /^CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=(.+)$/m.exec(gha.stdout)?.[1];
  const digest = file => file && crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const observed = {kkk2: kkk2.status, gha: gha.status, samePin: actual.sha256 === ghaSha,
    sameBytes: digest(actual.file) === digest(ghaFile)};
  console.log(`HOST_LLVM_TWO_ENTRIES ${JSON.stringify(observed)} kkk2=${actual.file} gha=${ghaFile}`);
  assert.deepEqual(observed, {kkk2: 0, gha: 0, samePin: true, sameBytes: true});
}));

test('shell and GHA reject the same host provenance digest change', () => fixture(({env, run}) => {
  const output = path.join(path.dirname(env.STAGE1_HOST_IDENTITIES), 'kkk2-host.json');
  const manifestFile = path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestFile));
  manifest.sha256 = '0'.repeat(64);
  fs.writeFileSync(manifestFile, JSON.stringify(manifest));
  const kkk2 = run(['--shell-output', output]);
  const gha = run();
  const marker = 'HOST_LLVM_PROVENANCE_MISMATCH field=sha256';
  const observed = {kkk2: kkk2.status, gha: gha.status, kkk2Marker: kkk2.stderr.includes(marker),
    ghaMarker: gha.stderr.includes(marker), exported: fs.existsSync(output)};
  console.log(`HOST_LLVM_TWO_REJECTIONS ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {kkk2: 1, gha: 1, kkk2Marker: true, ghaMarker: true, exported: false});
}));

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

// Enter the real preparation CLI at each source-workflow target boundary.
for (const target of ['linux-aarch64', 'darwin-arm64', 'darwin-x64']) {
  const library = target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so';
  test(`source ${target} exports pinned artifact bytes and digest`, () => fixture(({env, run}) => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    const output = /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(result.stdout)?.[1];
    assert.ok(output, result.stdout);
    const source = path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, library);
    assert.notEqual(output, source);
    assert.notEqual(output, env.CJCJ_BOOTSTRAP_HOST_LLVM_SO);
    assert.ok(fs.lstatSync(output).isFile());
    assert.deepEqual(fs.readFileSync(output), fs.readFileSync(source));
    const sha = JSON.parse(fs.readFileSync(path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'manifest.json'))).sha256;
    assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_LLVM_SHA256=${sha}\n`));
    console.log(`ASSERT target=${target} pinned host bytes and digest exported`);
  }, target));

  test(`source ${target} rejects one-digit digest change`, () => fixture(({env, run}) => {
    const file = env.STAGE1_HOST_IDENTITIES;
    fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace(target === 'linux-aarch64' ? /(linux_aarch64 libLLVM-15.so )([a-f0-9])/ : /("sha256":")([a-f0-9])/, (_, prefix, digit) => prefix + (digit === '0' ? '1' : '0')));
    const result = run();
    assert.match(result.stderr, /HOST_LLVM_SHA256_MISMATCH expected=/);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=/m);
    console.log(`ASSERT target=${target} digest rejection executed`);
  }, target));

  for (const field of ['source_sha', 'run_id', 'run_attempt', 'producer_sha', 'platform', 'sha256']) {
    test(`source ${target} rejects provenance ${field}`, () => fixture(({env, run}) => {
      const file = path.join(env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'manifest.json');
      const manifest = JSON.parse(fs.readFileSync(file));
      manifest[field] = 'different';
      fs.writeFileSync(file, JSON.stringify(manifest));
      const result = run();
      assert.match(result.stderr, new RegExp(`HOST_LLVM_PROVENANCE_MISMATCH field=${field}`));
      assert.notEqual(result.status, 0);
      assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=/m);
      console.log(`ASSERT target=${target} provenance ${field} rejection executed`);
    }, target));
  }

  test(`source ${target} cannot fall back to SDK without artifact`, () => fixture(({env, run}) => {
    delete env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
    const result = run();
    assert.match(result.stderr, /HOST_LLVM_ARTIFACT_MISSING/);
    assert.notEqual(result.status, 0);
  }, target));
}

test('workflow supplies the target and downloads pinned host LLVM for every cell', () => {
  const workflow = fs.readFileSync(new URL('../../.github/workflows/srcbuild-target.yml', import.meta.url), 'utf8');
  assert.ok(workflow.includes('CJCJ_SRCBUILD_TARGET: ${{ matrix.target }}'));
  for (const name of ['Load immutable bootstrap host LLVM provenance', 'Download pinned bootstrap host LLVM']) {
    const step = workflow.split(`- name: ${name}\n`)[1]?.split('\n      - name:')[0];
    assert.ok(step, name);
    assert.doesNotMatch(step, /if:/);
  }
  assert.ok(workflow.includes('node ci/release/prepare_bootstrap_inputs.mjs'));
});

for (const target of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64']) {
  test(`producer ${target} records actual digest and source identity for consumer`, () => fixture(({env, run}) => {
    const root = env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
    const expected = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
    fs.writeFileSync(path.join(root, 'demangled-symbols.txt'), '');
    const producer = spawnSync('python3', [new URL('./record_host_llvm.py', import.meta.url).pathname, root], {
      env: {...env, HOST_LLVM_SOURCE_SHA: expected.source_sha, HOST_LLVM_PLATFORM: expected.platform,
        HOST_LLVM_LIBRARY: target.startsWith('darwin-') ? 'libLLVM.dylib' : 'libLLVM-15.so',
        GITHUB_RUN_ID: expected.run_id, GITHUB_RUN_ATTEMPT: expected.run_attempt, GITHUB_SHA: expected.producer_sha}, encoding: 'utf8'});
    assert.equal(producer.status, 0, producer.stderr);
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    const output = /^CJCJ_BOOTSTRAP_HOST_LLVM_SO=(.+)$/m.exec(result.stdout)?.[1];
    assert.ok(output, result.stdout);
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'), expected.sha256);
    console.log(`ASSERT producer target=${target} manifest accepted and bytes exported`);
  }, target));
}
