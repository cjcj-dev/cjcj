import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {gcFixContentPresent, GC_FIX_SOURCE, verifyGcFixAncestry} from './build_patched_runtime.mjs';

const GOOD = `
class MutatorManager {
    bool TryAcquireMutatorManagementRLock()
    {
        if (mgmtWritersWaiting.load(std::memory_order_acquire) > 0) {
            return false;
        }
        if (!mutatorManagementRWLock.TryLockRead()) {
            return false;
        }
        if (mgmtWritersWaiting.load(std::memory_order_acquire) > 0) {
            mutatorManagementRWLock.UnlockRead();
            return false;
        }
        return true;
    }
};
`;

const MISSING_RECHECK = `
class MutatorManager {
    bool TryAcquireMutatorManagementRLock()
    {
        if (mgmtWritersWaiting.load(std::memory_order_acquire) > 0) {
            return false;
        }
        if (!mutatorManagementRWLock.TryLockRead()) {
            return false;
        }
        return true;
    }
};
`;

function git(root, ...arguments_) {
  const result = spawnSync('git', ['-C', root, ...arguments_], {encoding: 'utf8'});
  assert.equal(result.status, 0, `git ${arguments_.join(' ')}: ${(result.stderr || '').trim()}`);
  return result.stdout.trim();
}

test('gcFixContentPresent is true only with post-lock writer recheck', () => {
  assert.equal(gcFixContentPresent(GOOD), true);
  assert.equal(gcFixContentPresent(MISSING_RECHECK), false);
  assert.equal(gcFixContentPresent('no function here'), false);
});

test('rewritten history with same content: old ancestry red, content floor green', async () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'gc-fix-rewrite-'));
  try {
    git(fixture, 'init', '--quiet', '--initial-branch=main');
    git(fixture, 'config', 'user.name', 'Zxilly');
    git(fixture, 'config', 'user.email', 'zxilly@outlook.com');
    const file = path.join(fixture, ...GC_FIX_SOURCE.split('/'));
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, GOOD);
    git(fixture, 'add', GC_FIX_SOURCE);
    git(fixture, 'commit', '--quiet', '-m', 'introducer');
    const oldSha = git(fixture, 'rev-parse', 'HEAD');

    git(fixture, 'checkout', '--orphan', 'rewritten');
    git(fixture, 'commit', '--quiet', '-m', 'rewrite keeps content');
    const newSha = git(fixture, 'rev-parse', 'HEAD');
    assert.notEqual(oldSha, newSha);
    const ancestry = spawnSync('git', ['-C', fixture, 'merge-base', '--is-ancestor', oldSha, 'HEAD'], {
      encoding: 'utf8',
    });
    assert.equal(ancestry.status, 1, 'old sha must not be an ancestor after rewrite');
    await verifyGcFixAncestry(fixture, 'HEAD');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('missing post-lock recheck fails content floor', async () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'gc-fix-missing-'));
  try {
    const file = path.join(fixture, ...GC_FIX_SOURCE.split('/'));
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, MISSING_RECHECK);
    await assert.rejects(() => verifyGcFixAncestry(fixture, 'HEAD'), /pinned GC fix content missing/);
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});
