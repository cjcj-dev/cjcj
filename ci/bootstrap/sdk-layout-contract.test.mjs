#!/usr/bin/env zx
// Real CLI contracts. No validator reimplementation, rewritten lock, or test
// hook in either product. Inputs and product results remain in the lane.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {command} from './fixtures/sdk-plan-fixture.mjs';
import {fileDigest, readJson, atomicJson} from './sdk-manifest.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.env.SDK_MANIFEST_TEST_ROOT;
const engine = process.env.SDK_SHAREDBUILD_ENGINE;
const verifier = process.env.SDK_VERIFY_PRODUCT || path.join(here, 'sdk_verify.py');
assert.ok(root && engine, 'explicit private root and fixed sharedbuild engine required');
const write = async (file, bytes) => { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, bytes); };
async function input(label) {
  const work = await fs.mkdtemp(path.join(root, `${label}-`)), source = path.join(work, 'source');
  await write(path.join(source, 'bin/cjc'), 'small compiler input\n');
  await fs.chmod(path.join(source, 'bin/cjc'), 0o755);
  await write(path.join(source, 'lib/member.h'), 'authenticated header\n');
  await fs.mkdir(path.join(source, 'lib/empty'));
  return {work, source, cache: path.join(work, 'cache'), sdk: path.join(work, 'sdk')};
}
async function observe(f, label, result) {
  await atomicJson(path.join(f.work, `${label}.json`), result);
  console.log(`TARGET_ASSERTION_EXECUTED ${label} rc=${result.rc} evidence=${f.work} stdout=${JSON.stringify(result.stdout)} stderr=${JSON.stringify(result.stderr)}`);
  return result;
}
async function legacy(f, label, create = false) {
  return observe(f, label, await command(['python3', verifier, '--sdk', f.sdk, '--role', 'host',
    ...(create ? ['--write-lock', '--from', f.source] : [])]));
}
async function publisher(f, label) {
  return observe(f, label, await command(['python3', engine, '--remote', '--root', f.cache,
    '--lane', 'sym_cjcj_934_implement_r6098289478', 'sdk-publish', '--source', f.source, '--version', 'layout-test']));
}
const good = result => assert.equal(result.rc, 0, result.stderr);
function rejected(result, rule, rel) {
  assert.equal(result.rc, 1, result.stdout + result.stderr);
  assert.ok(result.stderr.split('\n').some(line => line.includes(`rule=${rule} `) && line.includes(rel)), result.stderr);
}
async function legacyInput(label, target = 'lib') {
  const f = await input(label);
  await fs.symlink(target, path.join(f.source, 'include'));
  await fs.cp(f.source, f.sdk, {recursive: true, verbatimSymlinks: true});
  return f;
}

// Verbatim retained R2 lock from Review6098747736/raw-inputs/legacy-lock.json.
// Its original payload bytes are recorded in that review's layout-gaps.mjs.
// Never call --write-lock or fill in modes on this retained input.
async function historicalPayload(label) {
  const work = await fs.mkdtemp(path.join(root, `${label}-`)), sdk = path.join(work, 'sdk');
  await write(path.join(sdk, 'bin/cjc'), 'small fixture compiler input\n');
  await fs.chmod(path.join(sdk, 'bin/cjc'), 0o755);
  await write(path.join(sdk, 'lib/member.h'), 'frozen header\n');
  await fs.mkdir(path.join(sdk, 'lib/empty'));
  for (const rel of ['lib', 'lib/empty']) await fs.chmod(path.join(sdk, rel), 0o755);
  return {work, sdk};
}
async function retainedLegacyInput(label) {
  const f = await historicalPayload(label);
  await fs.symlink('lib', path.join(f.sdk, 'include'));
  const lockBytes = await fs.readFile(path.join(here, 'fixtures/sdk-legacy-directory-lock.json'));
  await fs.writeFile(path.join(f.sdk, 'SDK.lock.json'), lockBytes);
  return {...f, lockBytes};
}

