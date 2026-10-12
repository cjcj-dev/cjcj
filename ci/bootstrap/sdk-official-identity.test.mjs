#!/usr/bin/env zx
// Small native fixture qualification only; no real official SDK receipt is minted.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileDigest, canonical, objectId, PLAN_SCHEMA, ROLES, buildIdentities, atomicJson} from './sdk-manifest.mjs';
import {officialIdentityVerifier} from '../../build/lib/official-sdk-identity.mjs';

const execute = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(await fs.readFile(process.env.SDK_IDENTITY_FIXTURE, 'utf8'));
const evidence = process.env.SDK_IDENTITY_EVIDENCE;
const engine = process.env.SDK_SHAREDBUILD_ENGINE;
const arm = process.env.SDK_IDENTITY_ARM || 'candidate';
assert.ok(evidence && engine && fixture.kind === 'synthetic-native-identity', 'private explicit fixture/evidence/engine required');
await fs.mkdir(evidence, {recursive: true});
const verifier = await officialIdentityVerifier();
async function command(label, argv) {
  let result;
  try { const row = await execute(argv[0], argv.slice(1), {maxBuffer: 4 * 1024 * 1024}); result = {rc: 0, ...row}; }
  catch (error) { result = {rc: error.code, stdout: error.stdout || '', stderr: error.stderr || '', signal: error.signal || null}; }
  await atomicJson(path.join(evidence, `${label}.json`), {argv, ...result});
  console.log(`TARGET_ASSERTION_EXECUTED ${label} rc=${result.rc} result=${path.join(evidence, `${label}.json`)} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}
const good = row => assert.equal(row.rc, 0, row.stderr);
const rejectIdentity = row => { assert.notEqual(row.rc, 0, `wrong identity accepted: ${row.stdout}`); assert.match(row.stderr, /OFFICIAL_IDENTITY|pinned archive identity/); };
async function publish(label, version, source = fixture.source) {
  const request = path.join(evidence, `${label}-request.json`);
  await atomicJson(request, {verifier, input: {archive: fixture.archive, platform: 'linux-x64', readonly: false, version: fixture.version}});
  return command(label, ['python3', engine, '--remote', '--root', path.join(evidence, 'cache'), '--lane', 'sdk927-fixture',
    'sdk-publish', '--source', source, '--version', version, '--official-identity-request', request]);
}
const stock = (await publish('fixture-publish-control', fixture.version));
good(stock);
const sdk = stock.stdout.trim();
const sourceLock = await fs.readFile(path.join(sdk, 'SDK.lock.json'));
const sourceCjc = await fileDigest(path.join(fixture.source, 'bin/cjc'));
function plan(root, lock, version, label) {
  const component = {id: 'official', roles: [...ROLES], domain: 'host', source: {kind: 'distribution', root, lock,
    lockSha256: '', version, reason: 'explicit small native archive fixture; not official SDK qualification'},
    config: {host: 'linux_x86_64', target: 'linux_x86_64', options: {}, tools: {}},
    producer: {adapter: 'official', version: fixture.productSha}, dependencies: [], install: [{from: '', to: ''}]};
  return {schema: PLAN_SCHEMA, lane: 'sdk927-fixture', role: 'host', stage: 'seed', platform: 'linux_x86_64',
    buildRoot: path.join(evidence, label), verification: fixture.verification, components: [component]};
}
async function resolve(label, p) {
  p.components[0].source.lockSha256 = await fileDigest(p.components[0].source.lock);
  const file = path.join(evidence, `${label}-plan.json`); await atomicJson(file, p);
  return command(label, [process.execPath, '--input-type=module', '-e',
    `import fs from 'node:fs/promises'; import {resolvePlan} from ${JSON.stringify(path.join(here, 'toolchain-sdk.mjs'))}; const m=await resolvePlan(JSON.parse(await fs.readFile(process.argv[1],'utf8'))); console.log(JSON.stringify({status:m.status,rc:m.rc,proof:m.components.official.execution.officialIdentity,files:m.files}));`, file]);
}
async function build(label, sdkRoot) {
  const recipe = {...fixture.recipe, sdk: sdkRoot, sdkIdentityVerifier: verifier};
  const file = path.join(evidence, `${label}-recipe.json`); await atomicJson(file, recipe);
  return command(label, ['python3', engine, '--remote', '--root', path.join(evidence, 'build-cache'), '--lane', 'sdk927-fixture',
    'build', '--recipe', file, '--work', path.join(evidence, 'work')]);
}
test('publisher rejects only a conflicting request tag before naming or successful sealing', async () => {
  good(await publish('publisher-fresh-control', fixture.version));
  good(await publish('publisher-cache-control', fixture.version));
  const alias = await publish('publisher-legitimate-nightly-alias', `nightly-${fixture.version}`); good(alias);
  good(await build('recipe-legitimate-nightly-alias', alias.stdout.trim()));
  good(await resolve('resolver-legitimate-nightly-alias', plan(alias.stdout.trim(), path.join(alias.stdout.trim(), 'SDK.lock.json'), `nightly-${fixture.version}`, 'resolve-legitimate-alias')));
  assert.equal(await fileDigest(path.join(fixture.source, 'bin/cjc')), sourceCjc);
  const bad = await publish('publisher-wrong-tag', fixture.wrongVersion);
  const badAlias = await publish('publisher-wrong-nightly-alias', `nightly-${fixture.wrongVersion}`);
  console.log(`TARGET_ASSERTION_EXECUTED publisher-reject-tags rc=${bad.rc},${badAlias.rc}`);
  assert.deepEqual([bad, badAlias].map(row => row.rc !== 0), [true, true], 'conflicting exact and nightly alias tags were accepted');
  for (const row of [bad, badAlias]) rejectIdentity(row);
});
test('ordinary recipe consumption rejects a self-consistent wrong tagged marked and legacy seal', async () => {
  const normal = await build('recipe-fresh-control', sdk); good(normal);
  good(await build('recipe-cache-control', sdk));
  const legacyRoot = path.join(evidence, 'valid-legacy'); await fs.cp(sdk, legacyRoot, {recursive: true});
  const legacyLock = JSON.parse(sourceLock); delete legacyLock.layoutVersion; delete legacyLock.source_layout;
  legacyLock.distribution_sha256 = objectId({version: legacyLock.version, files: Object.fromEntries(Object.entries(legacyLock.files).map(([rel, row]) => [rel, row.sha256])), officialIdentity: legacyLock.officialIdentity});
  await fs.chmod(path.join(legacyRoot, 'SDK.lock.json'), 0o644); await atomicJson(path.join(legacyRoot, 'SDK.lock.json'), legacyLock);
  good(await command('seal-valid-legacy', ['python3', '-c', 'import importlib.util,pathlib,sys;s=importlib.util.spec_from_file_location("sb",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.seal(pathlib.Path(sys.argv[2]))', engine, legacyRoot]));
  good(await build('recipe-valid-legacy-control', legacyRoot));
  good(await resolve('resolver-valid-legacy-control', plan(legacyRoot, path.join(legacyRoot, 'SDK.lock.json'), fixture.version, 'resolve-valid-legacy')));
  const wrongResults = [];
  for (const layout of ['marked', 'legacy']) {
    const root = path.join(evidence, `wrong-${layout}`); await fs.cp(sdk, root, {recursive: true});
    const lock = JSON.parse(sourceLock); lock.version = fixture.wrongVersion;
    if (layout === 'legacy') { delete lock.layoutVersion; delete lock.source_layout; }
    const files = Object.fromEntries(Object.entries(lock.files).map(([rel, row]) => [rel, row.sha256]));
    lock.distribution_sha256 = objectId({version: lock.version, files, ...(lock.source_layout ? {source_layout: lock.source_layout} : {}), officialIdentity: lock.officialIdentity});
    await fs.chmod(path.join(root, 'SDK.lock.json'), 0o644); await atomicJson(path.join(root, 'SDK.lock.json'), lock);
    good(await command(`seal-${layout}`, ['python3', '-c',
      'import importlib.util,pathlib,sys;s=importlib.util.spec_from_file_location("sb",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.seal(pathlib.Path(sys.argv[2]))', engine, root]));
    const result = await build(`recipe-wrong-${layout}`, root); wrongResults.push(result);
  }
  console.log(`TARGET_ASSERTION_EXECUTED recipe-reject-marked-and-legacy rc=${wrongResults.map(row => row.rc).join(',')}`);
  assert.deepEqual(wrongResults.map(row => row.rc !== 0), [true, true], 'ordinary recipe accepted wrong marked/legacy identity');
  for (const row of wrongResults) rejectIdentity(row);
});
test('resolver fresh official producer rejects wrong label before producing a successful receipt', async () => {
  const p = plan(sdk, path.join(sdk, 'SDK.lock.json'), fixture.version, 'resolve-fresh');
  const normal = await resolve('resolve-fresh-control', p); good(normal);
  const actual = JSON.parse(normal.stdout.trim().split('\n').at(-1));
  assert.equal(actual.proof.compiler.version, fixture.version);
  assert.equal(actual.files['bin/cjc'].sha256, sourceCjc);
  assert.equal(actual.files['include/member.h'].sha256, actual.files['lib/member.h'].sha256);
  assert.equal(actual.files['lib/empty'].mode, 0o750 & ~0o222);
  assert.equal(actual.files['include/empty'].type, 'directory');
  console.log('NON_CUT_CONTROLS_EXECUTED compiler-bytes alias-bytes directory-type readonly-mode');
  const wrongLock = path.join(evidence, 'fresh-wrong.lock.json');
  const lock = JSON.parse(sourceLock); lock.version = fixture.wrongVersion;
  await atomicJson(wrongLock, lock);
  const wrong = plan(sdk, wrongLock, fixture.wrongVersion, 'resolve-wrong');
  const result = await resolve('resolve-wrong-tag', wrong);
  const identity = buildIdentities(wrong).get('official');
  let receipt;
  try { receipt = JSON.parse(await fs.readFile(path.join(identity.directory, 'output.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  console.log(`TARGET_ASSERTION_EXECUTED producer-no-success-receipt status=${receipt?.status || 'absent'} rc=${result.rc}`);
  assert.notEqual(receipt?.status, 'complete', 'wrong tag was sealed as a successful producer record');
  rejectIdentity(result);
});
test('resolver cache and original prior-receipt admission reject missing proof without altering history', async () => {
  // This is an actual receipt emitted by the frozen pre-fix product during
  // preparation, not a handwritten success record or an amended old receipt.
  const p = JSON.parse(await fs.readFile(fixture.legacyPlan, 'utf8'));
  const directory = buildIdentities(p).get('official').directory;
  const before = await fs.readFile(path.join(directory, 'output.json'));
  const done = await fs.readFile(path.join(directory, 'DONE'));
  const stat = await fs.stat(path.join(directory, 'output.json'));
  const normal = plan(sdk, path.join(sdk, 'SDK.lock.json'), fixture.version, 'resolve-fresh');
  good(await resolve('resolver-new-cache-control', normal));
  const result = await resolve('resolver-legacy-cache-missing-proof', p);
  const component = p.components[0], identity = buildIdentities(p).get('official');
  component.producer = {...component.producer, receipt: directory, receiptSha256: done.toString().trim(), originBuildRoot: p.buildRoot};
  const prior = await resolve('resolver-legacy-prior-missing-proof', p);
  console.log(`TARGET_ASSERTION_EXECUTED resolver-reject-cache-and-prior rc=${result.rc},${prior.rc}`);
  assert.deepEqual([result, prior].map(row => row.rc !== 0), [true, true], 'resolver accepted original successful cache/prior receipt without source proof');
  for (const row of [result, prior]) rejectIdentity(row);
  assert.deepEqual(await fs.readFile(path.join(directory, 'output.json')), before);
  assert.equal((await fs.stat(path.join(directory, 'output.json'))).mtimeMs, stat.mtimeMs);
  assert.deepEqual(await fs.readFile(path.join(directory, 'DONE')), done);
});
