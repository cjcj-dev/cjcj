import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
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

// Route (b): ci/colour-runtime/* is the immutable record of already-published Darwin
// libraries. It is checked against its own producer run, never rewritten to the RC pin;
// the active RC runtime is checked against the explicit native producer pin instead.
const envPins = text => Object.fromEntries(text.trim().split('\n').map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));

test('active runtime pin is the explicit RC native producer runtime', async () => {
  const source = await resolveRuntimeSource({});
  const producer = envPins(await fs.readFile(new URL('../sdk/source_pin.env', import.meta.url), 'utf8')
    .then(text => text.split('\n').filter(line => line && !line.startsWith('#')).join('\n')));
  assert.equal(source.pinRef, producer.RUNTIME_REF, 'RUNTIME_PIN_NOT_RC_PRODUCER');
  console.log(`ASSERT ACTIVE_RUNTIME_PIN_RC ${source.pinRef}`);
});

for (const platform of ['darwin_aarch64', 'darwin_x86_64']) {
  test(`legacy published native libraries for ${platform} stay bound to their producer run`, async () => {
    const source = await resolveRuntimeSource({});
    const release = JSON.parse(await fs.readFile(
      new URL('../../ci/colour-runtime/release.json', import.meta.url), 'utf8'));
    const legacy = envPins(await fs.readFile(new URL(`../../ci/colour-runtime/${platform}.env`, import.meta.url), 'utf8'));
    const row = release.platforms[platform];
    assert.match(row?.runtime_sha ?? '', /^[0-9a-f]{40}$/, `DARWIN_LEGACY_RUNTIME_SHA: ${platform}`);
    assert.equal(row.run_id, legacy.COLOUR_RT_RUN_ID, `DARWIN_LEGACY_RUN_MISMATCH: ${platform}`);
    assert.equal(row.run_attempt, legacy.COLOUR_RT_RUN_ATTEMPT, `DARWIN_LEGACY_RUN_MISMATCH: ${platform}`);
    assert.notEqual(row.runtime_sha, source.pinRef,
      `DARWIN_LEGACY_IMPERSONATES_RC: ${platform}; rotate it only with a real rebuilt and republished tuple`);
    console.log(`ASSERT DARWIN_LEGACY_RUNTIME ${platform} ${row.runtime_sha} active=${source.pinRef}`);
  });
}

test('runtime source rejects an unauthorized override', async () => {
  await assert.rejects(resolveRuntimeSource({CJCJ_RUNTIME_REF_OVERRIDE: overrideRef}),
    /allowed only by an explicit dry-run\/test authorization/);
});

test('runtime source accepts an explicitly authorized exact commit', async () => {
  const source = await resolveRuntimeSource({
    CJCJ_RUNTIME_REF_OVERRIDE: overrideRef,
    CJCJ_ALLOW_RUNTIME_OVERRIDE: 'true',
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

test('runtime source rejects an incomplete explicit pair', async () => {
  await assert.rejects(resolveRuntimeSource({CJCJ_NATIVE_RUNTIME_REF: overrideRef}), /NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);
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