test('retained v1 typed-directory lock without mode is rejected directly and stays unchanged', async () => {
  const f = await retainedLegacyInput('retained-directory-no-mode');
  for (const [label, mode] of [['original', 0o755], ['changed', 0o655], ['restored', 0o755]]) {
    await fs.chmod(path.join(f.sdk, 'lib'), mode);
    const result = await legacy(f, `retained-no-mode-${label}`);
    rejected(result, 'PAYLOAD_MODE', 'include');
    assert.deepEqual(result.stderr.split('\n').filter(line => line.includes('SDK-VERIFY-FAIL')), [
      'SDK-VERIFY-FAIL rule=PAYLOAD_MODE directory mode differs from sealed lock: include',
      'SDK-VERIFY-FAIL rule=PAYLOAD_MODE directory mode differs from sealed lock: include/empty',
    ], 'original lock must fail on missing directory identity, without unrelated diagnostics');
    assert.deepEqual(await fs.readFile(path.join(f.sdk, 'SDK.lock.json')), f.lockBytes);
  }
});

for (const typed of [false, true]) {
  test(`historical ${typed ? 'typed' : 'untyped'} file-only lock remains a legal direct input`, async () => {
    const f = await historicalPayload(`file-only-${typed}`);
    // Separate control SDK and independently authored historical file-only lock.
    // This is not a repair or a reseal of the retained directory lock.
    const original = await readJson(path.join(here, 'fixtures/sdk-legacy-directory-lock.json'));
    const files = Object.fromEntries(['bin/cjc', 'lib/member.h'].map(rel => [rel, {
      sha256: original.files[rel].sha256, component: original.files[rel].component,
      symlink: false, producer: {}, ...(typed ? {type: 'file'} : {}),
    }]));
    await atomicJson(path.join(f.sdk, 'SDK.lock.json'), {
      version: 1, role: 'host', files, official_retain: {}, components: original.components,
    });
    const controlBytes = await fs.readFile(path.join(f.sdk, 'SDK.lock.json'));
    good(await legacy(f, `file-only-${typed}-control`));
    assert.deepEqual(await fs.readFile(path.join(f.sdk, 'SDK.lock.json')), controlBytes);
  });
}

test('legacy directory alias locks its target, typed members and every member digest', async () => {
  const f = await legacyInput('legacy-positive'); good(await legacy(f, 'write-lock', true));
  const lock = await readJson(path.join(f.sdk, 'SDK.lock.json'));
  console.log(`DIRECTORY_LOCK_ASSERT_REACHED ${JSON.stringify(lock.files)}`);
  assert.equal(lock.files.include.type, 'directory'); assert.equal(lock.files.include.sha256, null);
  assert.equal(lock.files.include.link_target, 'lib'); assert.equal(lock.files.include.resolved_target, 'lib');
  assert.deepEqual(lock.files.include.members, ['include/empty', 'include/member.h']);
  assert.equal(lock.files['include/empty'].type, 'directory');
  assert.equal(lock.version, 2);
  assert.equal(lock.files.include.mode, (await fs.stat(path.join(f.sdk, 'include'))).mode & 0o777);
  assert.equal(lock.files['include/empty'].mode, (await fs.stat(path.join(f.sdk, 'include/empty'))).mode & 0o777);
  assert.equal(lock.files['include/member.h'].sha256, await fileDigest(path.join(f.source, 'lib/member.h')));
  good(await legacy(f, 'verify'));
  await fs.rename(f.source, `${f.source}-removed`); await fs.rename(f.sdk, `${f.sdk}-moved`); f.sdk += '-moved';
  good(await legacy(f, 'relocated-verify'));
});

