import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {runGrepProbe, runRequiredProbe} from '../lib/fail-closed-probes.mjs';

const zxProbe = spawnSync('sh', ['-c', 'command -v zx'], {encoding: 'utf8'});
const zxPath = zxProbe.status === 0 ? `${zxProbe.stdout || ''}`.trim() : '';
const zxCommand = zxPath
  ? {command: zxPath, prefix: []}
  : {command: 'npx', prefix: ['--yes', 'zx@8']};

async function failingTool(t, name, exit = 73) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'fail-closed-probe-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const executable = path.join(root, name);
  await fs.writeFile(executable, [
    '#!/bin/sh',
    `printf '%s\\n' '${name} forced failure' >&2`,
    `exit ${exit}`,
    '',
  ].join('\n'), {mode: 0o755});
  return () => spawnSync(executable, [], {encoding: 'utf8'});
}

test('tuple fetch prerequisite cannot turn a failed tool into BLOCKED success', async t => {
  const run = await failingTool(t, 'gh');
  await assert.rejects(
    runRequiredProbe({label: 'LLVM tuple fallback prerequisite gh --version', run}),
    /LLVM tuple fallback prerequisite gh --version failed \(exit=73\): gh forced failure/,
  );
});

test('tuple fetch script rejects an incomplete current-run artifact', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'tuple-fetch-negative-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const artifact = path.join(root, 'artifact');
  await fs.mkdir(artifact);
  await fs.writeFile(path.join(artifact, 'incomplete-marker'), 'fixture\n');
  const result = spawnSync(zxCommand.command, [
    ...zxCommand.prefix,
    path.resolve('ci/platform_matrix/fetch_llvm_tuple.mjs'),
  ], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PLATFORM_CI_ROOT: path.join(root, 'platform-ci'),
      TUPLE_ARTIFACT_DIR: artifact,
      TUPLE_FETCH_ATTEMPTS: '1',
      TUPLE_FETCH_DELAY_SECONDS: '0',
      TUPLE_DRY_RUN: '0',
    },
  });
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 78, output);
  assert.match(output, /required LLVM tuple unavailable: fixed-llvm-tools-.* is incomplete/);

  const dryRun = spawnSync(zxCommand.command, [
    ...zxCommand.prefix,
    path.resolve('ci/platform_matrix/fetch_llvm_tuple.mjs'),
  ], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PLATFORM_CI_ROOT: path.join(root, 'platform-ci-dry'),
      TUPLE_ARTIFACT_DIR: artifact,
      TUPLE_DRY_RUN: '1',
    },
  });
  assert.equal(dryRun.status, 0, `${dryRun.stdout}\n${dryRun.stderr}`);
});

test('tuple fetch script rejects a failed gh prerequisite', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'tuple-fetch-gh-negative-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const artifact = path.join(root, 'empty-artifact');
  const stubBin = path.join(root, 'bin');
  await Promise.all([fs.mkdir(artifact), fs.mkdir(stubBin)]);
  await fs.writeFile(path.join(stubBin, 'gh'), [
    '#!/bin/sh',
    "printf '%s\\n' 'gh forced failure' >&2",
    'exit 73',
    '',
  ].join('\n'), {mode: 0o755});
  const result = spawnSync(zxCommand.command, [
    ...zxCommand.prefix,
    path.resolve('ci/platform_matrix/fetch_llvm_tuple.mjs'),
  ], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${stubBin}:${process.env.PATH}`,
      PLATFORM_CI_ROOT: path.join(root, 'platform-ci'),
      TUPLE_ARTIFACT_DIR: artifact,
      TUPLE_FETCH_ATTEMPTS: '1',
      TUPLE_FETCH_DELAY_SECONDS: '0',
      TUPLE_DRY_RUN: '0',
    },
  });
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 78, output);
  assert.match(output, /required LLVM tuple unavailable: LLVM tuple fallback prerequisite gh --version failed \(exit=73\): gh forced failure/);
});

test('SDK LLVM-path grep distinguishes no match from apparatus failure', async t => {
  const failed = await failingTool(t, 'grep');
  await assert.rejects(
    runGrepProbe({label: 'SDK hard-coded LLVM library path grep', run: failed}),
    /SDK hard-coded LLVM library path grep failed \(exit=73\): grep forced failure/,
  );
  const noMatch = await runGrepProbe({
    label: 'SDK hard-coded LLVM library path grep',
    run: () => ({status: 1, stdout: '', stderr: ''}),
  });
  assert.equal(noMatch.matched, false);
});

test('bcgate final negative grep rejects apparatus failure', async t => {
  const run = await failingTool(t, 'grep');
  await assert.rejects(
    runGrepProbe({label: 'bcgate one-side divergence grep', run}),
    /bcgate one-side divergence grep failed \(exit=73\): grep forced failure/,
  );
});

test('package rejects a failed readelf inspection', async t => {
  const run = await failingTool(t, 'readelf');
  await assert.rejects(
    runRequiredProbe({label: 'package readelf -d bin/cjc', run}),
    /package readelf -d bin\/cjc failed \(exit=73\): readelf forced failure/,
  );
});

test('package rejects a failed ldd inspection', async t => {
  const run = await failingTool(t, 'ldd');
  await assert.rejects(
    runRequiredProbe({label: 'package ldd bin/cjc', run}),
    /package ldd bin\/cjc failed \(exit=73\): ldd forced failure/,
  );
});
