import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

import {GATES} from './release-gates.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');
const SHA40 = /^[0-9a-f]{40}$/;

function run(program, args, options = {}) {
  return spawnSync(program, args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
}

function git(root, ...args) {
  const result = run('git', ['-C', root, ...args]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function commit(root, message) {
  git(root, 'add', '.');
  git(root, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
    'commit', '-m', message);
  const sha = git(root, 'rev-parse', 'HEAD');
  assert.match(sha, SHA40);
  return sha;
}

function gate(root, name, extra = []) {
  const result = run(process.execPath, [command, name, '--repo', root, '--json', ...extra]);
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`gate output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

test('registry keeps all 17 gates, exactly six explicit runs, and the four 0811 updates', () => {
  assert.deepEqual(Object.keys(GATES), Array.from({length: 17}, (_, index) => `G${index + 1}`));
  assert.deepEqual(Object.entries(GATES).filter(([, value]) => value.needsRun).map(([name]) => name),
    ['G3', 'G6', 'G7', 'G9', 'G10', 'G11']);
  assert.deepEqual(Object.entries(GATES).filter(([, value]) => value.updated).map(([name]) => name),
    ['G3', 'G4', 'G8', 'G9']);
});

test('G5 distinguishes an unwired checker from the same checker wired fail-closed', async t => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'release-gates-g5-'));
  t.after(() => fs.rm(fixture, {recursive: true, force: true}));
  git(fixture, 'init', '-q');
  await write(fixture, 'scripts/check_packaged_std.mjs',
    "const CLASS_NAMES = ['cjo', 'bc', 'static-ffi', 'shared', 'provenance'];\n");
  await write(fixture, '.github/workflows/build-release-package.yml', [
    'jobs:',
    '  package:',
    '    steps:',
    '      - name: Compose SDK package',
    '        run: node scripts/package_sdk.mjs',
    '',
  ].join('\n'));
  const before = commit(fixture, 'checker exists but has no consumer');
  await write(fixture, '.github/workflows/build-release-package.yml', [
    'jobs:',
    '  package:',
    '    steps:',
    '      - name: Compose SDK package',
    '        run: node scripts/package_sdk.mjs',
    '      - name: Verify packaged standard library',
    '        if: inputs.verify',
    '        timeout-minutes: 2',
    '        run: |',
    '          node scripts/check_packaged_std.mjs --sdk "$SDK" --std "$STD" --platform "$PLATFORM"',
    '      - name: Verify packaged SDK',
    '        run: node ci/smoke/run_smoke.mjs',
    '',
  ].join('\n'));
  const after = commit(fixture, 'wire checker');

  const negative = gate(fixture, 'G5', ['--ref', before]);
  assert.equal(negative.result.status, 1, negative.result.stderr);
  assert.equal(negative.value.status, 'NOT_MET');
  assert.match(negative.value.value, /workflow_consumers=0/);

  const positive = gate(fixture, 'G5', ['--ref', after]);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');
  assert.match(positive.value.value, /workflow_consumers=1/);
});

test('G13 distinguishes ancestor, non-ancestor, and unreadable runtime histories', async t => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'release-gates-g13-'));
  const cjcj = path.join(fixture, 'cjcj');
  const runtime = path.join(fixture, 'runtime');
  t.after(() => fs.rm(fixture, {recursive: true, force: true}));
  await fs.mkdir(cjcj, {recursive: true});
  await fs.mkdir(runtime, {recursive: true});

  git(runtime, 'init', '-q');
  await write(runtime, 'history.txt', 'root\n');
  const root = commit(runtime, 'root');
  await fs.appendFile(path.join(runtime, 'history.txt'), 'loaderlife\n');
  const loaderlife = commit(runtime, 'loaderlife');
  await fs.appendFile(path.join(runtime, 'history.txt'), 'pin tip\n');
  const positivePin = commit(runtime, 'pin tip');
  git(runtime, 'checkout', '-q', '-b', 'negative-control', root);
  await write(runtime, 'negative.txt', 'sibling without loaderlife\n');
  const negativePin = commit(runtime, 'negative sibling');

  await write(cjcj, 'ci/runtime_pin.env', [
    `RUNTIME_REF=${positivePin}`,
    'RUNTIME_VERSION=fixture',
    'RUNTIME_SRC_URL=https://example.invalid/runtime.git',
    `LOADERLIFE_MIN_REF=${loaderlife}`,
    '',
  ].join('\n'));
  for (const file of ['llvm_pin.env', 'source_pin.env', 'cjpm_pin.env']) {
    await write(cjcj, `ci/${file}`, '# unused by this fixture\n');
  }

  const positive = gate(cjcj, 'G13', ['--runtime-repo', runtime]);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');

  const negative = gate(cjcj, 'G13', [
    '--runtime-repo', runtime,
    '--runtime-ref', negativePin,
  ]);
  assert.equal(negative.result.status, 1, negative.result.stderr);
  assert.equal(negative.value.status, 'NOT_MET');

  const unknown = gate(cjcj, 'G13', ['--runtime-repo', path.join(fixture, 'missing-runtime')]);
  assert.equal(unknown.result.status, 2, unknown.result.stderr);
  assert.equal(unknown.value.status, 'UNKNOWN');
  assert.match(unknown.value.value, /runtime ancestry unreadable/);
});
