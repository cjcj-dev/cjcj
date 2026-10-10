#!/usr/bin/env zx
// Actual publisher, frozen SDK CLI, original receipts and both SDK verifiers.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {fixture, command} from './fixtures/sdk-plan-fixture.mjs';
import {atomicJson, readJson, fileDigest, buildIdentities} from './sdk-manifest.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
async function observe(f, label, result) {
  await atomicJson(path.join(f.root, `${label}.json`), result);
  console.log(`DIRECTORY_CLOSURE_ASSERT_REACHED ${label} rc=${result.rc} evidence=${f.root} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}
async function directoryFixture() {
  const f = await fixture(), source = path.join(f.root, 'directory-input');
  await fs.cp(path.join(f.root, 'official'), source, {recursive: true});
  await fs.mkdir(path.join(source, 'tools/empty/leaf'), {recursive: true});
  await fs.chmod(path.join(source, 'tools/empty'), 0o750);
  await fs.chmod(path.join(source, 'tools/empty/leaf'), 0o751);
  const published = await observe(f, 'publisher', await command(['python3', process.env.SDK_SHAREDBUILD_ENGINE,
    '--remote', '--root', path.join(f.root, 'directory-cache'), '--lane', f.plan.lane,
    'sdk-publish', '--source', source, '--version', 'directory-closure']));
  assert.equal(published.rc, 0, published.stderr);
  const root = published.stdout.trim(), lock = path.join(root, 'SDK.lock.json');
  const official = f.plan.components.find(row => row.id === 'official');
  official.source = {...official.source, root, lock, version: 'directory-closure', lockSha256: await fileDigest(lock)};
  f.identities = buildIdentities(f.plan);
  await atomicJson(f.planFile, f.plan);
  return {...f, source, depot: root};
}
const assemble = (f, args = []) => command(['bash', path.join(here, 'sdk_build.sh'), '--plan', f.planFile, '--to', f.out, ...args]);
async function verify(f, kind, label) {
  const argv = kind === 'python' ? ['python3', '-B', path.join(here, 'sdk_verify.py'), '--sdk', f.out,
    '--runtime-pin', f.plan.verification.runtimePin.path, '--target-tuple', 'linux_x86_64_cjnative'] :
    [process.execPath, '--input-type=module', '-e',
      'const {verifyManifestSdk}=await import(process.argv[2]); const fs=await import("node:fs/promises"); const sdk=process.argv[1]; await verifyManifestSdk(sdk,JSON.parse(await fs.readFile(sdk+"/SDK.plan.json")),JSON.parse(await fs.readFile(sdk+"/SDK.manifest.json")));',
      f.out, path.join(here, 'toolchain-sdk.mjs')];
  return observe(f, `${label}-${kind}`, await command(argv));
}

test('real final SDK preserves authenticated empty directories and readonly source modes', async () => {
  const existing = process.env.SDK_DIRECTORY_EXISTING;
  const plan = existing ? await readJson(path.join(existing, 'plan.json')) : null;
  const f = existing ? {root: existing, out: path.join(existing, 'sdk'), plan, identities: buildIdentities(plan),
    depot: plan.components.find(row => row.id === 'official').source.root} : await directoryFixture();
  const result = existing ? await readJson(path.join(existing, 'final-assembly.json')) : await observe(f, 'final-assembly', await assemble(f));
  if (existing) console.log(`REUSED_COMPLETED_ASSEMBLY evidence=${existing} rc=${result.rc}`);
  assert.equal(result.rc, 0, result.stderr);
  const depotLock = await readJson(path.join(f.depot, 'SDK.lock.json'));
  const receipt = await readJson(path.join(f.identities.get('official').directory, 'output.json'));
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  const lock = await readJson(path.join(f.out, 'SDK.lock.json'));
  for (const [rel, sourceMode] of [['tools/empty', 0o750], ['tools/empty/leaf', 0o751]]) {
    const expectedMode = sourceMode & ~0o222;
    const row = {rel, source: depotLock.source_layout[rel], receipt: receipt.files[rel], manifest: manifest.files[rel], lock: lock.files[rel],
      mode: (await fs.stat(path.join(f.out, rel))).mode & 0o777};
    console.log(`DIRECTORY_PROVENANCE_ASSERT_REACHED ${JSON.stringify(row)}`);
    assert.equal(row.source.mode, sourceMode);
    for (const entry of [row.receipt, row.manifest, row.lock]) {
      assert.equal(entry.type, 'directory'); assert.equal(entry.sha256, null); assert.equal(entry.mode, expectedMode);
    }
    assert.equal(row.receipt.sourceMode, sourceMode); assert.equal(row.receipt.modeTransform, 'readonly');
    assert.equal(row.lock.source_mode, sourceMode); assert.equal(row.lock.mode_transform, 'readonly');
    assert.equal(row.mode, expectedMode);
  }
  assert.deepEqual(lock.files['tools/empty'].members, ['tools/empty/leaf']);
  assert.deepEqual(lock.files['tools/empty/leaf'].members, []);
  for (const kind of (existing ? ['esm'] : ['python', 'esm'])) assert.equal((await verify(f, kind, 'normal')).rc, 0);
  const originalLock = await fileDigest(path.join(f.out, 'SDK.lock.json'));
  for (const mutation of ['mode', 'extra', 'missing']) {
    const dir = path.join(f.out, 'tools/empty'), leaf = path.join(dir, 'leaf');
    if (mutation === 'mode') await fs.chmod(dir, 0o450);
    if (mutation === 'extra') await fs.mkdir(path.join(dir, 'extra'));
    if (mutation === 'missing') await fs.rmdir(leaf);
    try {
      for (const kind of ['python', 'esm']) {
        const bad = await verify(f, kind, `${mutation}-target`);
        assert.equal(bad.rc, 1, `${mutation}/${kind} must reject without resealing`);
        assert.match(bad.stderr, /PAYLOAD_MODE|PAYLOAD_MEMBERS|UNDECLARED|ENOENT/);
      }
    } finally {
      if (mutation === 'mode') await fs.chmod(dir, 0o550);
      if (mutation === 'extra') await fs.rmdir(path.join(dir, 'extra'));
      if (mutation === 'missing') { await fs.mkdir(leaf); await fs.chmod(leaf, 0o551); }
    }
    assert.equal(await fileDigest(path.join(f.out, 'SDK.lock.json')), originalLock);
    for (const kind of ['python', 'esm']) assert.equal((await verify(f, kind, `${mutation}-restored`)).rc, 0);
  }
});

test('official directory source mode change is refused before a receipt is sealed', async () => {
  const f = await directoryFixture(), dir = path.join(f.depot, 'tools/empty');
  const lockSha = await fileDigest(path.join(f.depot, 'SDK.lock.json'));
  await fs.chmod(dir, 0o450);
  try {
    const result = await observe(f, 'official-directory-mode-target', await assemble(f));
    assert.equal(result.rc, 1, 'frozen source directory mode must be consumed');
    assert.match(result.stderr, /rule=DISTRIBUTION_LAYOUT/);
    await assert.rejects(fs.access(path.join(f.identities.get('official').directory, 'output.json')));
  } finally { await fs.chmod(dir, 0o550); }
  assert.equal(await fileDigest(path.join(f.depot, 'SDK.lock.json')), lockSha);
  const restored = await observe(f, 'official-directory-mode-restored', await assemble(f, ['--resume-failed']));
  assert.equal(restored.rc, 0, restored.stderr);
});

test('ordinary final SDK remains the independent control', async () => {
  const f = await fixture(), result = await observe(f, 'ordinary-final-control', await assemble(f));
  assert.equal(result.rc, 0, result.stderr);
});
