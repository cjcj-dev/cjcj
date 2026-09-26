import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {installStage3Compiler} from '../../ci/srcbuild/lib/compose-install.mjs';
import {fileSha256} from '../../ci/srcbuild/lib/final-compiler.mjs';

test('compose replaces stage2 wrapper with recorded stage3 product', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'compose-install-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'bin', 'cjc'), '#!/bin/sh\nexec stage2-wrapper\n', {mode: 0o755});
  await fs.writeFile(path.join(sdk, 'bin', 'cjcj-stage2'), 'stage2 elf fixture', {mode: 0o755});
  const product = path.join(root, 'cjc@cjcj');
  await fs.writeFile(product, 'stage3 final compiler fixture', {mode: 0o755});
  const lineage = {compilerSha256: await fileSha256(product), parentSha256: 'b'.repeat(64), stage: 'stage3'};
  const installed = await installStage3Compiler({sdk, product, lineage});
  console.log('COMPOSE_STAGE3_ORIGIN_ASSERT_REACHED');
  assert.equal(installed, path.join(sdk, 'bin', 'cjc'));
  assert.equal(await fs.readFile(installed, 'utf8'), 'stage3 final compiler fixture');
  assert.equal(await fileSha256(installed), lineage.compilerSha256);
  assert.equal(await fs.readlink(installed), 'cjcj-stage1');
  assert.equal(await fs.readlink(path.join(sdk, 'bin', 'cjc-frontend')), 'cjcj-stage1');
  assert.equal((await fs.lstat(path.join(sdk, 'bin', 'cjcj-stage1'))).isFile(), true);
  await assert.rejects(fs.stat(path.join(sdk, 'bin', 'cjcj-stage2')), {code: 'ENOENT'});
});

test('compose rejects a product that is not the recorded stage3 compiler', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'compose-mismatch-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  const product = path.join(root, 'cjc@cjcj');
  await fs.writeFile(product, 'wrong compiler');
  await assert.rejects(
    installStage3Compiler({
      sdk, product, lineage: {compilerSha256: crypto.createHash('sha256').update('stage3').digest('hex')},
    }),
    /compose stage3 producer mismatch/,
  );
  console.log('COMPOSE_STAGE3_MISMATCH_ASSERT_REACHED');
});
