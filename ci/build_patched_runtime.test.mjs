#!/usr/bin/env zx

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {gcFixContentPresent, verifyGcFixAncestry} from './build_patched_runtime.mjs';

$.verbose = false;

const GOOD = `
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
  assert.equal(gcFixContentPresent(GOOD), true);
  assert.equal(gcFixContentPresent('bool TryAcquireMutatorManagementRLock() { return true; }'), false);
  const work = await fs.mkdtemp(path.join(process.cwd(), '.build-patched-runtime-test-'));
  try {
    const file = path.join(work, 'runtime/src/Mutator/MutatorManager.h');
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, GOOD);
    await verifyGcFixAncestry(work, 'HEAD');
    await fs.writeFile(file, 'bool TryAcquireMutatorManagementRLock() { return true; }\n');
    await assert.rejects(() => verifyGcFixAncestry(work, 'HEAD'), /pinned GC fix content missing/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
  console.log('SELFTEST_RESULT=PASS');
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
