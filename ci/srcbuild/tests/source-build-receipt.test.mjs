import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {captureBuildInputs, finishBuildReceipt, sourceIdentity} from '../lib/source-build-receipt.mjs';

async function fixture(body) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'source-receipt-'));
  try {
    const source = path.join(root, 'source');
    await fs.mkdir(source);
    const git = (...args) => execFileSync('git', ['-C', source, ...args], {stdio: 'pipe'});
    git('init');
    await fs.writeFile(path.join(source, 'module.cj'), 'main() { 0 }');
    git('add', '.');
    git('-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-m', 'fixture');
    const compiler = path.join(root, 'compiler');
    await fs.writeFile(compiler, 'compiler input');
    await body({root, source, compiler});
  } finally { await fs.rm(root, {recursive: true, force: true}); }
}

test('receipt binds real checkout, compiler input, recipe and built output', () => fixture(async ({root, source, compiler}) => {
  const captured = await captureBuildInputs({source, files: {compiler}, recipe: {command: 'build'}});
  assert.match(captured.source.commit, /^[0-9a-f]{40}$/);
  assert.match(captured.inputs.compiler, /^[0-9a-f]{64}$/);
  const core = path.join(root, 'core.a');
  await fs.writeFile(core, 'built core');
  const output = path.join(root, 'SOURCE-BUILD.json');
  const receipt = await finishBuildReceipt({source, captured, output, artifacts: {core}});
  assert.equal(receipt.inputs.compiler, captured.inputs.compiler);
  assert.equal(receipt.recipe.command, 'build');
  assert.notEqual(receipt.products.core, receipt.inputs.compiler);
  assert.deepEqual(JSON.parse(await fs.readFile(output)), receipt);
}));

test('source changes between capture and completed build are rejected', () => fixture(async ({root, source, compiler}) => {
  const captured = await captureBuildInputs({source, files: {compiler}, recipe: {}});
  await fs.writeFile(path.join(source, 'module.cj'), 'main() { 1 }');
  await assert.rejects(finishBuildReceipt({source, captured, output: path.join(root, 'receipt'), artifacts: {}}), /source changed during build/);
}));

test('tracked build transformations remain distinct from the source commit', () => fixture(async ({source}) => {
  const before = sourceIdentity(source);
  await fs.writeFile(path.join(source, 'module.cj'), 'main() { 2 }');
  const after = sourceIdentity(source);
  assert.equal(before.commit, after.commit);
  assert.notEqual(before.diffSha256, after.diffSha256);
}));

test('untracked source cannot silently acquire the checkout identity', () => fixture(async ({source}) => {
  await fs.writeFile(path.join(source, 'extra.cj'), 'extra');
  assert.throws(() => sourceIdentity(source), /source receipt has untracked inputs/);
}));
