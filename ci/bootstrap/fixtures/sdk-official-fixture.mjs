#!/usr/bin/env zx
// Read retained official inputs. Only the real producer authenticates payload
// bytes and emits receipts; fixture preparation never manufactures that proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {readJson, fileDigest, validatePlan, atomicJson, execute} from '../sdk-manifest.mjs';
import {validateOfficialSdkProof, officialIdentityVerifier} from '../../../build/lib/official-sdk-identity.mjs';

export async function officialFixtureSource(planFile = process.env.SDK_OFFICIAL_PLAN) {
  assert.ok(planFile && path.isAbsolute(planFile), 'SDK_FIXTURE_NOT_RUN: supply an absolute retained SDK_OFFICIAL_PLAN');
  const plan = validatePlan(await readJson(planFile));
  assert.equal(plan.role, 'host');
  assert.equal(plan.platform, 'linux_x86_64');
  assert.equal(plan.components.length, 1, 'SDK_FIXTURE_NOT_RUN: retained official input must be a one-component plan');
  const component = plan.components[0];
  assert.equal(component.producer.adapter, 'official');
  assert.equal(component.source.kind, 'distribution');
  assert.equal(component.domain, 'host');
  assert.ok(component.roles.includes('official-host'));
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
  assert.equal(lock.officialIdentity.platform, 'linux-x64');
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

// The normal publisher creates a full physical copy (copytree, symlinks=False)
// and its own lock. Negative consumers may only mutate this owner-local entity,
// never the retained distribution or its successful input records.
export async function privateOfficialFixtureSource(source, root, engine) {
  const cache = path.join(root, 'private-official-cache');
  const request = path.join(root, 'private-official-request.json');
  await officialFixtureRequest(source, request);
  let result;
  try {
    result = {rc: 0, ...await execute('python3', ['-I', engine, '--remote', '--root', cache,
      '--lane', path.basename(root), 'sdk-publish',
      '--source', source.root, '--version', source.version, '--official-identity-request', request])};
  } catch (error) {
    result = {rc: error.code ?? null, signal: error.signal ?? null, stdout: error.stdout || '', stderr: error.stderr || ''};
    throw error;
  } finally {
    await atomicJson(path.join(root, 'private-official-publish.json'), result);
  }
  const copy = result.stdout.trim();
  assert.ok(path.isAbsolute(copy) && copy.startsWith(`${cache}${path.sep}`), 'publisher must return this fixture private copy');
  assert.equal((await fs.lstat(copy)).isSymbolicLink(), false);
  assert.equal(await fs.realpath(copy), copy);
  const lock = path.join(copy, 'SDK.lock.json');
  const privateSource = {...source, root: copy, lock, lockSha256: await fileDigest(lock),
    reason: 'authenticated owner-private official publisher copy for negative source tests'};
  await officialFixtureLock(privateSource);
  console.log(`PRIVATE_OFFICIAL_SOURCE_PUBLISHED rc=${result.rc} root=${copy} lock=${lock}`);
  return privateSource;
}

export function unavailableOfficialMutation(detail) {
  throw new Error(`SDK_FIXTURE_NOT_RUN: ${detail}; no legal non-target official archive input is retained. Preserve the target assertion and obtain its input contract before execution.`);
}
