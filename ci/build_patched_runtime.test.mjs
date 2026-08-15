#!/usr/bin/env zx

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {
  GC_FIX_MAX_FETCH_DEPTH,
  INITIAL_RUNTIME_FETCH_DEPTH,
  gcFixCommit,
  verifyGcFixAncestry,
} from './build_patched_runtime.mjs';
import {resolveRuntimeSource} from './runtime-pin.mjs';

$.verbose = false;

const {runtimeRef, sourceUrl} = await resolveRuntimeSource({});
// The floor is read from the pin file, not from a literal here — a second copy of
// it is what went stale and took CI down on 2026-08-15.
const GC_FIX_COMMIT = await gcFixCommit({});
const suppliedSource = argv._[0];
const remote = suppliedSource
  ? (/^[a-z][a-z0-9+.-]*:\/\//i.test(suppliedSource)
    ? suppliedSource
    : pathToFileURL(path.resolve(suppliedSource)).href)
  : sourceUrl;
const temporaryRoot = await fs.mkdtemp(path.join(process.cwd(), '.build-patched-runtime-test-'));

async function initShallow(name, ref, depth) {
  const work = path.join(temporaryRoot, name);
  await fs.mkdir(work);
  await $({quiet: true, stdio: 'pipe'})`git -C ${work} init -q`;
  await $({quiet: true, stdio: 'pipe'})`git -C ${work} remote add origin ${remote}`;
  await $({quiet: true, stdio: 'pipe'})`git -C ${work} fetch --depth ${depth} origin ${ref}`;
  await $({quiet: true, stdio: 'pipe'})`git -C ${work} checkout -q FETCH_HEAD`;
  return work;
}

async function gitResult(work, ...arguments_) {
  return $({nothrow: true, quiet: true, stdio: 'pipe'})`git -C ${work} ${arguments_}`;
}

async function captureRuntimeLog(run) {
  const lines = [];
  const originalLog = console.log;
  console.log = (...values) => {
    const line = values.join(' ');
    lines.push(line);
    originalLog(...values);
  };
  let error;
  try {
    await run();
  } catch (caught) {
    error = caught;
  } finally {
    console.log = originalLog;
  }
  return {error, output: lines.join('\n')};
}

try {
  // Positive control first: retain the fix object, but point HEAD at a ref whose
  // history stops at the fix's parent. This is specifically the "object exists,
  // ancestry is false" arm and must remain fail-closed.
  const withoutFix = await initShallow('without-fix', runtimeRef, GC_FIX_MAX_FETCH_DEPTH);
  assert.equal((await gitResult(withoutFix, 'cat-file', '-e', `${GC_FIX_COMMIT}^{commit}`)).exitCode, 0);
  const withoutFixRef = (await gitResult(withoutFix, 'rev-parse', `${GC_FIX_COMMIT}^`)).stdout.trim();
  await $({quiet: true, stdio: 'pipe'})`git -C ${withoutFix} branch without-gc-fix ${withoutFixRef}`;
  await $({quiet: true, stdio: 'pipe'})`git -C ${withoutFix} checkout -q without-gc-fix`;
  assert.equal((await gitResult(withoutFix, 'merge-base', '--is-ancestor', GC_FIX_COMMIT, 'HEAD')).exitCode, 1);

  const positive = await captureRuntimeLog(
    () => verifyGcFixAncestry(withoutFix, 'refs/heads/without-gc-fix'),
  );
  assert.match(positive.error?.message || '', /pinned GC fix ancestry missing/);
  assert.match(positive.output, /is available, but runtime refs\/heads\/without-gc-fix does not descend/);
  assert.doesNotMatch(positive.output, /unreachable after deepening by/);
  console.log(`SELFTEST_CASE=without-fix ref=${withoutFixRef} rc=1 diagnostic=ancestry-missing`);

  // Negative control: reproduce the production depth-200 fetch from a clean
  // repository, then prove the measured deepen makes the object and ancestry
  // independently resolvable.
  // ⭐ 深度取 20 而非 INITIAL_RUNTIME_FETCH_DEPTH：⭐ 新地板离 pin 只有约 235 笔，
  // ⭐ 而 depth-200 的浅克隆已经能取到它 ⇒ ⭐⭐ 用 200 起步这条臂会**永远走不到加深路径**，
  // ⭐ 变成一个恒真的对照。⛔ 对照臂必须真的证明它要证明的那件事。
  const currentPin = await initShallow('current-pin', runtimeRef, 20);
  assert.notEqual((await gitResult(currentPin, 'cat-file', '-e', `${GC_FIX_COMMIT}^{commit}`)).exitCode, 0);
  const negative = await captureRuntimeLog(() => verifyGcFixAncestry(currentPin, runtimeRef));
  assert.equal(negative.error, undefined);
  assert.match(negative.output, /not present; deepening by \d+/);
  // The success line must name the depth it actually reached, so a future drift shows
  // up as a number that keeps climbing rather than as one hard-coded constant.
  assert.match(negative.output, /is an ancestor of the selected runtime source \(after deepening by \d+\)/);
  assert.equal((await gitResult(currentPin, 'cat-file', '-e', `${GC_FIX_COMMIT}^{commit}`)).exitCode, 0);
  assert.equal((await gitResult(currentPin, 'merge-base', '--is-ancestor', GC_FIX_COMMIT, 'HEAD')).exitCode, 0);
  assert.doesNotMatch(negative.output, /Not a valid commit name|runtime fetch apparatus/);
  console.log(`SELFTEST_CASE=current-pin ref=${runtimeRef} rc=0 object=commit ancestry=0`);

  // Apparatus diagnostic: a clean shallow fetch of the without-fix ref cannot
  // acquire the fix by deepening that history. It must not be mislabeled as an
  // ancestry result because the prerequisite object is absent.
  const missingObject = await initShallow(
    'missing-object', withoutFixRef, INITIAL_RUNTIME_FETCH_DEPTH,
  );
  assert.notEqual((await gitResult(missingObject, 'cat-file', '-e', `${GC_FIX_COMMIT}^{commit}`)).exitCode, 0);
  const apparatus = await captureRuntimeLog(
    () => verifyGcFixAncestry(missingObject, withoutFixRef),
  );
  assert.match(apparatus.error?.message || '', /unreachable after deepening by \d+/);
  assert.match(apparatus.output, /is still absent after asking for \d+ more commits/);
  assert.doesNotMatch(apparatus.output, /pinned GC fix ancestry missing|Not a valid commit name/);
  console.log(`SELFTEST_CASE=missing-object ref=${withoutFixRef} rc=1 diagnostic=fetch-apparatus`);
  console.log('SELFTEST_RESULT=PASS');
} finally {
  await fs.rm(temporaryRoot, {recursive: true, force: true});
}
