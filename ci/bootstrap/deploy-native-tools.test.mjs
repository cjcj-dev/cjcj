// The Darwin H1 adapter is deployed only from the public tools repository at a
// pinned commit; TOOLS_REF stays the product pin and private sources are refused.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {NATIVE_TOOLS_ADAPTER_FILES, deployNativeTools, publicToolsRepository} from './deploy-native-tools.mjs';

const PUBLIC = 'https://github.com/cjcj-dev/cjcj-tools';
const git = (cwd, ...args) => {
  const r = spawnSync('git', ['-C', cwd, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', ...args], {encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
};
function tools(t, {files = NATIVE_TOOLS_ADAPTER_FILES, origin = PUBLIC + '.git'} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'native-tools-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const repo = path.join(dir, 'tools');
  fs.mkdirSync(repo);
  git(repo, 'init', '-q');
  fs.writeFileSync(path.join(repo, 'README.md'), 'tools\n');
  for (const rel of files) { fs.mkdirSync(path.dirname(path.join(repo, rel)), {recursive: true}); fs.writeFileSync(path.join(repo, rel), `// ${rel}\n`); }
  git(repo, 'add', '-A');
  git(repo, 'commit', '-qm', 'test: adapter');
  git(repo, 'remote', 'add', 'origin', origin);
  return {dir, repo, commit: git(repo, 'rev-parse', 'HEAD')};
}

test('the adapter source is the public pinned tools repository and TOOLS_REF is unchanged', () => {
  const pin = fs.readFileSync(new URL('../source_pin.env', import.meta.url), 'utf8');
  assert.match(pin, /^TOOLS_REF=3460b1e55a16414f52385663ba780fb4ed07ee65$/m);
  assert.equal(publicToolsRepository(), PUBLIC);
  assert.throws(() => publicToolsRepository('TOOLS_SRC_URL=git@internal:private/tools.git\n'), /NATIVE_TOOLS_PUBLIC_URL/);
  assert.deepEqual(NATIVE_TOOLS_ADAPTER_FILES, ['ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']);
  const inputs = fs.readFileSync(new URL('./sdk-inputs.mjs', import.meta.url), 'utf8');
  assert.match(inputs, /for\(const rel of NATIVE_TOOLS_ADAPTER_FILES\)/);
  assert.doesNotMatch(fs.readFileSync(new URL('./deploy-native-tools.mjs', import.meta.url), 'utf8'), /paired private tools commit/);
});

test('deploy exports both modules from the public pinned commit with digests', async t => {
  const f = tools(t);
  const result = await deployNativeTools(f.repo, f.commit, path.join(f.dir, 'adapter'), {publicUrl: PUBLIC});
  assert.deepEqual(Object.keys(result.files), NATIVE_TOOLS_ADAPTER_FILES);
  const record = JSON.parse(fs.readFileSync(path.join(f.dir, 'adapter/BUILD-INPUTS.json'), 'utf8'));
  assert.equal(record.repository, PUBLIC);
  assert.equal(record.commit, f.commit);
  for (const rel of NATIVE_TOOLS_ADAPTER_FILES) assert.equal(fs.readFileSync(path.join(f.dir, 'adapter', rel), 'utf8'), `// ${rel}\n`);
});

test('red cut: a commit without the public adapter fails closed before writing', async t => {
  const f = tools(t, {files: [NATIVE_TOOLS_ADAPTER_FILES[0]]});
  await assert.rejects(deployNativeTools(f.repo, f.commit, path.join(f.dir, 'adapter'), {publicUrl: PUBLIC}),
    new RegExp(`NATIVE_TOOLS_ADAPTER_MISSING ts/src/sharedbuild/stage1-transform\\.mjs@${f.commit}`));
  assert.equal(fs.existsSync(path.join(f.dir, 'adapter')), false);
});

test('red cut: a private or wrong-path origin is refused', async t => {
  const f = tools(t, {origin: 'git@github.com:cjcj-dev/cjcj-tools-private.git'});
  await assert.rejects(deployNativeTools(f.repo, f.commit, path.join(f.dir, 'adapter'), {publicUrl: PUBLIC}), /NATIVE_TOOLS_REPOSITORY_NOT_PUBLIC/);
  const moved = tools(t, {files: ['src/sharedbuild/cjcj-stage1.mjs', 'src/sharedbuild/stage1-transform.mjs']});
  await assert.rejects(deployNativeTools(moved.repo, moved.commit, path.join(moved.dir, 'adapter'), {publicUrl: PUBLIC}),
    /NATIVE_TOOLS_ADAPTER_MISSING ts\/src\/sharedbuild\/cjcj-stage1\.mjs/);
  await assert.rejects(deployNativeTools(f.repo, 'main', path.join(f.dir, 'adapter'), {publicUrl: PUBLIC}), /NATIVE_TOOLS_COMMIT_REQUIRED/);
});
