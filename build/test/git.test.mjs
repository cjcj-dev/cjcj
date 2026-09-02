import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {shallowClone} from '../lib/git.mjs';

const runGit = (args, options = {}) => {
  const result = spawnSync('git', args, {encoding: 'utf8', ...options});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};

test('shallowClone fetches a full commit SHA without treating it as a branch', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-git-'));
  const destination = path.join(root, 'checkout');
  const sha = '27d23ffbe2ba3ec28719c30977832816370c8231';
  const previousDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  const originalWrite = process.stderr.write;
  let output = '';
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  try {
    await shallowClone('https://example.invalid/runtime.git', destination, {tag: sha});
  } finally {
    process.stderr.write = originalWrite;
    if (previousDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previousDryRun;
    fs.rmSync(root, {recursive: true, force: true});
  }
  assert.match(output, /git init/);
  assert.match(output, new RegExp(`git -C .* -c http.version=HTTP/1.1 fetch --depth 1 https://example.invalid/runtime.git ${sha}`));
  assert.match(output, /git -C .* checkout --detach FETCH_HEAD/);
  assert.doesNotMatch(output, new RegExp(`clone .* --branch ${sha}`));
});

test('shallowClone fetches through a source mirror but retains the authoritative remote', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-git-mirror-'));
  const source = path.join(root, 'source');
  const mirror = path.join(root, 'runtime.git');
  const destination = path.join(root, 'checkout');
  const authoritative = 'https://github.com/cjcj-dev/cangjie-runtime.git';
  const previousMirrors = process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS;
  t.after(() => {
    if (previousMirrors === undefined) delete process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS;
    else process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS = previousMirrors;
    fs.rmSync(root, {recursive: true, force: true});
  });

  runGit(['init', source]);
  fs.writeFileSync(path.join(source, 'README'), 'mirror fixture\n');
  runGit(['-C', source, 'add', 'README']);
  runGit(['-C', source, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-m', 'fixture']);
  const sha = runGit(['-C', source, 'rev-parse', 'HEAD']);
  runGit(['clone', '--bare', source, mirror]);
  process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS = `${authoritative}=file://${mirror}`;

  await shallowClone(authoritative, destination, {tag: sha});

  assert.equal(runGit(['-C', destination, 'rev-parse', 'HEAD']), sha);
  assert.equal(runGit(['-C', destination, 'remote', 'get-url', 'origin']), authoritative);
});
