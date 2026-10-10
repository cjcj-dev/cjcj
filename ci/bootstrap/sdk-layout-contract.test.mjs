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

test('legacy directory alias locks its target, typed members and every member digest', async () => {
  const f = await legacyInput('legacy-positive'); good(await legacy(f, 'write-lock', true));
  const lock = await readJson(path.join(f.sdk, 'SDK.lock.json'));
  console.log(`DIRECTORY_LOCK_ASSERT_REACHED ${JSON.stringify(lock.files)}`);
  assert.equal(lock.files.include.type, 'directory'); assert.equal(lock.files.include.sha256, null);
  assert.equal(lock.files.include.link_target, 'lib'); assert.equal(lock.files.include.resolved_target, 'lib');
  assert.deepEqual(lock.files.include.members, ['include/empty', 'include/member.h']);
  assert.equal(lock.files['include/empty'].type, 'directory');
  assert.equal(lock.files['include/member.h'].sha256, await fileDigest(path.join(f.source, 'lib/member.h')));
  good(await legacy(f, 'verify'));
  await fs.rename(f.source, `${f.source}-removed`); await fs.rename(f.sdk, `${f.sdk}-moved`); f.sdk += '-moved';
  good(await legacy(f, 'relocated-verify'));
});

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

for (const kind of ['target', 'missing', 'tamper', 'extra', 'empty-directory', 'type']) {
  test(`legacy sealed directory rejects ${kind} without rewriting its lock`, async () => {
    const f = await legacyInput(`legacy-${kind}`); good(await legacy(f, `${kind}-control`, true));
    const lock = await fileDigest(path.join(f.sdk, 'SDK.lock.json'));
    const member = path.join(f.sdk, 'lib/member.h'), bytes = await fs.readFile(member);
    if (kind === 'target') { await fs.unlink(path.join(f.sdk, 'include')); await fs.symlink('./lib', path.join(f.sdk, 'include')); }
    if (kind === 'missing') await fs.unlink(member);
    if (kind === 'tamper') await fs.writeFile(member, 'tampered header\n');
    if (kind === 'extra') await write(path.join(f.sdk, 'lib/extra.h'), 'extra');
    if (kind === 'empty-directory') await fs.rmdir(path.join(f.sdk, 'lib/empty'));
    if (kind === 'type') { await fs.unlink(path.join(f.sdk, 'include')); await fs.writeFile(path.join(f.sdk, 'include'), 'lib'); }
    const rule = {target: 'SYMLINK', missing: 'PAYLOAD_MEMBERS', tamper: 'PAYLOAD_DIGEST', extra: 'PAYLOAD_MEMBERS',
      'empty-directory': 'PAYLOAD_MEMBERS', type: 'PAYLOAD_TYPE'}[kind];
    rejected(await legacy(f, `${kind}-target`), rule, kind === 'tamper' ? 'include/member.h' : 'include');
    assert.equal(await fileDigest(path.join(f.sdk, 'SDK.lock.json')), lock);
    if (kind === 'target' || kind === 'type') { await fs.unlink(path.join(f.sdk, 'include')); await fs.symlink('lib', path.join(f.sdk, 'include')); }
    if (kind === 'missing' || kind === 'tamper') await fs.writeFile(member, bytes);
    if (kind === 'extra') await fs.unlink(path.join(f.sdk, 'lib/extra.h'));
    if (kind === 'empty-directory') await fs.mkdir(path.join(f.sdk, 'lib/empty'));
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
