#!/usr/bin/env zx
// Read retained official inputs. Only the real producer authenticates payload
// bytes and emits receipts; fixture preparation never manufactures that proof.
import assert from 'node:assert/strict';
import path from 'node:path';
import {readJson, fileDigest, validatePlan, atomicJson} from '../sdk-manifest.mjs';
import {validateOfficialSdkProof, officialIdentityVerifier} from '../../../build/lib/official-sdk-identity.mjs';

export async function officialFixtureSource(planFile = process.env.SDK_OFFICIAL_PLAN) {
  assert.ok(planFile && path.isAbsolute(planFile), 'SDK_FIXTURE_NOT_RUN: supply an absolute retained SDK_OFFICIAL_PLAN');
  const plan = validatePlan(await readJson(planFile));
  assert.equal(plan.components.length, 1, 'SDK_FIXTURE_NOT_RUN: retained official input must be a one-component plan');
  const component = plan.components[0];
  assert.equal(component.producer.adapter, 'official');
  assert.equal(component.source.kind, 'distribution');
  assert.equal(component.domain, 'host');
  assert.equal(component.source.version, '1.3.0-alpha.20261009001050', 'SDK_FIXTURE_NOT_RUN: this input contract retains the real 1009 release');
  await officialFixtureLock(component.source);
  return structuredClone(component.source);
}

export async function officialFixtureLock(source) {
  assert.equal(await fileDigest(source.lock), source.lockSha256, 'retained official lock changed');
  const lock = await readJson(source.lock);
  assert.equal(lock.schema, 'sharedbuild-official-sdk-v1');
  assert.equal(lock.role, 'host');
  assert.equal(lock.version, source.version);
  validateOfficialSdkProof(lock.officialIdentity, source.version);
  return lock;
}

export async function officialFixtureRequest(source, requestFile) {
  const lock = await officialFixtureLock(source);
  const request = {verifier: await officialIdentityVerifier(), input: {
    archive: lock.officialIdentity.archive.path, platform: lock.officialIdentity.platform,
    readonly: lock.layoutVersion === 1 || lock.officialMaterialization === 'readonly',
  }};
  await atomicJson(requestFile, request);
  return request;
}

export function unavailableOfficialMutation(detail) {
  throw new Error(`SDK_FIXTURE_NOT_RUN: ${detail}; no legal non-target official archive input is retained. Preserve the target assertion and obtain its input contract before execution.`);
}
