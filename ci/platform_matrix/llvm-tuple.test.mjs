import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import zlib from 'node:zlib';
import {activateLlvmTuple, verifyInstalledLlvmTuple} from './llvm-tuple.mjs';

const digest = payload => crypto.createHash('sha256').update(payload).digest('hex');
const testRoot = process.env.RELEASE_EVIDENCE_TEST_ROOT || os.tmpdir();

async function fixture(context, name, payload, version) {
  await fs.mkdir(testRoot, {recursive: true});
  const root = await fs.mkdtemp(path.join(testRoot, 'llvm-tuple-'));
  context.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, name);
  const original = Buffer.from('original SDK payload');
  await fs.writeFile(sdk, original);
  const archive = path.join(root, 'payload.gz');
  await fs.writeFile(archive, zlib.gzipSync(payload));
  const tool = {name, archive, manifestKey: 'TOOL_SHA256', versionKey: 'TOOL_VERSION'};
  const manifest = new Map([['TOOL_SHA256', digest(payload)], ['TOOL_VERSION', version]]);
  return {root, sdk, original, tool, manifest, options: {manifest, sdkToolPath: async () => sdk}};
}

async function resultOf(fixtureData) {
  try {
    await activateLlvmTuple([fixtureData.tool], fixtureData.options);
    return {error: undefined, payload: await fs.readFile(fixtureData.sdk)};
  } catch (error) {
    return {error, payload: await fs.readFile(fixtureData.sdk)};
  }
}

test('platform build verifies native installation instead of patching the official host', async () => {
  const source = await fs.readFile(new URL('./build_cjcj.mjs', import.meta.url), 'utf8');
  assert.match(source, /import \{verifyInstalledLlvmTuple\} from '\.\/llvm-tuple\.mjs'/);
  assert.match(source, /await verifyInstalledLlvmTuple\(fixedTools, \{sdk: cangjieHome, sdkToolPath, manifest\}\)/);
  assert.doesNotMatch(source, /await activateLlvmTuple/);
});

test('tuple artifact authentication rejects changed payload before replacing SDK', async context => {
  const data = await fixture(context, 'llc', Buffer.from('invalid payload'), 'LLVM version fixture');
  data.manifest.set('TOOL_SHA256', '0'.repeat(64));
  const result = await resultOf(data);
  assert.match(result.error?.message || '', /artifact sha mismatch/);
  assert.deepEqual(result.payload, data.original);
});

test('tuple version authentication rejects mismatch before replacing SDK', async context => {
  const payload = Buffer.from('#!/usr/bin/env node\nconsole.log("LLVM version actual");\n');
  const data = await fixture(context, 'llc', payload, 'LLVM version expected');
  const result = await resultOf(data);
  assert.match(result.error?.message || '', /tuple LLVM tool version mismatch/);
  assert.deepEqual(result.payload, data.original);
});

test('tuple rejects unsuccessful version probe before replacing SDK', async context => {
  const payload = Buffer.from('#!/usr/bin/env node\nconsole.log("LLVM version expected"); process.exitCode = 1;\n');
  const data = await fixture(context, 'opt', payload, 'LLVM version expected');
  const result = await resultOf(data);
  assert.match(result.error?.message || '', /tuple LLVM tool probe failed/);
  assert.deepEqual(result.payload, data.original);
});

const lldBinary = process.env.LLVM_TUPLE_TEST_LLD;
for (const name of ['llc', 'opt', 'ld.lld', 'ld64.lld', 'ld.lld.exe']) {
  test(`activation preserves staged basename ${name} without optional LLVM input`, async context => {
    const payload = Buffer.from('#!/usr/bin/env node\nconsole.log("LLVM version fixture");\n');
    const data = await fixture(context, name, payload, 'LLVM version fixture');
    const result = await resultOf(data);
    console.log(`BASENAME_ASSERT name=${name} staged=${path.basename(data.tool.tuple)} error=${result.error?.message || 'none'}`);
    assert.equal(result.error, undefined);
    assert.equal(path.basename(data.tool.tuple), name, `qualified staging preserves SDK basename: ${name}`);
    assert.equal(digest(result.payload), digest(payload));
  });
}

for (const [name, flavor] of [['ld.lld', 'gnu'], ['ld64.lld', 'darwin'], ['ld.lld.exe', 'gnu']]) {
  test(`real LLD activation preserves ${name} driver and installed payload`, {skip: !lldBinary}, async context => {
    const versionProbe = spawnSync(lldBinary, ['-flavor', flavor, '--version'], {encoding: 'utf8'});
    assert.equal(versionProbe.status, 0, versionProbe.stderr);
    const version = versionProbe.stdout.trim();
    assert.match(version, /^LLD /);
    const payload = await fs.readFile(lldBinary);
    console.log(`REAL_LLD_INPUT name=${name} sha256=${digest(payload)} version=${version}`);
    const data = await fixture(context, name, payload, version);
    const result = await resultOf(data);
    console.log(`TARGET_ASSERT name=${name} error=${result.error?.message || 'none'} installed_sha256=${digest(result.payload)}`);
    assert.equal(result.error, undefined, `driver-preserving activation: ${name}`);
    assert.equal(digest(result.payload), digest(payload), `installed qualified payload: ${name}`);
    assert.equal(path.basename(data.tool.tuple), name);
    const installedProbe = spawnSync(data.sdk, ['--version'], {encoding: 'utf8'});
    assert.equal(installedProbe.status, 0, installedProbe.stderr);
    assert.equal(installedProbe.stdout.trim(), version);
    assert.deepEqual(await fs.readFile(`${data.sdk}.orig`), data.original);
  });
}

test('installed native tuple consumes actual retained producer and preserves input bytes', async context => {
  const payload = Buffer.from('#!/usr/bin/env node\nconsole.log("LLVM version native fixture");\n');
  const data = await fixture(context, 'llc', payload, 'LLVM version native fixture');
  await fs.writeFile(data.sdk, payload, {mode: 0o755}); await fs.chmod(data.sdk, 0o755);
  const producer = path.join(data.root, 'native-llc'); await fs.writeFile(producer, payload);
  await fs.writeFile(data.sdk+'.entry', 'cjcj-sdk-entry-v1\n1\nnative-llc\nlinux\nnative-target:x64\n');
  const options = {...data.options, sdk: data.root};
  await verifyInstalledLlvmTuple([data.tool], options);
  assert.deepEqual(await fs.readFile(data.sdk), payload);
  await fs.writeFile(producer, 'different native LLVM');
  await assert.rejects(verifyInstalledLlvmTuple([data.tool], options), /producer sha mismatch/);
  assert.deepEqual(await fs.readFile(data.sdk), payload);
  await fs.writeFile(producer, payload);
  await verifyInstalledLlvmTuple([data.tool], options);
  const original = await fs.readFile(data.tool.archive);
  await fs.writeFile(data.tool.archive, zlib.gzipSync(Buffer.from('different artifact')));
  await assert.rejects(verifyInstalledLlvmTuple([data.tool], options), /artifact sha mismatch/);
  await fs.writeFile(data.tool.archive, original);
  assert.equal(await fs.stat(data.sdk+'.orig').then(() => true, () => false), false);
});