for (const version of [undefined, 1, 2]) {
  for (const [label, jsonMode, diskMode] of [
    ['missing', undefined, 0o755], ['false', 'false', 0], ['true', 'true', 1],
    ['null', 'null', 0o755], ['string', '"493"', 0o755], ['float', '493.0', 0o755],
    ['negative', '-1', 0o755], ['out-of-range', '512', 0o755],
  ]) {
    test(`typed-directory mode ${label} is ineligible with version ${version ?? 'absent'}`, async () => {
      const f = await legacyInput(`mode-schema-${version ?? 'absent'}-${label}`);
      good(await legacy(f, 'mode-schema-control', true));
      const lockPath = path.join(f.sdk, 'SDK.lock.json'), validBytes = await fs.readFile(lockPath);
      const synthetic = JSON.parse(validBytes);
      const originalMode = synthetic.files.lib.mode;
      if (version === undefined) delete synthetic.version; else synthetic.version = version;
      synthetic.files.lib.mode = diskMode;
      // A separate synthetic schema input, never substituted for the original
      // R2 lock above. Keep 493.0 as JSON float text to exercise Python typing.
      delete synthetic.files.include.mode;
      if (jsonMode !== undefined) synthetic.files.include.mode = 'MODE_SCHEMA_VALUE';
      const declared = JSON.stringify(synthetic).replace('"MODE_SCHEMA_VALUE"', jsonMode ?? 'null');
      await fs.writeFile(lockPath, declared);
      await fs.chmod(path.join(f.sdk, 'lib'), diskMode);
      try {
        const result = await legacy(f, `mode-schema-${label}-target`);
        rejected(result, 'PAYLOAD_MODE', 'include');
        assert.deepEqual(result.stderr.split('\n').filter(line => line.includes('SDK-VERIFY-FAIL')), [
          'SDK-VERIFY-FAIL rule=PAYLOAD_MODE directory mode differs from sealed lock: include',
        ]);
        assert.equal(await fs.readFile(lockPath, 'utf8'), declared);
      } finally {
        await fs.chmod(path.join(f.sdk, 'lib'), originalMode);
        await fs.writeFile(lockPath, validBytes);
      }
      good(await legacy(f, 'mode-schema-restored'));
    });
  }
}

for (const [name, target] of [['external', '../outside'], ['cycle', '.'], ['dangling', 'missing']]) {
  test(`legacy creation rejects ${name} directory alias and restores`, async () => {
    const f = await legacyInput(`legacy-${name}`);
    await write(path.join(f.work, 'outside/member.h'), 'external');
    await fs.unlink(path.join(f.sdk, 'include')); await fs.symlink(target, path.join(f.sdk, 'include'));
    await fs.unlink(path.join(f.source, 'include')); await fs.symlink(target, path.join(f.source, 'include'));
    const bad = await legacy(f, `${name}-target`, true); rejected(bad, 'SYMLINK', 'include ->');
    assert.equal(bad.stderr.split('\n').filter(line => line.includes('SDK-VERIFY-FAIL')).length, 1);
    await assert.rejects(fs.access(path.join(f.sdk, 'SDK.lock.json')));
    for (const tree of [f.source, f.sdk]) { await fs.unlink(path.join(tree, 'include')); await fs.symlink('lib', path.join(tree, 'include')); }
    good(await legacy(f, `${name}-restored`, true)); good(await legacy(f, `${name}-control`));
  });
}

