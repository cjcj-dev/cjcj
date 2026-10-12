#!/usr/bin/env zx
// Requires an authenticated real official source/archive; never provisions it.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {buildIdentities, fileDigest, atomicJson} from './sdk-manifest.mjs';

const run = promisify(execFile);
const root = process.env.SDK_PRESEAL_ROOT;
const input = process.env.SDK_PRESEAL_PLAN;
const arm = process.env.SDK_PRESEAL_ARM || 'normal';
assert.ok(root && path.isAbsolute(root) && input && path.isAbsolute(input), 'explicit private root and authenticated plan required');
const evidence = path.join(root, 'evidence', arm);
await fs.mkdir(evidence, {recursive: true});
const template = JSON.parse(await fs.readFile(input));
assert.equal(template.components.length, 1);
const source = template.components[0].source;
const before = {sha256: await fileDigest(source.lock), mtimeMs: (await fs.stat(source.lock)).mtimeMs};
assert.equal(before.sha256, source.lockSha256);
const lock = JSON.parse(await fs.readFile(source.lock));
assert.ok(Object.keys(lock.files).length > 1 && lock.files['bin/cjc'] && lock.officialIdentity);
const legacy = structuredClone(lock);
delete legacy.layoutVersion;
delete legacy.source_layout;
const declarations = path.join(root, 'declarations');
await fs.mkdir(declarations, {recursive: true});
// Stable declarations permit genuine cache/prior controls across causal arms.
async function declaration(name, value) {
  const file = path.join(declarations, name);
  try { assert.deepEqual(JSON.parse(await fs.readFile(file)), value); }
  catch (error) { if (error.code !== 'ENOENT') throw error; await atomicJson(file, value); }
  return file;
}
const completeLock = await declaration('complete-legacy.lock.json', legacy);
const partialLock = await declaration('incomplete-legacy.lock.json', {...legacy, files: {'bin/cjc': legacy.files['bin/cjc']}});
async function plan(lockFile, buildRoot) {
  const p = structuredClone(template);
  p.lane = path.basename(root);
  p.buildRoot = buildRoot;
  p.components[0].source.lock = lockFile;
  p.components[0].source.lockSha256 = await fileDigest(lockFile);
  return p;
}
const module = fileURLToPath(new URL('./toolchain-sdk.mjs', import.meta.url));
async function resolve(label, p) {
  const file = path.join(evidence, label + '.plan.json');
  await atomicJson(file, p);
  const argv = [process.execPath, '--input-type=module', '-e',
    `import fs from 'node:fs/promises';import {resolvePlan} from ${JSON.stringify(module)};console.log(JSON.stringify(await resolvePlan(JSON.parse(await fs.readFile(process.argv[1])))));`, file];
  let result;
  try { result = {rc: 0, ...await run(argv[0], argv.slice(1), {maxBuffer: 12 * 1024 * 1024})}; }
  catch (error) { result = {rc: error.code, signal: error.signal || null, stdout: error.stdout || '', stderr: error.stderr || ''}; }
  await atomicJson(path.join(evidence, label + '.product.json'), {argv, ...result});
  console.log(`PRODUCT_RESULT ${label} rc=${result.rc}`);
  return result;
}
async function optional(file, json = false) {
  try { const bytes = await fs.readFile(file, 'utf8'); return json ? JSON.parse(bytes) : bytes.trim(); }
  catch (error) { if (error.code !== 'ENOENT') throw error; return null; }
}
let controlsPassed = false;
test('complete real legacy payload succeeds through fresh/cache/prior and marked cache', async () => {
  const p = await plan(completeLock, path.join(root, 'complete-legacy'));
  for (const label of ['legacy-fresh-or-cache', 'legacy-cache']) {
    const result = await resolve(label, p);
    assert.equal(result.rc, 0, result.stderr);
    const manifest = JSON.parse(result.stdout.trim().split('\n').at(-1));
    assert.equal(manifest.files['bin/cjc'].sha256, lock.officialIdentity.compiler.sha256);
    assert.equal(manifest.components.official.status, 'complete');
    assert.deepEqual(manifest.components.official.execution.officialIdentity, lock.officialIdentity);
    assert.ok(manifest.files.LICENSE && Object.keys(manifest.files).length > Object.keys(lock.files).length);
  }
  const id = buildIdentities(p).get('official');
  const prior = structuredClone(p);
  prior.components[0].producer = {...prior.components[0].producer, receipt: id.directory,
    receiptSha256: await optional(path.join(id.directory, 'DONE')), originBuildRoot: p.buildRoot};
  const admitted = await resolve('legacy-prior', prior);
  assert.equal(admitted.rc, 0, admitted.stderr);
  // Existing complete marked receipt is read-only; this calls the new tree's
  // independent consumer without making another full SDK copy.
  const marked = await resolve('marked-cache', template);
  assert.equal(marked.rc, 0, marked.stderr);
  controlsPassed = true;
  console.log('NON_CUT_CONTROLS_PASSED complete-legacy compiler-original-bytes proof LICENSE cache prior marked-cache');
});
test('incomplete real legacy copy fails before any successful receipt or DONE', async (t) => {
  if (!controlsPassed) { t.skip('positive product failure; dependent negative not run'); return; }
  const p = await plan(partialLock, path.join(root, 'incomplete-' + arm));
  const result = await resolve('incomplete-legacy', p);
  const id = buildIdentities(p).get('official');
  const output = await optional(path.join(id.directory, 'output.json'), true);
  const done = await optional(path.join(id.directory, 'DONE'));
  const state = await optional(path.join(id.directory, 'state.json'), true);
  const after = {sha256: await fileDigest(source.lock), mtimeMs: (await fs.stat(source.lock)).mtimeMs};
  const observed = {productRc: result.rc, outputStatus: output?.status || 'absent', outputRc: output?.rc ?? null,
    done, doneAuthenticatesOutput: output !== null && done === await fileDigest(path.join(id.directory, 'output.json')),
    stateStatus: state?.status, stateError: state?.error, directory: id.directory, sourceLockBefore: before, sourceLockAfter: after,
    productFiles: Object.fromEntries(await Promise.all(['sdk-producers.mjs', 'sdk-manifest.mjs', 'toolchain-sdk.mjs'].map(async name =>
      [name, await fileDigest(fileURLToPath(new URL(name, import.meta.url)))])))};
  await atomicJson(path.join(evidence, 'observed.json'), observed);
  // Rejection itself also holds with the cut: it must not mask the seal-order assertion.
  assert.notEqual(result.rc, 0, 'incomplete SDK returned success');
  assert.match(result.stderr, /official archive payload mismatch: LICENSE/);
  assert.equal(await fileDigest(path.join(id.directory, 'artifacts/bin/cjc')), lock.officialIdentity.compiler.sha256);
  console.log('TARGET_ASSERTION_EXECUTED no-incomplete-success-receipt ' + JSON.stringify(observed));
  assert.notEqual(output?.status, 'complete', 'incomplete legacy payload was sealed as status=complete/rc=0 before archive rejection');
  assert.equal(output, null, 'failed copy must not publish output.json');
  assert.equal(done, null, 'failed copy must not publish DONE');
  assert.equal(state?.status, 'failed');
  assert.deepEqual(after, before, 'original source lock mutated');
});
