import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  TOOLCHAIN_IDENTITY,
  TOOLCHAIN_IDENTITY_ARTIFACTS,
  TOOLCHAIN_IDENTITY_FORMAT,
  stampBinaryLineage,
  writeToolchainIdentity,
} from '../lib/toolchain-identity.mjs';

const COMMITS = Object.freeze({
  runtime: '1'.repeat(40),
  cjc: '2'.repeat(40),
  cjpm: '3'.repeat(40),
  hle: '5'.repeat(40),
  llc: '4'.repeat(40),
  opt: '4'.repeat(40),
});

const PATHS = Object.freeze({
  runtime: 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
  cjc: 'bin/cjc',
  cjpm: 'tools/bin/cjpm',
  hle: 'tools/bin/hle',
  llc: 'third_party/llvm/bin/llc',
  opt: 'third_party/llvm/bin/opt',
});

async function fixture({includeHle = true} = {}) {
  const stage = await fs.mkdtemp(path.join(os.tmpdir(), 'toolchain-identity-'));
  const releaseRows = [];
  for (const artifact of TOOLCHAIN_IDENTITY_ARTIFACTS) {
    if (artifact.optional && !includeHle) continue;
    const relative = PATHS[artifact.name];
    const file = path.join(stage, relative);
    const stamp = `${artifact.prefix}:${COMMITS[artifact.name]}`;
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, `${artifact.name}\0${stamp}\0`);
    const bytes = await fs.readFile(file);
    const digest = (await import('node:crypto')).createHash('sha256').update(bytes).digest('hex');
    releaseRows.push({
      component: artifact.component,
      source: {
        status: 'resolved',
        repository: `https://example.invalid/${artifact.component}.git`,
        commit: COMMITS[artifact.name],
      },
      artifact: {path: relative, sha256: digest},
      embedded_stamp: stamp,
    });
  }
  return {stage, releaseRows};
}

test('identity producer binds final artifacts to clean repository commits', async t => {
  const value = await fixture();
  t.after(() => fs.rm(value.stage, {recursive: true, force: true}));
  const result = await writeToolchainIdentity(value);
  assert.equal(result.artifacts.length, 6);
  const text = await fs.readFile(path.join(value.stage, TOOLCHAIN_IDENTITY), 'utf8');
  assert.match(text, new RegExp(`^format\\t${TOOLCHAIN_IDENTITY_FORMAT}$`, 'm'));
  assert.match(text, /^sdk_root\t\.$/m);
  assert.match(text, /^artifact_count\t6$/m);
  for (const artifact of TOOLCHAIN_IDENTITY_ARTIFACTS) {
    assert.match(text, new RegExp(`^${artifact.name}_path\\t${PATHS[artifact.name].replaceAll('.', '\\.')}$$`, 'm'));
    assert.match(text, new RegExp(`^${artifact.name}_repository\\thttps://example\\.invalid/`, 'm'));
    assert.match(text, new RegExp(`^${artifact.name}_commit\\t${COMMITS[artifact.name]}$`, 'm'));
    assert.match(text, new RegExp(`^${artifact.name}_dirty\\tno$`, 'm'));
    assert.match(text, new RegExp(`^${artifact.name}_lineage\\t${artifact.prefix}:${COMMITS[artifact.name]}$`, 'm'));
  }
});

test('identity producer rejects an unstamped artifact instead of writing UNKNOWN as PASS', async t => {
  const value = await fixture();
  t.after(() => fs.rm(value.stage, {recursive: true, force: true}));
  await fs.writeFile(path.join(value.stage, PATHS.cjpm), 'cjpm-without-lineage');
  const row = value.releaseRows.find(item => item.component === 'cjpm');
  const bytes = await fs.readFile(path.join(value.stage, PATHS.cjpm));
  row.artifact.sha256 = (await import('node:crypto')).createHash('sha256').update(bytes).digest('hex');
  row.embedded_stamp = 'no-stamp';
  await assert.rejects(
    writeToolchainIdentity(value),
    /cjpm CJTOOL-COMMIT occurrence must be exactly 1; actual count=0/,
  );
  await assert.rejects(fs.stat(path.join(value.stage, TOOLCHAIN_IDENTITY)), {code: 'ENOENT'});
});

test('identity producer omits the optional inherited hle record', async t => {
  const value = await fixture({includeHle: false});
  t.after(() => fs.rm(value.stage, {recursive: true, force: true}));
  const result = await writeToolchainIdentity(value);
  assert.equal(result.artifacts.length, 5);
  const text = await fs.readFile(path.join(value.stage, TOOLCHAIN_IDENTITY), 'utf8');
  assert.match(text, /^artifact_count\t5$/m);
  assert.doesNotMatch(text, /^hle_path\t/m);
});

test('identity producer rejects a dirty embedded lineage stamp', async t => {
  const value = await fixture();
  t.after(() => fs.rm(value.stage, {recursive: true, force: true}));
  const dirtyStamp = `CJLLVM-COMMIT:${COMMITS.llc}-dirty`;
  const file = path.join(value.stage, PATHS.llc);
  await fs.writeFile(file, `llc\0${dirtyStamp}\0`);
  const bytes = await fs.readFile(file);
  const row = value.releaseRows.find(item => item.component === 'llvm-llc');
  row.artifact.sha256 = (await import('node:crypto')).createHash('sha256').update(bytes).digest('hex');
  row.embedded_stamp = dirtyStamp;
  await assert.rejects(writeToolchainIdentity(value), /llc CJLLVM-COMMIT must not be dirty/);
});

test('post-link lineage stamping is idempotent and rejects conflicting source identity', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'binary-lineage-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const file = path.join(root, 'cjpm');
  await fs.writeFile(file, 'fixture executable');
  const commit = '5'.repeat(40);
  const first = await stampBinaryLineage({file, prefix: 'CJTOOL-COMMIT', commit});
  assert.equal(first.changed, true);
  assert.equal(first.stamp, `CJTOOL-COMMIT:${commit}`);
  const second = await stampBinaryLineage({file, prefix: 'CJTOOL-COMMIT', commit});
  assert.equal(second.changed, false);
  assert.equal(second.sha256, first.sha256);
  assert.equal((await fs.readFile(file, 'latin1')).split('CJTOOL-COMMIT:').length - 1, 1);
  await assert.rejects(
    stampBinaryLineage({file, prefix: 'CJTOOL-COMMIT', commit: '6'.repeat(40)}),
    /CJTOOL-COMMIT conflicts with source commit/,
  );
  await assert.rejects(
    stampBinaryLineage({file, prefix: 'CJTOOL-COMMIT', commit: `${commit}-dirty`}),
    /must be a clean 40-character commit SHA/,
  );
});
