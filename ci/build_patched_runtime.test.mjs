#!/usr/bin/env zx

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {gcFixWeakSourceShapePresent, verifyGcFixWeakSourceShape} from './build_patched_runtime.mjs';

$.verbose = false;

const CANONICAL_SOURCE_SHAPE = `
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
`;

try {
  assert.equal(gcFixWeakSourceShapePresent(CANONICAL_SOURCE_SHAPE), true);
  assert.equal(gcFixWeakSourceShapePresent('bool TryAcquireMutatorManagementRLock() { return true; }'), false);
  const work = await fs.mkdtemp(path.join(process.cwd(), '.build-patched-runtime-test-'));
  try {
    const file = path.join(work, 'runtime/src/Mutator/MutatorManager.h');
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, CANONICAL_SOURCE_SHAPE);
    await verifyGcFixWeakSourceShape(work, 'HEAD');
    await fs.writeFile(file, 'bool TryAcquireMutatorManagementRLock() { return true; }\n');
    await assert.rejects(
      () => verifyGcFixWeakSourceShape(work, 'HEAD'),
      /pinned GC weak source-shape floor missing/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
  console.log('SELFTEST_RESULT=PASS');
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