for (const kind of ['target', 'missing', 'tamper', 'extra', 'extra-empty-directory', 'empty-directory', 'type', 'member-declaration', 'directory-mode', 'missing-mode']) {
  test(`legacy sealed directory rejects ${kind} without rewriting its lock`, async () => {
    const f = await legacyInput(`legacy-${kind}`); good(await legacy(f, `${kind}-control`, true));
    const lock = await fileDigest(path.join(f.sdk, 'SDK.lock.json'));
    const lockBytes = await fs.readFile(path.join(f.sdk, 'SDK.lock.json'));
    const member = path.join(f.sdk, 'lib/member.h'), bytes = await fs.readFile(member);
    if (kind === 'target') { await fs.unlink(path.join(f.sdk, 'include')); await fs.symlink('./lib', path.join(f.sdk, 'include')); }
    if (kind === 'missing') await fs.unlink(member);
    if (kind === 'tamper') await fs.writeFile(member, 'tampered header\n');
    if (kind === 'extra') await write(path.join(f.sdk, 'lib/extra.h'), 'extra');
    if (kind === 'extra-empty-directory') await fs.mkdir(path.join(f.sdk, 'lib/extra-empty'));
    if (kind === 'empty-directory') await fs.rmdir(path.join(f.sdk, 'lib/empty'));
    if (kind === 'type') { await fs.unlink(path.join(f.sdk, 'include')); await fs.cp(path.join(f.sdk, 'lib'), path.join(f.sdk, 'include'), {recursive: true}); }
    if (kind === 'directory-mode') await fs.chmod(path.join(f.sdk, 'lib'), 0o655);
    if (kind === 'missing-mode') {
      const declared = JSON.parse(lockBytes); delete declared.files.include.mode;
      await atomicJson(path.join(f.sdk, 'SDK.lock.json'), declared);
    }
    if (kind === 'member-declaration') {
      const declared = JSON.parse(lockBytes); declared.files.include.members = [];
      await atomicJson(path.join(f.sdk, 'SDK.lock.json'), declared);
    }
    const rule = {target: 'SYMLINK', missing: 'UNDECLARED', tamper: 'PAYLOAD_DIGEST', extra: 'UNDECLARED', 'extra-empty-directory': 'UNDECLARED',
      'empty-directory': 'UNDECLARED', type: 'PAYLOAD_TYPE', 'member-declaration': 'PAYLOAD_MEMBERS', 'directory-mode': 'PAYLOAD_MODE', 'missing-mode': 'PAYLOAD_MODE'}[kind];
    const result = await legacy(f, `${kind}-target`);
    rejected(result, rule, kind === 'tamper' ? 'include/member.h' : 'include');
    if (rule === 'UNDECLARED') assert.ok(!result.stderr.includes('rule=PAYLOAD_'), result.stderr);
    if (!['member-declaration', 'missing-mode'].includes(kind)) assert.equal(await fileDigest(path.join(f.sdk, 'SDK.lock.json')), lock);
    if (kind === 'target' || kind === 'type') { await fs.rm(path.join(f.sdk, 'include'), {recursive: true}); await fs.symlink('lib', path.join(f.sdk, 'include')); }
    if (kind === 'missing' || kind === 'tamper') await fs.writeFile(member, bytes);
    if (kind === 'extra') await fs.unlink(path.join(f.sdk, 'lib/extra.h'));
    if (kind === 'extra-empty-directory') await fs.rmdir(path.join(f.sdk, 'lib/extra-empty'));
    if (kind === 'empty-directory') await fs.mkdir(path.join(f.sdk, 'lib/empty'));
    if (kind === 'directory-mode') await fs.chmod(path.join(f.sdk, 'lib'), 0o755);
    if (kind === 'member-declaration' || kind === 'missing-mode') await fs.writeFile(path.join(f.sdk, 'SDK.lock.json'), lockBytes);
    assert.equal(await fileDigest(path.join(f.sdk, 'SDK.lock.json')), lock);
    good(await legacy(f, `${kind}-restored`));
  });
}

for (const kind of ['plain', 'file', 'directory']) {
  test(`publisher ${kind} source authenticates the exact materialized closure`, async () => {
    const f = await input(`publisher-${kind}`);
    if (kind !== 'plain') await fs.symlink(kind === 'file' ? 'member.h' : 'lib', path.join(f.source, kind === 'file' ? 'lib/alias.h' : 'include'));
    const result = await publisher(f, `${kind}-publish`); good(result);
    const depot = result.stdout.trim(), lock = await readJson(path.join(depot, 'SDK.lock.json'));
    const expected = ['bin/cjc', 'lib/member.h', ...(kind === 'file' ? ['lib/alias.h'] : []), ...(kind === 'directory' ? ['include/member.h'] : [])].sort();
    console.log(`PUBLISHER_MEMBERS_ASSERT_REACHED kind=${kind} files=${JSON.stringify(lock.files)} source=${JSON.stringify(lock.source_layout)}`);
    assert.deepEqual(Object.keys(lock.files).sort(), expected);
    for (const rel of expected) {
      assert.equal((await fs.lstat(path.join(depot, rel))).isSymbolicLink(), false);
      assert.equal(lock.files[rel].type, 'file'); assert.equal(await fileDigest(path.join(depot, rel)), await fileDigest(path.join(f.source, rel)));
      assert.equal(lock.files[rel].mode, (await fs.stat(path.join(f.source, rel))).mode & 0o555);
    }
    if (kind === 'directory') { assert.equal(lock.source_layout.include.target, 'lib'); assert.ok(lock.source_layout['include/empty']); }
    good(await publisher(f, `${kind}-reuse`));
  });
}

