import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const entry = path.resolve(import.meta.dirname, '../steps/qualify-tuple-oracle.mjs');

test('explicit tuple oracle entry rejects absent official identity before comparisons', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'tuple-oracle-entry-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const env = {...process.env, CJCJ_SRCBUILD_TARGET: 'linux-x64'};
  for (const key of ['CJCJ_SRCBUILD_BOOTSTRAP_SDK', 'CJCJ_TOOLCHAIN', 'CJCJ_HOST_CJC_SHA256',
    'CJCJ_HOST_RUNTIME_SHA256', 'CJCJ_HOST_BOUNDSCHECK_SHA256', 'CJCJ_BOOTSTRAP_HOST_LLVM_SHA256']) delete env[key];
  const result = spawnSync('npx', ['--yes', 'zx@8', entry, path.join(root, 'sdk'), path.join(root, 'result')],
    {env, encoding: 'utf8', timeout: 120000});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /OFFICIAL_ORACLE_PIN_REQUIRED/);
  assert.doesNotMatch(result.stdout, /TUPLE_ORACLE_QUALIFIED|\[tuple-oracle\] phase=/);
  console.log('TUPLE_ORACLE_PIN_REJECTION_OBSERVED rc=1');
});
