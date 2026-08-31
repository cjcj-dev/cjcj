import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test, {after, before} from 'node:test';
import {
  gcFixWeakSourceShapePresent,
  GC_FIX_SOURCE,
  verifyGcFixWeakSourceShape,
} from './build_patched_runtime.mjs';
import {resolveRuntimeSource} from './runtime-pin.mjs';

let checkout;
let checkoutOwned = false;
let actualHeader;

function git(root, ...arguments_) {
  const result = spawnSync('git', ['-C', root, ...arguments_], {encoding: 'utf8'});
  assert.equal(result.status, 0, `git ${arguments_.join(' ')}: ${(result.stderr || '').trim()}`);
  return result.stdout.trim();
}

before(async () => {
  const {runtimeRef, sourceUrl} = await resolveRuntimeSource();
  const configuredCheckout = process.env.GC_FIX_RUNTIME_CHECKOUT;
  if (configuredCheckout) {
    checkout = path.resolve(configuredCheckout);
  } else {
    checkout = fs.mkdtempSync(path.join(os.tmpdir(), 'gc-fix-runtime-checkout-'));
    checkoutOwned = true;
    git(checkout, 'init', '--quiet');
    git(checkout, 'remote', 'add', 'origin', sourceUrl);
    git(checkout, 'fetch', '--quiet', '--depth=1', 'origin', runtimeRef);
    git(checkout, 'checkout', '--quiet', '--detach', 'FETCH_HEAD');
  }
  const checkoutHead = git(checkout, 'rev-parse', 'HEAD');
  assert.equal(checkoutHead, runtimeRef, 'fixture checkout must match the pinned runtime ref');
  actualHeader = fs.readFileSync(path.join(checkout, ...GC_FIX_SOURCE.split('/')), 'utf8');
  const headerSha256 = crypto.createHash('sha256').update(actualHeader).digest('hex');
  console.log(`ACTUAL_RUNTIME_CHECKOUT_HEAD=${checkoutHead}`);
  console.log(`ACTUAL_MUTATOR_MANAGER_SHA256=${headerSha256}`);
});

after(() => {
  if (checkoutOwned) fs.rmSync(checkout, {recursive: true, force: true});
});

function withoutCanonicalUnlock(sourceText) {
  const functionStart = sourceText.indexOf('bool TryAcquireMutatorManagementRLock()');
  const lock = sourceText.indexOf('mutatorManagementRWLock.TryLockRead()', functionStart);
  const token = 'mutatorManagementRWLock.UnlockRead();';
  const unlock = sourceText.indexOf(token, lock);
  assert.ok(functionStart >= 0 && lock > functionStart && unlock > lock,
    'actual checkout must contain the canonical post-TryLockRead UnlockRead token');
  return sourceText.slice(0, unlock)
    + '/* fault injection: canonical UnlockRead token removed */'
    + sourceText.slice(unlock + token.length);
}

test('weak source-shape floor accepts the actual checkout and rejects a missing token', () => {
  assert.equal(gcFixWeakSourceShapePresent(actualHeader), true);
  assert.equal(gcFixWeakSourceShapePresent(withoutCanonicalUnlock(actualHeader)), false);
  assert.equal(gcFixWeakSourceShapePresent('no function here'), false);
});

test('rewritten history drops every old ref while actual checkout source shape remains', async () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'gc-fix-rewrite-'));
  try {
    git(fixture, 'init', '--quiet', '--initial-branch=main');
    git(fixture, 'config', 'user.name', 'Zxilly');
    git(fixture, 'config', 'user.email', 'zxilly@outlook.com');
    const file = path.join(fixture, ...GC_FIX_SOURCE.split('/'));
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.copyFileSync(path.join(checkout, ...GC_FIX_SOURCE.split('/')), file);
    git(fixture, 'add', GC_FIX_SOURCE);
    git(fixture, 'commit', '--quiet', '-m', 'introducer');
    const oldSha = git(fixture, 'rev-parse', 'HEAD');

    git(fixture, 'checkout', '--orphan', 'rewritten');
    git(fixture, 'commit', '--quiet', '-m', 'rewrite keeps content');
    const refsBeforeDelete = git(
      fixture, 'for-each-ref', '--format=%(refname)', `--contains=${oldSha}`);
    assert.equal(refsBeforeDelete, 'refs/heads/main', 'positive control must retain old sha');
    console.log(`REWRITE_REFS_BEFORE_DELETE=${refsBeforeDelete}`);
    git(fixture, 'branch', '--delete', '--force', 'main');
    const newSha = git(fixture, 'rev-parse', 'HEAD');
    assert.notEqual(oldSha, newSha);
    const ancestry = spawnSync('git', ['-C', fixture, 'merge-base', '--is-ancestor', oldSha, 'HEAD'], {
      encoding: 'utf8',
    });
    assert.equal(ancestry.status, 1, 'old sha must not be an ancestor after rewrite');
    const refsContainingOld = git(
      fixture, 'for-each-ref', '--format=%(refname)', `--contains=${oldSha}`);
    assert.equal(refsContainingOld, '', 'no ref may contain the old sha after rewrite');
    console.log('REWRITE_REFS_CONTAINING_OLD=<empty>');
    await verifyGcFixWeakSourceShape(fixture, 'HEAD');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('missing canonical token fails the weak source-shape floor', async () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'gc-fix-missing-'));
  try {
    const file = path.join(fixture, ...GC_FIX_SOURCE.split('/'));
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, withoutCanonicalUnlock(actualHeader));
    await assert.rejects(
      () => verifyGcFixWeakSourceShape(fixture, 'HEAD'),
      /pinned GC weak source-shape floor missing/);
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});
