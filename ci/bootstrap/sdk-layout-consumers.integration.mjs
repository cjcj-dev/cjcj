#!/usr/bin/env zx
// Exercise the consumers through their real entries, with original publisher
// locks and genuine small native producer receipts. Never reseal a mutation.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {fixture, command} from './fixtures/sdk-plan-fixture.mjs';
import {readJson, atomicJson, fileDigest, canonical, objectId, sha256} from './sdk-manifest.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const assemble = (f, args = []) => command(['bash', path.join(here, 'sdk_build.sh'), '--plan', f.planFile, '--to', f.out, ...args]);
async function observe(f, label, result) {
  await atomicJson(path.join(f.root, `${label}.json`), result);
  console.log(`CONSUMER_TARGET_ASSERT_REACHED ${label} rc=${result.rc} evidence=${f.root} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}

async function recipeInput(label) {
  const f = await fixture();
  const assembled = await observe(f, `${label}-qualification`, await assemble(f));
  assert.equal(assembled.rc, 0, `RECIPE_INPUT_QUALIFICATION ${assembled.stderr}`);
  const recipe = await readJson(path.join(f.identities.get('runtime').directory, 'sharedbuild-request.json'));
  return {...f, recipe};
}
async function consumeSdk(f, sdk, label) {
  const recipe = path.join(f.root, `${label}-recipe.json`);
  // This is a new public CLI request, not a changed frozen component plan or
  // a rewritten successful output receipt. The original recipe is retained.
  await atomicJson(recipe, {...f.recipe, sdk});
  return observe(f, label, await command(['python3', process.env.SDK_SHAREDBUILD_ENGINE,
    '--remote', '--root', path.join(f.root, `${label}-cache`), '--lane', f.plan.lane,
    'build', '--recipe', recipe, '--work', path.join(f.root, `${label}-work`)]));
}
async function historicalSdk(f, marked, label) {
  const sdk = path.join(f.root, label), original = await readJson(path.join(f.recipe.sdk, 'SDK.lock.json'));
  await fs.mkdir(sdk);
  const files = Object.fromEntries(Object.entries(original.files).map(([rel, row]) => [rel, {sha256: row.sha256}]));
  for (const rel of Object.keys(files)) {
    await fs.mkdir(path.dirname(path.join(sdk, rel)), {recursive: true});
    await fs.copyFile(path.join(f.recipe.sdk, rel), path.join(sdk, rel));
    await fs.chmod(path.join(sdk, rel), (await fs.stat(path.join(f.recipe.sdk, rel))).mode & 0o777);
  }
  const distribution = {version: 'historical-file-only', files: Object.fromEntries(Object.entries(files).map(([rel, row]) => [rel, row.sha256]))};
  // Standalone historical-format distribution input, authored before it is
  // consumed. No output.json, execution record or successful producer receipt
  // is created. SDK DONE authenticates this input's metadata bytes only.
  const lock = {schema: 'sharedbuild-official-sdk-v1', role: 'host', version: distribution.version,
    distribution_sha256: objectId(distribution), files, ...(marked ? {layoutVersion: 1} : {})};
  await fs.writeFile(path.join(sdk, 'SDK.lock.json'), canonical(lock));
  const inventory = {...distribution.files, 'SDK.lock.json': await fileDigest(path.join(sdk, 'SDK.lock.json'))};
  const manifest = Object.keys(inventory).sort().map(rel => `${inventory[rel]}  ${rel}\n`).join('');
  await fs.writeFile(path.join(sdk, 'MANIFEST.sha256'), manifest);
  await fs.writeFile(path.join(sdk, 'DONE'), `${sha256(manifest)}\n`);
  return sdk;
}

test('marked SDK without source layout reaches the public recipe consumer rejection', async () => {
  const f = await recipeInput('marker'), sdk = await historicalSdk(f, true, 'marked-no-layout');
  const before = await fs.readFile(path.join(sdk, 'SDK.lock.json'));
  const result = await consumeSdk(f, sdk, 'marked-no-layout-target');
  console.log(`TARGET_ASSERTION_BEGIN source-layout-marker rc=${result.rc} stderr=${JSON.stringify(result.stderr)}`);
  assert.deepEqual({rc: result.rc, diagnostics: result.stderr.split('\n').filter(line => line.startsWith('ERROR:'))},
    {rc: 1, diagnostics: ['ERROR: SDK_LOCK_REJECT missing source layout']},
    'source-layout-marker: real CLI must reject specifically at the marked layout obligation');
  console.log('TARGET_ASSERTION_PASS source-layout-marker');
  assert.deepEqual(await fs.readFile(path.join(sdk, 'SDK.lock.json')), before);
});

test('historical unmarked file-only SDK remains a legal public recipe consumer control', async () => {
  const f = await recipeInput('historical'), sdk = await historicalSdk(f, false, 'unmarked-file-only');
  const before = await fs.readFile(path.join(sdk, 'SDK.lock.json'));
  const result = await consumeSdk(f, sdk, 'unmarked-file-only-control');
  console.log(`TARGET_ASSERTION_BEGIN historical-file-only-control rc=${result.rc}`);
  assert.equal(result.rc, 0, result.stderr);
  console.log('TARGET_ASSERTION_PASS historical-file-only-control');
  assert.deepEqual(await fs.readFile(path.join(sdk, 'SDK.lock.json')), before);
});

test('publisher reserved metadata remains excluded in the public recipe consumer control', async () => {
  const f = await recipeInput('reserved-metadata'), source = path.join(f.root, 'retained-metadata-source');
  await fs.cp(path.join(f.root, 'official'), source, {recursive: true});
  for (const name of ['SDK.lock.json', 'MANIFEST.sha256', 'DONE']) await fs.writeFile(path.join(source, name), `retained input ${name}\n`);
  const published = await observe(f, 'reserved-metadata-publisher', await command(['python3', process.env.SDK_SHAREDBUILD_ENGINE,
    '--remote', '--root', path.join(f.root, 'reserved-metadata-depot'), '--lane', f.plan.lane,
    'sdk-publish', '--source', source, '--version', 'reserved-metadata-control']));
  assert.equal(published.rc, 0, published.stderr);
  const sdk = published.stdout.trim(), lock = await readJson(path.join(sdk, 'SDK.lock.json'));
  const result = await consumeSdk(f, sdk, 'reserved-metadata-consumer-control');
  console.log(`TARGET_ASSERTION_BEGIN reserved-metadata-control rc=${result.rc}`);
  assert.equal(result.rc, 0, result.stderr);
  assert.equal(lock.layoutVersion, 1); assert.ok(lock.source_layout);
  for (const name of ['SDK.lock.json', 'MANIFEST.sha256', 'DONE']) {
    assert.equal(Object.hasOwn(lock.files, name), false);
    assert.equal(Object.hasOwn(lock.source_layout, name), false);
  }
  console.log('TARGET_ASSERTION_PASS reserved-metadata-control');
});

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
