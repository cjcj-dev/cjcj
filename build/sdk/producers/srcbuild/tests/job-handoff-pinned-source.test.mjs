// Cross-job source handoffs carry no source: the consumer obtains every source
// tree by a pinned 40-hex Git checkout and the payload holds only build state.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const product = path.resolve(import.meta.dirname, '../job-handoff.mjs');
const VERSION_FILE = 'packages/basic/src/Version.cj';
const VERSION_PINNED = 'package std.basic\npublic let CANGJIE_VERSION: String = "0.0.0"\n';
const VERSION_INJECTED = 'package std.basic\npublic let CANGJIE_VERSION: String = "0.0.2"\n';
const nested = '.srcbuild/workspace/compiler';
const git = (cwd, ...args) => {
  const r = spawnSync('git', ['-C', cwd, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', ...args], {encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
};
const write = async (file, body, mode) => {
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, body, mode ? {mode} : undefined);
};
async function repository(dir, files) {
  await fs.mkdir(dir, {recursive: true});
  git(dir, 'init', '-q');
  for (const [rel, body] of Object.entries(files)) await write(path.join(dir, rel), body);
  git(dir, 'add', '-A');
  git(dir, 'commit', '-qm', 'test: source');
  return git(dir, 'rev-parse', 'HEAD');
}
async function fixture(t) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'pinned-handoff-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const upstream = path.join(dir, 'upstream');
  const pinned = await repository(upstream, {'src/compiler.cj': 'pinned compiler source\n'});
  await write(path.join(upstream, 'src/compiler.cj'), 'later compiler source\n');
  git(upstream, 'commit', '-qam', 'test: later source');
  const later = git(upstream, 'rev-parse', 'HEAD');
  git(upstream, 'config', 'uploadpack.allowAnySHA1InWant', 'true');
  const origin = path.join(dir, 'origin');
  const head = await repository(origin, {'cjpm.toml': 'version = "0.0.0"\n', 'packages/cjc/src/main.cj': 'main() {}\n',
    'packages/basic/src/Version.cj': VERSION_PINNED, 'runtime_shim/cjc_runtime_config.c': 'int config;\n'});
  await write(path.join(origin, 'packages/cjc/src/main.cj'), 'main() { later }\n');
  git(origin, 'commit', '-qam', 'test: later workflow source');
  const laterHead = git(origin, 'rev-parse', 'HEAD');
  const root = path.join(dir, 'workspace');
  const checkout = async (commit = head) => {
    await fs.rm(root, {recursive: true, force: true});
    git(dir, 'clone', '-q', origin, root);
    git(root, 'checkout', '-q', '--detach', commit);
  };
  await checkout();
  await fs.mkdir(path.join(root, '.srcbuild/workspace'), {recursive: true});
  git(path.join(root, '.srcbuild/workspace'), 'clone', '-q', upstream, 'compiler');
  git(path.join(root, nested), 'checkout', '-q', '--detach', pinned);
  await write(path.join(root, nested, 'target/release/bin/cjc'), '#!/bin/sh\necho built\n', 0o755);
  await write(path.join(root, 'runtime_shim/cjc_runtime_config.o'), 'object');
  await write(path.join(root, 'target/release/cjc.cjo'), 'cjo');
  await write(path.join(root, '.srcbuild/workspace/install/lib/libcangjie-runtime.so'), 'runtime');
  // The product version is injected into a tracked file by an earlier step.
  await write(path.join(root, 'cjpm.toml'), 'version = "0.0.2"\n');
  const archive = path.join(dir, 'artifact');
  const env = {...process.env, GITHUB_WORKSPACE: root, GITHUB_SHA: head, GITHUB_RUN_ID: '901',
    CJCJ_SRCBUILD_TARGET: 'linux-x64', GITHUB_ENV: path.join(dir, 'env'), GITHUB_PATH: path.join(dir, 'path')};
  const run = (mode, phase = 'stage0', overrides = {}) => {
    const r = spawnSync(process.execPath, [product, mode, phase, archive], {env: {...env, ...overrides}, encoding: 'utf8'});
    return {rc: r.status, output: `${r.stdout}${r.stderr}`};
  };
  return {dir, root, upstream, pinned, later, head, laterHead, archive, run, checkout};
}
const members = archive => spawnSync('tar', ['-tf', archive], {encoding: 'utf8'}).stdout.split('\n')
  .filter(Boolean).map(name => name.replace(/^\.\//, '').replace(/\/$/, ''));

test('handoff payload carries build outputs but no tracked source; manifest pins every checkout', async t => {
  const f = await fixture(t);
  const packed = f.run('pack');
  assert.equal(packed.rc, 0, packed.output);
  const manifest = JSON.parse(await fs.readFile(path.join(f.archive, 'manifest.json'), 'utf8'));
  assert.equal(manifest.sourcePolicy, 'pinned-git-checkout');
  assert.equal(manifest.commit, f.head);
  assert.deepEqual(manifest.checkouts, [{path: nested, commit: f.pinned, url: f.upstream}]);
  assert.deepEqual(manifest.overlay.map(row => row.path), ['cjpm.toml']);
  const names = members(path.join(f.archive, 'payload.tar'));
  for (const source of ['packages/cjc/src/main.cj', 'runtime_shim/cjc_runtime_config.c', nested + '/src/compiler.cj'])
    assert.ok(!names.includes(source), `source crossed the job boundary: ${source}`);
  assert.ok(!names.some(name => name.split('/').includes('.git')), 'Git objects crossed the job boundary');
  for (const output of ['runtime_shim/cjc_runtime_config.o', 'target/release/cjc.cjo', nested + '/target/release/bin/cjc',
    '.srcbuild/workspace/install/lib/libcangjie-runtime.so']) assert.ok(names.includes(output), `missing output ${output}`);
  console.log(`HANDOFF_SOURCE_FREE members=${names.length} checkouts=${manifest.checkouts.length}`);
});

test('fresh runner restores outputs over a pinned Git checkout of the recorded commits', async t => {
  const f = await fixture(t);
  assert.equal(f.run('pack').rc, 0);
  await f.checkout();
  const restored = f.run('restore');
  assert.equal(restored.rc, 0, restored.output);
  assert.equal(git(path.join(f.root, nested), 'rev-parse', 'HEAD'), f.pinned);
  assert.equal(await fs.readFile(path.join(f.root, nested, 'src/compiler.cj'), 'utf8'), 'pinned compiler source\n');
  assert.equal(await fs.readFile(path.join(f.root, nested, 'target/release/bin/cjc'), 'utf8'), '#!/bin/sh\necho built\n');
  assert.equal(await fs.readFile(path.join(f.root, 'cjpm.toml'), 'utf8'), 'version = "0.0.2"\n');
});

test('consumer rejects a workflow checkout at a different commit', async t => {
  const f = await fixture(t);
  assert.equal(f.run('pack').rc, 0);
  await f.checkout(f.laterHead);
  const rejected = f.run('restore');
  assert.notEqual(rejected.rc, 0);
  assert.match(rejected.output, /handoff checkout SHA mismatch: workspace/);
});

test('consumer rejects a nested source checkout at a different commit', async t => {
  const f = await fixture(t);
  assert.equal(f.run('pack').rc, 0);
  await f.checkout();
  await fs.mkdir(path.join(f.root, '.srcbuild/workspace'), {recursive: true});
  git(path.join(f.root, '.srcbuild/workspace'), 'clone', '-q', f.upstream, 'compiler');
  git(path.join(f.root, nested), 'checkout', '-q', '--detach', f.later);
  const rejected = f.run('restore');
  assert.notEqual(rejected.rc, 0);
  assert.match(rejected.output, new RegExp(`handoff checkout SHA mismatch: ${nested.replace(/[.]/g, '\\.')}`));
});

test('consumer rejects a payload that carries a verbatim source file', async t => {
  const f = await fixture(t);
  assert.equal(f.run('pack').rc, 0);
  // Re-seal the payload with a tracked source file, as an old source tar did.
  const payload = path.join(f.archive, 'payload.tar');
  const r = spawnSync('tar', ['-rf', payload, '-C', f.root, 'packages/cjc/src/main.cj'], {encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr);
  const manifestFile = path.join(f.archive, 'manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
  manifest.sha256 = crypto.createHash('sha256').update(await fs.readFile(payload)).digest('hex');
  await fs.writeFile(manifestFile, JSON.stringify(manifest));
  await f.checkout();
  const rejected = f.run('restore');
  assert.notEqual(rejected.rc, 0);
  assert.match(rejected.output, /handoff payload carries source: packages\/cjc\/src\/main\.cj/);
});

test('consumer rejects a manifest without the pinned checkout policy', async t => {
  const f = await fixture(t);
  assert.equal(f.run('pack').rc, 0);
  const manifestFile = path.join(f.archive, 'manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
  delete manifest.sourcePolicy;
  await fs.writeFile(manifestFile, JSON.stringify(manifest));
  await f.checkout();
  assert.match(f.run('restore').output, /handoff manifest lacks pinned checkout policy/);
});

// The injected product version crosses as data and is re-derived on restore.
test('the injected version crosses as data, never as Version.cj bytes', async t => {
  const f = await fixture(t);
  await write(path.join(f.root, VERSION_FILE), VERSION_INJECTED);
  const packed = f.run('pack', 'stage0', {SOURCE_SDK_VERSION: '0.0.2'});
  assert.equal(packed.rc, 0, packed.output);
  const manifest = JSON.parse(await fs.readFile(path.join(f.archive, 'manifest.json'), 'utf8'));
  assert.deepEqual(manifest.derivations.map(({path: rel, kind, version}) => ({rel, kind, version})),
    [{rel: VERSION_FILE, kind: 'cangjie-version', version: '0.0.2'}]);
  assert.ok(!members(path.join(f.archive, 'payload.tar')).includes(VERSION_FILE), 'Version.cj bytes crossed the job boundary');
  await f.checkout();
  const restored = f.run('restore');
  assert.equal(restored.rc, 0, restored.output);
  assert.equal(await fs.readFile(path.join(f.root, VERSION_FILE), 'utf8'), VERSION_INJECTED);
});
test('red cut: an edited tracked source file or a non-injection Version.cj edit fails the pack', async t => {
  const f = await fixture(t);
  await write(path.join(f.root, 'packages/cjc/src/main.cj'), 'main() { edited }\n');
  const edited = f.run('pack');
  assert.notEqual(edited.rc, 0);
  assert.match(edited.output, /handoff modified tracked source: packages\/cjc\/src\/main\.cj/);
  const g = await fixture(t);
  await write(path.join(g.root, VERSION_FILE), VERSION_INJECTED + '// extra\n');
  const extra = g.run('pack');
  assert.notEqual(extra.rc, 0);
  assert.match(extra.output, /handoff modified tracked source: packages\/basic\/src\/Version\.cj/);
});
test('red cut: an edited, a new untracked or a deleted source file fails the pack; build outputs still cross', async t => {
  const f = await fixture(t);
  await write(path.join(f.root, 'packages/cjc/src/main.cj'), 'main() { edited }\n');
  const edited = f.run('pack');
  assert.equal(edited.rc, 1, edited.output);
  assert.match(edited.output, /handoff modified tracked source: packages\/cjc\/src\/main\.cj/);
  for (const rel of ['packages/cjc/src/extra.cj', 'runtime_shim/extra_shim.c', 'packages/cjc/src/extra.h']) {
    const g = await fixture(t);
    await write(path.join(g.root, rel), 'untracked source\n');
    const added = g.run('pack');
    assert.equal(added.rc, 1, `${rel}: ${added.output}`);
    assert.match(added.output, new RegExp(`handoff untracked source: ${rel.replace(/[./]/g, '\\$&')}`));
  }
  const h = await fixture(t);
  await fs.rm(path.join(h.root, 'packages/cjc/src/main.cj'));
  const deleted = h.run('pack');
  assert.equal(deleted.rc, 1, deleted.output);
  assert.match(deleted.output, /handoff deleted tracked source: packages\/cjc\/src\/main\.cj/);
  // control: a generated source inside an untracked build directory and an object
  // next to tracked sources are build outputs and still cross
  const k = await fixture(t);
  await write(path.join(k.root, 'packages/cjc/target/gen/generated.cj'), 'generated\n');
  const built = k.run('pack');
  assert.equal(built.rc, 0, built.output);
  const crossed = members(path.join(k.archive, 'payload.tar'));
  for (const rel of ['packages/cjc/target/gen/generated.cj', 'runtime_shim/cjc_runtime_config.o']) assert.ok(crossed.includes(rel), rel);
});
test('red cut: restore re-checks each derivation and overlay and the exact edited set', async t => {
  const f = await fixture(t);
  await write(path.join(f.root, VERSION_FILE), VERSION_INJECTED);
  assert.equal(f.run('pack', 'stage0', {SOURCE_SDK_VERSION: '0.0.2'}).rc, 0);
  const wrongVersion = f.run('pack', 'stage0', {SOURCE_SDK_VERSION: '0.0.9'});
  assert.match(wrongVersion.output, /handoff derivation version is not SOURCE_SDK_VERSION/);
  assert.equal(f.run('pack', 'stage0', {SOURCE_SDK_VERSION: '0.0.2'}).rc, 0);
  const manifestFile = path.join(f.archive, 'manifest.json');
  const original = await fs.readFile(manifestFile, 'utf8');
  const tampered = async (edit, expected) => {
    const manifest = JSON.parse(original); edit(manifest);
    await fs.writeFile(manifestFile, JSON.stringify(manifest));
    await f.checkout();
    const rejected = f.run('restore');
    assert.notEqual(rejected.rc, 0, JSON.stringify(manifest.derivations));
    assert.match(rejected.output, expected);
  };
  await tampered(m => { m.derivations[0].version = '0.0.3'; m.environment.SOURCE_SDK_VERSION = '0.0.3'; },
    /handoff derivation digest mismatch: packages\/basic\/src\/Version\.cj/);
  await tampered(m => { m.environment.SOURCE_SDK_VERSION = '0.0.3'; }, /handoff derivation version is not SOURCE_SDK_VERSION/);
  await tampered(m => { m.overlay[0].sha256 = 'f'.repeat(64); }, /handoff overlay bytes mismatch: cjpm\.toml/);
  // The restored checkout must differ from its pins in exactly the recorded paths.
  await fs.writeFile(manifestFile, original);
  await f.checkout();
  await write(path.join(f.root, 'packages/cjc/src/main.cj'), 'main() { consumer edit }\n');
  const dirty = f.run('restore');
  assert.notEqual(dirty.rc, 0);
  assert.match(dirty.output, /handoff restored checkout differs from its manifest: packages\/cjc\/src\/main\.cj/);
  // Control: the untouched manifest restores.
  await fs.writeFile(manifestFile, original);
  await f.checkout();
  assert.equal(f.run('restore').rc, 0);
});