for (const [name, target, diagnostic] of [['external', '../outside', 'link escapes root: include'],
  ['cycle', '.', 'directory cycle: include'], ['dangling', 'missing', 'No such file or directory']]) {
  test(`publisher rejects ${name} directory alias before publication`, async () => {
    const f = await input(`publisher-${name}`); await write(path.join(f.work, 'outside/header'), 'outside');
    await fs.symlink(target, path.join(f.source, 'include'));
    const bad = await publisher(f, `${name}-target`); assert.equal(bad.rc, 1); assert.ok(bad.stderr.includes(diagnostic), bad.stderr);
    await assert.rejects(fs.access(path.join(f.cache, 'official-sdk')));
    await fs.unlink(path.join(f.source, 'include')); await fs.symlink('lib', path.join(f.source, 'include'));
    good(await publisher(f, `${name}-restored`));
  });
}

for (const kind of ['bytes', 'target', 'members']) {
  test(`publisher rejects source ${kind} change after preauthentication`, async () => {
    const f = await input(`publisher-race-${kind}`); await fs.symlink('lib', path.join(f.source, 'include'));
    // A bounded copy input gives the observer time to mutate after the real
    // .incoming transaction appears, hence after the source snapshot. This is
    // filesystem observation, not interposition or a callback in the product.
    await fs.writeFile(path.join(f.source, 'lib/copy-window.bin'), Buffer.alloc(32 * 1024 * 1024, 41));
    const args = [engine, '--remote', '--root', f.cache, '--lane', 'sym_cjcj_934_implement_r6098289478',
      'sdk-publish', '--source', f.source, '--version', 'layout-test'];
    const child = spawn('python3', args, {stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', completed = false;
    child.stdout.on('data', bytes => { stdout += bytes; }); child.stderr.on('data', bytes => { stderr += bytes; });
    const finished = new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', rc => { completed = true; resolve({rc, stdout, stderr}); }); });
    const parent = path.join(f.cache, 'official-sdk/layout-test'); let observed = false;
    while (!completed) {
      const names = await fs.readdir(parent).catch(() => []);
      if (names.some(name => name.startsWith('.incoming-'))) { observed = true; break; }
      await delay(1);
    }
    if (observed) {
      if (kind === 'bytes') await fs.writeFile(path.join(f.source, 'lib/member.h'), 'changed after snapshot\n');
      if (kind === 'target') { await fs.unlink(path.join(f.source, 'include')); await fs.symlink('./lib', path.join(f.source, 'include')); }
      if (kind === 'members') await write(path.join(f.source, 'lib/new.h'), 'added after snapshot\n');
    }
    const result = await observe(f, `source-${kind}-target`, await finished);
    console.log(`SOURCE_PREAUTH_ASSERT_REACHED kind=${kind} transactionObserved=${observed}`);
    assert.equal(observed, true, 'must mutate after real preauthentication');
    assert.equal(result.rc, 1, result.stderr); assert.match(result.stderr, /SDK changed during copy or unsupported filesystem entry/);
    assert.deepEqual(await fs.readdir(parent), [], 'failed source may not publish a seal');
    await fs.writeFile(path.join(f.source, 'lib/member.h'), 'authenticated header\n');
    if (kind === 'target') { await fs.unlink(path.join(f.source, 'include')); await fs.symlink('lib', path.join(f.source, 'include')); }
    if (kind === 'members') await fs.unlink(path.join(f.source, 'lib/new.h'));
    good(await publisher(f, `source-${kind}-restored`));
  });
}
