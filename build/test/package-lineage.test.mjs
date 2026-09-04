import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  classifyProvenanceText,
  inspectPackagedLineage,
} from '../lib/package-lineage.mjs';

const TUPLE = 'linux_x86_64_cjnative';
const STAGE2 = 'a'.repeat(40);
const STD = 'b'.repeat(40);

const digest = contents => crypto.createHash('sha256').update(contents).digest('hex');

async function write(root, relative, contents, mode) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents, mode ? {mode} : undefined);
  return file;
}

async function miniTree(kind) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), `pkg-lineage-${kind}-`));
  const stdBytes = kind === 'nightly' ? 'official-nightly-std-bytes\n' : `rebuilt-${kind}-std\n`;
  await write(root, `modules/${TUPLE}/std/std.core.a`, stdBytes);
  await write(root, `lib/${TUPLE}/libcangjie-std-core.a`, stdBytes);
  await write(root, 'tools/bin/cjpm', `cjpm\0CJTOOL-COMMIT:${STAGE2}\0`, 0o755);
  if (kind === 'stage1') {
    await write(root, 'PROVENANCE.txt', [
      `CJSTD-COMMIT:${STD} BUILT-BY:${STAGE2}`,
      'LINEAGE=stdlib-stage1',
      'BOOTSTRAP-STAGE: stage1',
      '',
    ].join('\n'));
  } else if (kind === 'nightly') {
    await write(root, 'PROVENANCE.txt', [
      'LINEAGE=official-nightly',
      'BUILT-WITH-SDK=nightly-1.3.0-alpha.20260904010027',
      '',
    ].join('\n'));
  } else {
    await write(root, 'PROVENANCE.txt', [
      `CJSTD-COMMIT:${STD} BUILT-BY:${STAGE2}`,
      'LINEAGE=final-std',
      `ARTIFACT-SHA256:`,
      `${digest(stdBytes)}  modules/${TUPLE}/std/std.core.a`,
      '',
    ].join('\n'));
  }
  return {root, stdSha: digest(stdBytes)};
}

test('feeds nightly std and turns red exactly official-std', async t => {
  const {root, stdSha} = await miniTree('nightly');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root, {officialStdShas: new Set([stdSha])});
  assert.equal(result.ok, false);
  assert.equal(result.code, 'official-std');
  assert.match(result.message, /official-std/);
  assert.equal(classifyProvenanceText(await fs.readFile(path.join(root, 'PROVENANCE.txt'), 'utf8')),
    'official-std');
  const allowed = await inspectPackagedLineage(root, {
    officialStdShas: new Set([stdSha]),
    allowNightlyStd: true,
  });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.allowedNightly, true);
});

test('feeds stage1 marker and turns red exactly bootstrap-intermediate', async t => {
  const {root} = await miniTree('stage1');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root, {officialStdShas: new Set()});
  assert.equal(result.ok, false);
  assert.equal(result.code, 'bootstrap-intermediate');
  assert.match(result.message, /bootstrap-intermediate/);
  assert.notEqual(result.code, 'official-std');
});

test('feeds final-std and stays green; official tree is not classified green', async t => {
  const final = await miniTree('final');
  const official = await miniTree('nightly');
  t.after(() => fs.rm(final.root, {recursive: true, force: true}));
  t.after(() => fs.rm(official.root, {recursive: true, force: true}));
  const green = await inspectPackagedLineage(final.root, {
    officialStdShas: new Set([official.stdSha]),
  });
  assert.equal(green.ok, true);
  assert.equal(green.code, 'ok');
  const positive = await inspectPackagedLineage(official.root, {
    officialStdShas: new Set([official.stdSha]),
  });
  assert.equal(positive.ok, false, 'official tree must not be classified green');
  assert.equal(positive.code, 'official-std');
});
