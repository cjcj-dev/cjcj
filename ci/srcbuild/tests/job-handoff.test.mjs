import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import test from 'node:test';

const product = path.resolve(import.meta.dirname, '../job-handoff.mjs');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
async function fixture(t) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'source-handoff-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const root = path.join(dir, 'workspace');
  for (const entry of ['.srcbuild/workspace/bootstrap-work', 'packages', 'runtime_shim']) {
    await fs.mkdir(path.join(root, entry), {recursive: true});
  }
  const binary = path.join(root, '.srcbuild/workspace/bootstrap-work/cjcj-stage2');
  await fs.writeFile(binary, '#!/bin/sh\nprintf "handoff-compiler-result\\n"\n', {mode: 0o755});
  await fs.symlink('cjcj-stage2', path.join(path.dirname(binary), 'cjc'));
  await fs.writeFile(path.join(root, 'runtime_shim/config.o'), 'producer-object-bytes');
  await fs.writeFile(path.join(root, 'cjpm.toml'), 'fixture');
  const archive = path.join(dir, 'artifact');
  const env = {...process.env, GITHUB_WORKSPACE: root, GITHUB_SHA: '1'.repeat(40),
    GITHUB_RUN_ID: '702', CJCJ_SRCBUILD_TARGET: 'linux-x64',
    GITHUB_ENV: path.join(dir, 'env'), GITHUB_PATH: path.join(dir, 'path'),
    CANGJIE_HOME: path.join(root, '.srcbuild/host-sdk'), SOURCE_SDK_VERSION: '0.0.2',
    CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256: '2'.repeat(64)};
  const run = (mode, overrides = {}) => {
    const r = spawnSync(process.execPath, [product, mode, 'stage1-compiler', archive],
      {env: {...env, ...overrides}, encoding: 'utf8'});
    return {rc: r.status, output: `${r.stdout}${r.stderr}`};
  };
  const packed = run('pack');
  assert.equal(packed.rc, 0, packed.output);
  return {dir, root, binary, archive, env, run};
}

test('producer archive restores executable compiler, symlink, shim and environment on a fresh job', async t => {
  const f = await fixture(t);
  const manifest = JSON.parse(await fs.readFile(path.join(f.archive, 'manifest.json')));
  assert.equal(manifest.sha256, digest(await fs.readFile(path.join(f.archive, 'payload.tar'))));
  await fs.rm(f.root, {recursive: true});
  await fs.mkdir(path.join(f.root, 'runtime_shim'), {recursive: true});
  await fs.writeFile(path.join(f.root, 'runtime_shim/config.o'), 'unrestored');
  const restored = f.run('restore');
  assert.equal(restored.rc, 0, restored.output);
  assert.match(restored.output, /BOOTSTRAP_VERIFIED handoff\/stage1-compiler [a-f0-9]{64}/);
  const result = spawnSync(path.join(path.dirname(f.binary), 'cjc'), [], {encoding: 'utf8'});
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'handoff-compiler-result\n');
  assert.equal(await fs.readFile(path.join(f.root, 'runtime_shim/config.o'), 'utf8'), 'producer-object-bytes');
  assert.equal(await fs.readlink(path.join(path.dirname(f.binary), 'cjc')), 'cjcj-stage2');
  assert.match(await fs.readFile(f.env.GITHUB_ENV, 'utf8'), /SOURCE_SDK_VERSION=0.0.2/);
  console.log('HANDOFF_ASSERT executable-output=handoff-compiler-result shim=producer-object-bytes');
});

test('consumer rejects corrupted payload before exporting any environment', async t => {
  const f = await fixture(t);
  // Appending bytes leaves tar readable. Only the product SHA check rejects it.
  await fs.appendFile(path.join(f.archive, 'payload.tar'), 'changed-after-publication');
  const result = f.run('restore');
  assert.notEqual(result.rc, 0, 'target assertion: changed producer bytes must be rejected');
  assert.match(result.output, /handoff payload SHA256 mismatch/);
  await assert.rejects(fs.stat(f.env.GITHUB_ENV), {code: 'ENOENT'});
  console.log('HANDOFF_ASSERT corrupt-payload=rejected-before-environment');
});

for (const [key, value] of [['GITHUB_SHA', '3'.repeat(40)], ['GITHUB_RUN_ID', '703'],
  ['CJCJ_SRCBUILD_TARGET', 'darwin-x64']]) {
  test(`consumer rejects a different ${key}`, async t => {
    const f = await fixture(t);
    const result = f.run('restore', {[key]: value});
    assert.notEqual(result.rc, 0);
    assert.match(result.output, /handoff identity mismatch/);
    await assert.rejects(fs.stat(f.env.GITHUB_ENV), {code: 'ENOENT'});
  });
}

test('consumer rejects wrong phase and does not accept a missing artifact', async t => {
  const f = await fixture(t);
  const file = path.join(f.archive, 'manifest.json');
  const record = JSON.parse(await fs.readFile(file));
  record.phase = 'stage0';
  await fs.writeFile(file, JSON.stringify(record));
  assert.match(f.run('restore').output, /handoff identity mismatch: phase/);
  await fs.rm(file);
  assert.notEqual(f.run('restore').rc, 0);
});
