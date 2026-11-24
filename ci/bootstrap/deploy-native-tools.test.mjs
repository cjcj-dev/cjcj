// The private Darwin H1 adapter (ts/src/sharedbuild) is retired: no host reads
// a private tools root, Linux and Darwin share the public cjpm H1 path, and a
// tools checkout is accepted only from the public origin at a 40-hex commit.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {RETIRED_NATIVE_TOOLS_ADAPTER_FILES, publicToolsRepository, rejectPrivateTools,
  verifyPublicToolsCheckout} from './deploy-native-tools.mjs';

const PUBLIC = 'https://github.com/cjcj-dev/cjcj-tools';
const read = rel => fs.readFileSync(new URL('../../' + rel, import.meta.url), 'utf8');
const git = (cwd, ...args) => {
  const r = spawnSync('git', ['-C', cwd, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', ...args], {encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
};
function tools(t, {origin = PUBLIC + '.git'} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'native-tools-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const repo = path.join(dir, 'tools');
  fs.mkdirSync(repo);
  git(repo, 'init', '-q');
  fs.writeFileSync(path.join(repo, 'README.md'), 'tools\n');
  git(repo, 'add', '-A');
  git(repo, 'commit', '-qm', 'test: tools');
  git(repo, 'remote', 'add', 'origin', origin);
  return {dir, repo, commit: git(repo, 'rev-parse', 'HEAD')};
}

test('the tools origin is the public pinned repository and TOOLS_REF is unchanged', () => {
  const pin = read('ci/source_pin.env');
  assert.match(pin, /^TOOLS_REF=4d14d051c58a5574d6525314b2c695e2e5dd26e6$/m);
  assert.equal(publicToolsRepository(), PUBLIC);
  assert.throws(() => publicToolsRepository('TOOLS_SRC_URL=git@internal:private/tools.git\n'), /NATIVE_TOOLS_PUBLIC_URL/);
});

test('no producer or consumer reads the retired private sharedbuild modules', () => {
  assert.deepEqual(RETIRED_NATIVE_TOOLS_ADAPTER_FILES, ['ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']);
  for (const rel of ['ci/bootstrap/sdk-inputs.mjs', 'ci/bootstrap/configure-gha-inputs.mjs', '.github/workflows/sdk-build-target.yml']) {
    const text = read(rel);
    assert.doesNotMatch(text, /sharedbuild|NATIVE_TOOLS_ADAPTER_FILES|NATIVE_H1_PRIVATE_PRODUCER_REQUIRED/, rel);
  }
  assert.doesNotMatch(read('build/sdk/producers/release/prepare_native_inputs.mjs'), /NATIVE_TOOLS_ADAPTER_FILES|privateRoot: 'adapter'/);
  assert.match(read('ci/bootstrap/sdk-inputs.mjs'), /rejectPrivateTools\(tools\)/);
  assert.match(read('ci/bootstrap/configure-gha-inputs.mjs'), /rejectPrivateTools\(locations\.tools/);
});

test('a private tools root fails closed on every host', () => {
  assert.deepEqual(rejectPrivateTools({cc: 'clang'}), {cc: 'clang'});
  assert.throws(() => rejectPrivateTools({privateRoot: '/x/adapter'}), /NATIVE_TOOLS_PRIVATE_ROOT_RETIRED/);
  assert.throws(() => rejectPrivateTools({privateRoot: ''}), /NATIVE_TOOLS_PRIVATE_ROOT_RETIRED/);
});

test('a tools checkout is accepted only from the public origin at an explicit commit', async t => {
  const f = tools(t);
  assert.deepEqual(await verifyPublicToolsCheckout(f.repo, f.commit, {publicUrl: PUBLIC}), {repository: PUBLIC, commit: f.commit});
  const moved = tools(t, {origin: 'git@internal:private/tools.git'});
  await assert.rejects(verifyPublicToolsCheckout(moved.repo, moved.commit, {publicUrl: PUBLIC}), /NATIVE_TOOLS_REPOSITORY_NOT_PUBLIC/);
  await assert.rejects(verifyPublicToolsCheckout(f.repo, 'main', {publicUrl: PUBLIC}), /NATIVE_TOOLS_COMMIT_REQUIRED/);
  await assert.rejects(verifyPublicToolsCheckout(f.repo, '0'.repeat(40), {publicUrl: PUBLIC}));
});
