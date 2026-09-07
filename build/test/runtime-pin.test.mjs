import assert from 'node:assert/strict';
import test from 'node:test';
import {resolveRuntimeSource} from '../../ci/runtime-pin.mjs';

const overrideRef = '1111111111111111111111111111111111111111';
const lowercaseRef = '751210efa9494b0877ee82e68af65171a0ecb85e';
const uppercaseRef = lowercaseRef.toUpperCase();
const mixedCaseRef = '751210eFa9494b0877eE82e68af65171a0ecb85e';
const oldRef = '08a7709ab15caf71b85843e8ea221fe3aedd6e99';

async function assertAuthorizedRefAccepted(runtimeRef) {
  const source = await resolveRuntimeSource({
    CJCJ_RUNTIME_REF_OVERRIDE: runtimeRef,
    CJCJ_ALLOW_RUNTIME_OVERRIDE: 'true',
    RUNTIME_REF: runtimeRef,
  });
  assert.equal(source.runtimeRef, runtimeRef);
}

async function assertAuthorizedRefRejected(runtimeRef) {
  await assert.rejects(resolveRuntimeSource({
    CJCJ_RUNTIME_REF_OVERRIDE: runtimeRef,
    CJCJ_ALLOW_RUNTIME_OVERRIDE: 'true',
  }), /full 40-character commit SHA/);
}

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

test('runtime source accepts a lowercase 40-character commit SHA', async () => {
  await assertAuthorizedRefAccepted(lowercaseRef);
});

test('runtime source accepts an uppercase 40-character commit SHA', async () => {
  await assertAuthorizedRefAccepted(uppercaseRef);
});

test('runtime source accepts a mixed-case 40-character commit SHA', async () => {
  await assertAuthorizedRefAccepted(mixedCaseRef);
});

test('runtime source continues to accept the old full commit SHA', async () => {
  await assertAuthorizedRefAccepted(oldRef);
});

test('runtime source rejects a mismatched consumer ref', async () => {
  await assert.rejects(resolveRuntimeSource({RUNTIME_REF: overrideRef}), /runtime ref mismatch/);
});

test('runtime source rejects a 39-character commit SHA', async () => {
  await assertAuthorizedRefRejected(lowercaseRef.slice(0, 39));
});

test('runtime source rejects a 41-character commit SHA', async () => {
  await assertAuthorizedRefRejected(`${lowercaseRef}0`);
});

test('runtime source rejects a non-hexadecimal 40-character commit SHA', async () => {
  await assertAuthorizedRefRejected(`${lowercaseRef.slice(0, 39)}g`);
});
