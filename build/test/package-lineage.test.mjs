import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  classifyProvenanceText,
  collectContentFindings,
  inspectPackagedLineage,
  listPackagedArtifacts,
  pinnedOfficialSdkRoot,
} from '../lib/package-lineage.mjs';

const TUPLE = 'linux_x86_64_cjnative';
const STAGE2 = 'a'.repeat(40);
const STD = 'b'.repeat(40);
const DYE = `rebuilt-final\0CJCJ-COMMIT:${STAGE2}\0g_cjStoreBadMask\0CJRT-COMMIT:${STD}\0`;

const digest = contents => crypto.createHash('sha256').update(contents).digest('hex');

async function write(root, relative, contents, mode) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents, mode ? {mode} : undefined);
  return file;
}

async function miniTree(kind) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), `pkg-lineage-${kind}-`));
  const stdBytes = kind === 'nightly' || kind === 'forge'
    ? 'official-nightly-std-bytes\n'
    : DYE;
  await write(root, `modules/${TUPLE}/std/std.core.a`, stdBytes);
  await write(root, `lib/${TUPLE}/libcangjie-std-core.a`, stdBytes);
  await write(root, `runtime/lib/${TUPLE}/libcangjie-runtime.so`, stdBytes);
  const toolBody = kind === 'final'
    ? `cjpm\0CJTOOL-COMMIT:${STAGE2}\0g_cjStoreBadMask\0`
    : `cjpm\0CJTOOL-COMMIT:${STAGE2}\0`;
  await write(root, 'tools/bin/cjpm', toolBody, 0o755);
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

async function copyOfficialStdModules(dest) {
  const official = await pinnedOfficialSdkRoot();
  const srcModules = path.join(official, 'modules');
  await fs.cp(srcModules, path.join(dest, 'modules'), {recursive: true});
}

test('feeds nightly std and turns red exactly official-std', async t => {
  const {root} = await miniTree('nightly');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'official-std');
  assert.match(result.message, /official-std/);
  assert.equal(classifyProvenanceText(await fs.readFile(path.join(root, 'PROVENANCE.txt'), 'utf8')),
    'official-std');
  const allowed = await inspectPackagedLineage(root, {allowNightlyStd: true});
  assert.equal(allowed.ok, true);
  assert.equal(allowed.allowedNightly, true);
});

test('feeds stage1 marker and turns red exactly bootstrap-intermediate', async t => {
  const {root} = await miniTree('stage1');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root);
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
  const green = await inspectPackagedLineage(final.root);
  assert.equal(green.ok, true);
  assert.equal(green.code, 'ok');
  const positive = await inspectPackagedLineage(official.root);
  assert.equal(positive.ok, false, 'official tree must not be classified green');
  assert.equal(positive.code, 'official-std');
});

test('official 0904 modules/std is rejected with per-file reasons', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'pkg-lineage-0904-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await copyOfficialStdModules(root);
  const stdFiles = (await listPackagedArtifacts(root))
    .filter(file => file.includes(`${path.sep}std${path.sep}`) || file.includes('/std/'));
  assert.ok(stdFiles.length > 0, '0904 modules/std must be present');
  const result = await inspectPackagedLineage(root);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'official-std');
  const listed = new Set(result.findings.map(item => item.file));
  for (const file of stdFiles) {
    assert.ok(listed.has(file), `missing per-file reason for ${file}`);
    assert.match(result.message, new RegExp(file.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    const finding = result.findings.find(item => item.file === file);
    assert.ok(finding.reasons.some(reason => /matches official nightly sha256/.test(reason)));
  }
  const forge = await fs.mkdtemp(path.join(os.tmpdir(), 'pkg-lineage-forge-'));
  t.after(() => fs.rm(forge, {recursive: true, force: true}));
  await copyOfficialStdModules(forge);
  await write(forge, 'PROVENANCE.txt', [
    `CJSTD-COMMIT:${STD} BUILT-BY:${STAGE2}`,
    'LINEAGE=final-std',
    '',
  ].join('\n'));
  await write(forge, 'tools/bin/cjpm', `cjpm\0CJTOOL-COMMIT:${STAGE2}\0`, 0o755);
  const forged = await inspectPackagedLineage(forge);
  assert.equal(forged.ok, false);
  assert.equal(forged.code, 'official-std');
  assert.ok(forged.findings.length > 0);
  assert.match(forged.message, /matches official nightly sha256/);
});

test('content findings cover lib runtime modules and tools', async t => {
  const {root} = await miniTree('final');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const files = await listPackagedArtifacts(root);
  assert.ok(files.some(file => file.includes(`${path.sep}modules${path.sep}`)));
  assert.ok(files.some(file => file.includes(`${path.sep}lib${path.sep}`)));
  assert.ok(files.some(file => file.includes(`${path.sep}runtime${path.sep}lib${path.sep}`)));
  assert.ok(files.some(file => file.endsWith(`${path.sep}tools${path.sep}bin${path.sep}cjpm`)));
  const findings = await collectContentFindings(root, new Set());
  assert.equal(findings.length, 0);
});
