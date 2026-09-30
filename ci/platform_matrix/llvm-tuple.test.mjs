import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import zlib from 'node:zlib';
import {activateLlvmTuple} from './llvm-tuple.mjs';

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

test('platform build invokes the tuple activation entry', async () => {
  const source = await fs.readFile(new URL('./build_cjcj.mjs', import.meta.url), 'utf8');
  assert.match(source, /import \{activateLlvmTuple\} from '\.\/llvm-tuple\.mjs'/);
  assert.match(source, /await activateLlvmTuple\(fixedTools, \{sdkToolPath, manifest\}\)/);
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
