import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {assertGitObjectProof} from './git-object-proof.mjs';

const context = {operation: 'fetch', url: 'controlled-local-remote', ref: 'controlled-pin'};
function rejects(result, pattern) {
  assert.throws(() => assertGitObjectProof(result, context), error => {
    assert.match(error.message, pattern);
    assert.match(error.message, /status=.*signal=.*error=.*stderr=/);
    assert.doesNotMatch(error.message, /is not reachable/);
    return true;
  });
}
test('Git proof timeout preserves ETIMEDOUT and does not claim missing object', () => {
  const result = spawnSync(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {timeout: 100, encoding: 'utf8'});
  assert.equal(result.error?.code, 'ETIMEDOUT');
  rejects(result, /Git timed out/);
});
test('Git proof startup failure preserves ENOENT', () => {
  const result = spawnSync('/nonexistent-cjcj-824-git', [], {encoding: 'utf8'});
  assert.equal(result.error?.code, 'ENOENT');
  rejects(result, /failed to start or complete/);
});
test('Git proof signal termination preserves SIGTERM', () => {
  const result = spawnSync(process.execPath, ['-e', 'process.kill(process.pid, "SIGTERM")'], {encoding: 'utf8'});
  assert.equal(result.signal, 'SIGTERM');
  rejects(result, /terminated by signal/);
});
test('Git proof missing exit status cannot pass', () => {
  rejects({status: null, signal: null, stderr: ''}, /no exit status/);
});
test('Git proof local remote accepts existing object and rejects missing object', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'git-proof-'));
  const git = args => spawnSync('git', args, {cwd: root, encoding: 'utf8', timeout: 5000});
  try {
    assert.equal(git(['init', '--bare', 'remote.git']).status, 0);
    assert.equal(git(['init', 'source']).status, 0);
    assert.equal(git(['-C', 'source', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']).status, 0);
    const ref = git(['-C', 'source', 'rev-parse', 'HEAD']).stdout.trim();
    assert.equal(git(['-C', 'source', 'push', '../remote.git', 'HEAD:refs/heads/main']).status, 0);
    assert.equal(git(['init', 'consumer']).status, 0);
    const probe = git(['ls-remote', 'remote.git']);
    assertGitObjectProof(probe, {...context, operation: 'ls-remote'});
    const fetch = sha => git(['-C', 'consumer', 'fetch', '--dry-run', '--depth', '1', '../remote.git', sha]);
    assertGitObjectProof(fetch(ref), {...context, ref});
    const missing = fetch('0123456789012345678901234567890123456789');
    assert.notEqual(missing.status, 0);
    assert.equal(missing.error, undefined);
    assert.equal(missing.signal, null);
    assert.throws(() => assertGitObjectProof(missing, context), /is not reachable/);
    assert.throws(() => assertGitObjectProof({...probe, status: 128}, {...context, operation: 'ls-remote'}), /remote preflight failed/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
