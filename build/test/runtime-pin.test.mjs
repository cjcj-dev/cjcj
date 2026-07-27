import assert from 'node:assert/strict';
import test from 'node:test';
import {resolveRuntimeSource} from '../../ci/runtime-pin.mjs';

const overrideRef = '1111111111111111111111111111111111111111';

test('runtime source defaults to the checked-in pin', async () => {
  const source = await resolveRuntimeSource({});
  assert.equal(source.runtimeRef, source.pinRef);
  assert.equal(source.overrideRef, '');
});

test('runtime source rejects an unauthorized override', async () => {
  await assert.rejects(resolveRuntimeSource({CJCJ_RUNTIME_REF_OVERRIDE: overrideRef}),
    /allowed only by an explicit dry-run\/test authorization/);
});

test('runtime source accepts an explicitly authorized exact commit', async () => {
  const source = await resolveRuntimeSource({
    CJCJ_RUNTIME_REF_OVERRIDE: overrideRef,
    CJCJ_ALLOW_RUNTIME_OVERRIDE: 'true',
    RUNTIME_REF: overrideRef,
  });
  assert.equal(source.runtimeRef, overrideRef);
  assert.equal(source.pinRef === overrideRef, false);
});

test('runtime source rejects a mismatched consumer ref', async () => {
  await assert.rejects(resolveRuntimeSource({RUNTIME_REF: overrideRef}), /runtime ref mismatch/);
});

test('runtime source requires a full commit SHA', async () => {
  await assert.rejects(resolveRuntimeSource({
    CJCJ_RUNTIME_REF_OVERRIDE: 'ddc45606',
    CJCJ_ALLOW_RUNTIME_OVERRIDE: '1',
  }), /full 40-character commit SHA/);
});
