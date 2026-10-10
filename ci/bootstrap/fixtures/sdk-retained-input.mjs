#!/usr/bin/env zx
// Admission of existing complete plans and original producer receipts. No
// production, publication, receipt rewriting or inferred SDK identity here.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {validatePlan, buildIdentities, readOutput, readJson, resolveFiles, fileDigest, atomicJson} from '../sdk-manifest.mjs';

export async function retainedSdkInput(planFile, role, label) {
  assert.ok(planFile, `${label}: a complete frozen plan is required; NOT_RUN`);
  const plan = validatePlan(await readJson(path.resolve(planFile)));
  assert.equal(plan.role, role, `${label}: preserve original runtime domain`);
  assert.equal(plan.platform, 'linux_x86_64');
  const identities = buildIdentities(plan), outputs = new Map();
  for (const component of plan.components) {
    const identity = identities.get(component.id);
    // readOutput authenticates DONE, original receipt bytes, frozen recipe,
    // source/tree and dependency IDs. Absence is an input failure, never SKIP.
    outputs.set(component.id, await readOutput(component.producer.receipt || identity.directory, component, identity));
  }
  const root = await fs.mkdtemp(path.join(process.env.SDK_MANIFEST_TEST_ROOT, `${label}-`));
  await atomicJson(path.join(root, 'input-identities.json'), Object.fromEntries([...outputs].map(([id, row]) =>
    [id, {directory: row.directory, receiptSha256: row.receiptSha256, buildId: row.buildId}])));
  return {root, plan, identities, outputs, files: resolveFiles(plan, outputs), planFile: path.join(root, 'plan.json'), out: path.join(root, 'sdk')};
}
export async function assertSelectedSdkBytes(f, runtimeSdk, stdSdk) {
  const tuple = 'linux_x86_64_cjnative';
  for (const [sdk, role, selected] of [[runtimeSdk, 'runtime', [`runtime/lib/${tuple}/libcangjie-runtime.so`,
    `runtime/lib/${tuple}/libboundscheck.so`, `lib/${tuple}/libcangjie-runtime.a`]],
  [stdSdk, 'std', Object.keys(f.files).filter(rel => /^(lib|runtime\/lib|modules)\//.test(rel)
    && (rel.includes('libcangjie-std-') || /FFI/.test(rel) || rel.startsWith('modules/')))]] ) {
    assert.ok(selected.length, `complete ${role} input members required`);
    const sourceManifest = await readJson(path.join(sdk, 'SDK.manifest.json'));
    const sourcePlan = await readJson(path.join(sdk, 'SDK.plan.json'));
    const sourceLock = await readJson(path.join(sdk, 'SDK.lock.json'));
    assert.equal(await fileDigest(path.join(sdk, 'SDK.manifest.json')), sourceLock.manifest_sha256);
    assert.equal(await fileDigest(path.join(sdk, 'SDK.plan.json')), sourceLock.plan_sha256);
    const owner = Object.values(f.files).find(row => f.plan.components.find(c => c.id === row.component)?.roles.includes(role));
    assert.ok(owner, `${role} must have an actual frozen producer`);
    for (const rel of selected) {
      const row = f.files[rel], original = sourceManifest.files[rel];
      assert.ok(row && original, `${role} member missing: ${rel}; NOT_RUN`);
      if (row.type === 'directory') continue;
      const actual = await fileDigest(path.join(sdk, rel));
      assert.equal(actual, original.sha256, `${sdk}: ${rel} original SDK bytes`);
      assert.equal(row.sha256, actual, `${rel}: supplied plan must select the requested real SDK entity`);
      const selectedComponent = f.plan.components.find(c => c.id === row.component);
      const originalComponent = sourcePlan.components.find(c => c.id === original.component);
      assert.deepEqual(selectedComponent.source, originalComponent.source, `${rel}: real producer source identity`);
      assert.equal(row.buildId, original.buildId, `${rel}: original producer build identity`);
      assert.equal(row.receiptSha256, original.receiptSha256, `${rel}: original producer receipt identity`);
    }
    if (role === 'std') {
      const wanted = Object.keys(sourceManifest.files).filter(rel => /^(lib|runtime\/lib|modules)\//.test(rel)
        && (rel.includes('libcangjie-std-') || /FFI/.test(rel) || rel.startsWith('modules/'))).sort();
      assert.deepEqual(selected.sort(), wanted, 'the real complete std set is retained, including modules and FFI');
    }
  }
}
