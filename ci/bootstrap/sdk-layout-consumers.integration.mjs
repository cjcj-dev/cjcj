#!/usr/bin/env zx
// Exercise the consumers through their real entries, with original publisher
// locks and genuine small native producer receipts. Never reseal a mutation.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {fixture, command} from './fixtures/sdk-plan-fixture.mjs';
import {readJson, atomicJson, fileDigest} from './sdk-manifest.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const assemble = (f, args = []) => command(['bash', path.join(here, 'sdk_build.sh'), '--plan', f.planFile, '--to', f.out, ...args]);
async function observe(f, label, result) {
  await atomicJson(path.join(f.root, `${label}.json`), result);
  console.log(`CONSUMER_TARGET_ASSERT_REACHED ${label} rc=${result.rc} evidence=${f.root} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}

test('frozen official consumer rejects a changed source mode before sealing its copy', async () => {
  const f = await fixture(); const original = await observe(f, 'official-control', await assemble(f));
  assert.equal(original.rc, 0, original.stderr);
  const official = f.plan.components.find(row => row.id === 'official'), directory = f.identities.get('official').directory;
  const file = path.join(official.source.root, 'tools/bin/cjpm'), mode = (await fs.stat(file)).mode & 0o777;
  const lockSha = await fileDigest(official.source.lock);
  await fs.rename(directory, `${directory}-saved`); await fs.chmod(file, mode ^ 0o100);
  f.out = path.join(f.root, 'changed-mode-sdk');
  let bad;
  try {
    bad = await observe(f, 'official-mode-target', await assemble(f));
    assert.notEqual(bad.rc, 0, bad.stderr);
    assert.match(bad.stderr, /rule=DISTRIBUTION_FILE component=official size\/mode tools\/bin\/cjpm/);
    await assert.rejects(fs.access(f.out));
  } finally { await fs.chmod(file, mode); }
  assert.equal(await fileDigest(official.source.lock), lockSha);
  f.out = path.join(f.root, 'restored-mode-sdk');
  const restored = await observe(f, 'official-mode-restored', await assemble(f, ['--resume-failed'])); assert.equal(restored.rc, 0, restored.stderr);
});

test('real sharedbuild recipe consumes the complete sealed entity layout', async () => {
  const f = await fixture(); const original = await observe(f, 'recipe-control-assembly', await assemble(f));
  assert.equal(original.rc, 0, original.stderr);
  const runtime = f.identities.get('runtime').directory, recipe = path.join(runtime, 'sharedbuild-request.json');
  const spec = await readJson(recipe), sdk = spec.sdk, lockSha = await fileDigest(path.join(sdk, 'SDK.lock.json'));
  const call = label => command(['python3', process.env.SDK_SHAREDBUILD_ENGINE, '--remote', '--root',
    path.join(f.plan.buildRoot, 'shared-cache'), '--lane', f.plan.lane, 'build', '--recipe', recipe,
    '--work', path.join(f.plan.buildRoot, 'shared-work')]).then(result => observe(f, label, result));
  const normal = await call('recipe-control'); assert.equal(normal.rc, 0, normal.stderr);
  const file = path.join(sdk, 'tools/bin/cjpm'), bytes = await fs.readFile(file), fileMode = (await fs.stat(file)).mode & 0o777;
  const directory = path.join(sdk, 'tools'), dirMode = (await fs.stat(directory)).mode & 0o777;
  for (const kind of ['mode', 'directory-mode', 'extra-directory', 'missing', 'tamper', 'link']) {
    if (kind === 'mode') await fs.chmod(file, fileMode ^ 0o100);
    if (kind === 'directory-mode') await fs.chmod(directory, dirMode ^ 0o100);
    if (kind === 'extra-directory') await fs.mkdir(path.join(sdk, 'unsealed-empty-directory'));
    if (kind === 'missing') await fs.rename(file, `${file}-removed`);
    if (kind === 'tamper') { await fs.chmod(file, 0o755); const altered = Buffer.from(bytes); altered[0] ^= 1; await fs.writeFile(file, altered); await fs.chmod(file, fileMode); }
    if (kind === 'link') { await fs.rename(file, `${file}-removed`); await fs.symlink('cjpm-removed', file); }
    try {
      const bad = await call(`recipe-${kind}-target`); assert.equal(bad.rc, 1, bad.stderr);
      assert.match(bad.stderr, kind === 'mode' || kind === 'directory-mode' || kind === 'extra-directory'
        ? /SDK_LOCK_REJECT materialized membership\/type\/content\/mode/ : /SDK_MANIFEST_REJECT/);
    } finally {
      if (kind === 'link') await fs.unlink(file);
      if (kind === 'missing' || kind === 'link') await fs.rename(`${file}-removed`, file);
      if (kind === 'extra-directory') await fs.rmdir(path.join(sdk, 'unsealed-empty-directory'));
      if (kind === 'tamper') { await fs.chmod(file, 0o755); await fs.writeFile(file, bytes); }
      await fs.chmod(file, fileMode); await fs.chmod(directory, dirMode);
    }
    assert.equal(await fileDigest(path.join(sdk, 'SDK.lock.json')), lockSha);
    const restored = await call(`recipe-${kind}-restored`); assert.equal(restored.rc, 0, restored.stderr);
  }
});

test('independent sharedbuild directory mode target reaches the sealed layout consumer', async () => {
  const f = await fixture(); const assembled = await observe(f, 'independent-directory-control-assembly', await assemble(f));
  assert.equal(assembled.rc, 0, assembled.stderr);
  const recipe = path.join(f.identities.get('runtime').directory, 'sharedbuild-request.json');
  const sdk = (await readJson(recipe)).sdk, directory = path.join(sdk, 'tools');
  const mode = (await fs.stat(directory)).mode & 0o777, lock = path.join(sdk, 'SDK.lock.json'), originalLock = await fileDigest(lock);
  const invoke = label => command(['python3', process.env.SDK_SHAREDBUILD_ENGINE, '--remote', '--root',
    path.join(f.plan.buildRoot, 'shared-cache'), '--lane', f.plan.lane, 'build', '--recipe', recipe,
    '--work', path.join(f.plan.buildRoot, 'shared-work')]).then(result => observe(f, label, result));
  const control = await invoke('independent-directory-control'); assert.equal(control.rc, 0, control.stderr);
  await fs.chmod(directory, mode ^ 0o100);
  try {
    const target = await invoke('independent-directory-target');
    assert.equal(target.rc, 1, 'the actual recipe consumer must refuse changed directory permissions');
    assert.match(target.stderr, /SDK_LOCK_REJECT materialized membership\/type\/content\/mode/);
  } finally { await fs.chmod(directory, mode); }
  assert.equal(await fileDigest(lock), originalLock);
  const restored = await invoke('independent-directory-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
