import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {runGrepProbe, runRequiredProbe} from '../lib/fail-closed-probes.mjs';

const zxProbe = spawnSync('sh', ['-c', 'command -v zx'], {encoding: 'utf8'});
const zxPath = zxProbe.status === 0 ? `${zxProbe.stdout || ''}`.trim() : '';
const zxCommand = zxPath
  ? {command: zxPath, prefix: []}
  : {command: 'npx', prefix: ['--yes', 'zx@8']};
const repoRoot = path.resolve(import.meta.dirname, '../..');
const coveredProbeLabels = new Set();

function coverProbeSite(label) {
  assert.equal(coveredProbeLabels.has(label), false, `duplicate negative control for ${label}`);
  coveredProbeLabels.add(label);
  return label;
}

async function productionProbeSites() {
  const listed = spawnSync('git', ['ls-files', '--', '*.mjs'], {cwd: repoRoot, encoding: 'utf8'});
  assert.equal(listed.status, 0, listed.stderr || 'git ls-files failed');
  const files = listed.stdout.split(/\r?\n/).filter(Boolean)
    .filter(relative => !relative.endsWith('.test.mjs'))
    .filter(relative => relative !== 'build/lib/fail-closed-probes.mjs');
  const sites = [];
  for (const relative of files) {
    const source = await fs.readFile(path.join(repoRoot, relative), 'utf8');
    const calls = [...source.matchAll(/\b(runRequiredProbe|runGrepProbe)\s*\(/g)];
    const labeled = [...source.matchAll(
      /\b(runRequiredProbe|runGrepProbe)\s*\(\s*\{\s*label:\s*(['"])([^'"\r\n]+)\2/g,
    )];
    assert.equal(labeled.length, calls.length,
      `${relative}: every fail-closed probe site must put a literal label first`);
    for (const match of labeled) {
      sites.push({
        helper: match[1],
        label: match[3],
        relative,
        line: source.slice(0, match.index).split('\n').length,
      });
    }
  }
  return sites;
}

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
  const label = coverProbeSite('LLVM tuple fallback prerequisite gh --version');
  const run = await failingTool(t, 'gh');
  await assert.rejects(
    runRequiredProbe({label, run}),
    /LLVM tuple fallback prerequisite gh --version failed \(exit=73\): gh forced failure/,
  );
});

test('tuple fetch unzip prerequisite cannot turn a failed tool into BLOCKED success', async t => {
  const label = coverProbeSite('LLVM tuple fallback prerequisite unzip -v');
  const run = await failingTool(t, 'unzip');
  await assert.rejects(
    runRequiredProbe({label, run}),
    /LLVM tuple fallback prerequisite unzip -v failed \(exit=73\): unzip forced failure/,
  );
});

test('tuple fetch script rejects an unsupported non-dry-run host', () => {
  const target = pathToFileURL(path.resolve('ci/platform_matrix/fetch_llvm_tuple.mjs')).href;
  const evaluate = [
    'Object.defineProperty(process, "platform", {value: "freebsd"});',
    `await import(${JSON.stringify(target)});`,
  ].join(' ');
  const result = spawnSync(zxCommand.command, [...zxCommand.prefix, '--eval', evaluate], {
    encoding: 'utf8',
    env: {...process.env, TUPLE_DRY_RUN: '0'},
  });
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 78, output);
  assert.match(output, /FATAL: required LLVM tuple unavailable: unsupported tuple host freebsd\/x64/);
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
  const label = coverProbeSite('SDK hard-coded LLVM library path grep');
  const failed = await failingTool(t, 'grep');
  await assert.rejects(
    runGrepProbe({label, run: failed}),
    /SDK hard-coded LLVM library path grep failed \(exit=73\): grep forced failure/,
  );
  const noMatch = await runGrepProbe({
    label,
    run: () => ({status: 1, stdout: '', stderr: ''}),
  });
  assert.equal(noMatch.matched, false);
});

test('bcgate final negative grep rejects apparatus failure', async t => {
  const label = coverProbeSite('bcgate one-side divergence grep');
  const run = await failingTool(t, 'grep');
  await assert.rejects(
    runGrepProbe({label, run}),
    /bcgate one-side divergence grep failed \(exit=73\): grep forced failure/,
  );
});

test('package rejects a failed readelf inspection', async t => {
  const label = coverProbeSite('package readelf -d bin/cjc');
  const run = await failingTool(t, 'readelf');
  await assert.rejects(
    runRequiredProbe({label, run}),
    /package readelf -d bin\/cjc failed \(exit=73\): readelf forced failure/,
  );
});

test('package rejects a failed ldd inspection', async t => {
  const label = coverProbeSite('package ldd bin/cjc');
  const run = await failingTool(t, 'ldd');
  await assert.rejects(
    runRequiredProbe({label, run}),
    /package ldd bin\/cjc failed \(exit=73\): ldd forced failure/,
  );
});

test('every production fail-closed probe site has a negative control', async () => {
  const sites = await productionProbeSites();
  const liveLabels = sites.map(({label}) => label);
  assert.equal(new Set(liveLabels).size, liveLabels.length,
    `fail-closed probe labels must identify one site each:\n${sites.map(
      site => `${site.label}\t${site.relative}:${site.line}`,
    ).join('\n')}`);
  assert.deepEqual([...coveredProbeLabels].sort(), [...liveLabels].sort(),
    'negative controls and production fail-closed probe sites diverged');
  console.log(`FAIL_CLOSED_PROBE_COVERAGE sites=${sites.length} files=${new Set(
    sites.map(({relative}) => relative),
  ).size}`);
});
