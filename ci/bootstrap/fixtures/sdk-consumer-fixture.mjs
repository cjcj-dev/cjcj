#!/usr/bin/env zx
// Consumers use the existing real producer fixture and the product CLI. This
// module never creates output receipts, DONE markers or installation locks.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {fixture, command} from './sdk-plan-fixture.mjs';
import {atomicJson, readJson, fileDigest, buildIdentities} from '../sdk-manifest.mjs';
import {officialFixtureRequest} from './sdk-official-fixture.mjs';

export const here = path.dirname(fileURLToPath(new URL('../sdk_build.sh', import.meta.url)));
export const tuple = 'linux_x86_64_cjnative';
export const cross = 'windows_x86_64_cjnative';
export {fixture, command, atomicJson, readJson, fileDigest};
export async function observe(f, label, argv) {
  const result = await command(argv);
  await atomicJson(path.join(f.root, `${label}.json`), {argv, ...result});
  console.log(`SDK_CONSUMER_OBSERVED ${label} rc=${result.rc} evidence=${f.root} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}
export async function assemble(f, label = 'assembly', product = process.env.SDK_BUILD_PRODUCT || path.join(here, 'sdk_build.sh')) {
  f.identities = buildIdentities(f.plan);
  await atomicJson(f.planFile, f.plan);
  return observe(f, label, ['bash', product, '--plan', f.planFile, '--to', f.out]);
}
export function good(result) { assert.equal(result.rc, 0, result.stdout + result.stderr); }
export function rejected(result, rule) {
  assert.equal(result.rc, 1, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, rule);
  assert.doesNotMatch(result.stdout + result.stderr, /FROZEN_PLAN_REQUIRED/);
}
export async function entries(f, expected) {
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  const receipt = await readJson(path.join(f.identities.get('compiler').directory, 'output.json'));
  for (const name of ['cjc', 'cjc-frontend']) {
    const entry = path.join(f.out, 'bin', name);
    assert.equal(await fs.readlink(entry), 'cjcj-stage1');
    assert.ok((await fs.realpath(entry)).startsWith(`${f.out}${path.sep}`));
    assert.equal(await fileDigest(entry), expected);
    assert.equal(manifest.files[`bin/${name}`].sha256, expected);
    assert.equal(manifest.files[`bin/${name}`].component, 'compiler');
  }
  assert.equal((await fs.lstat(path.join(f.out, 'bin/cjcj-stage1'))).isSymbolicLink(), false);
  assert.equal(receipt.files['bin/cjcj-stage1'].sha256, expected);
  return {manifest, receipt};
}
export async function nativeChecks(f, rel) {
  const binary = path.join(f.out, rel);
  const file = await observe(f, `${path.basename(rel)}-file`, ['file', '-bL', binary]); good(file);
  assert.match(file.stdout, /ELF/);
  const script = 'set -e; source "$1/envsetup.sh"; export LD_LIBRARY_PATH="$2${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; exec "${@:3}"';
  const run = argv => ['bash', '-c', script, 'sdk-consumer', f.out, f.plan.verification.hostRuntimeDir, ...argv];
  const load = await observe(f, `${path.basename(rel)}-ldd`, run(['ldd', binary])); good(load);
  assert.doesNotMatch(load.stdout + load.stderr, /not found/);
  const version = await observe(f, `${path.basename(rel)}-version`, run([binary, '--version'])); good(version);
  assert.ok(version.stdout.trim(), 'the actual version result must be observed');
  return {file, load, version};
}
export async function publish(f, source, label) {
  const original = f.plan.components.find(row => row.id === 'official').source;
  const request = path.join(f.root, `${label}-official-request.json`);
  await officialFixtureRequest(original, request);
  return observe(f, label, ['python3', process.env.SDK_SHAREDBUILD_ENGINE, '--remote', '--root',
    path.join(f.root, `${label}-cache`), '--lane', f.plan.lane, 'sdk-publish', '--source', source,
    '--version', original.version, '--official-identity-request', request]);
}
export async function retainPublished(f, source, label, mappings = []) {
  const result = await publish(f, source, label); good(result);
  const root = result.stdout.trim(), lock = path.join(root, 'SDK.lock.json');
  const official = f.plan.components.find(row => row.id === 'official');
  official.source = {...official.source, root, lock, lockSha256: await fileDigest(lock)};
  official.install.push(...mappings);
  return {root, lock: await readJson(lock)};
}
export async function verify(f, label = 'verify') {
  return observe(f, label, [process.execPath, '--input-type=module', '-e',
    'const {verifyManifestSdk}=await import(process.argv[2]); const fs=await import("node:fs/promises"); const sdk=process.argv[1]; await verifyManifestSdk(sdk,JSON.parse(await fs.readFile(sdk+"/SDK.plan.json")),JSON.parse(await fs.readFile(sdk+"/SDK.manifest.json")));',
    f.out, path.join(here, 'toolchain-sdk.mjs')]);
}
