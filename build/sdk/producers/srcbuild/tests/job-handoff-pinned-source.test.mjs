// Cross-job source handoffs carry no source: the consumer obtains every source
// tree by a pinned 40-hex Git checkout and the payload holds only build state.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {prepareStdDependencies, stdDependencySources} from '../../../../../ci/bootstrap/stdlib-build.mjs';
import {prepareWindowsLlvmSource} from '../../../../srcbuild/stages/fetch.mjs';
import {putLlvmFolders, putLlvmWindowsFixes} from '../../../../test/fixtures/windows-llvm-source.mjs';

const product = path.resolve(import.meta.dirname, '../job-handoff.mjs');
const VERSION_FILE = 'packages/basic/src/Version.cj';
const VERSION_PINNED = 'package std.basic\npublic let CANGJIE_VERSION: String = "0.0.0"\n';
const VERSION_INJECTED = 'package std.basic\npublic let CANGJIE_VERSION: String = "0.0.2"\n';
const nested = '.srcbuild/workspace/cangjie_compiler';
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
  const pinned = await repository(upstream, {'src/compiler.cj': 'pinned compiler source\n',
    'schema/CMakeLists.txt': '# pinned schema\n', 'cjpm.toml': 'version = "0.0.0"\n', '.gitignore': '/third_party/llvm-project/\n'});
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
  git(path.join(root, '.srcbuild/workspace'), 'clone', '-q', upstream, 'cangjie_compiler');
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

async function stdFixture(t) {
  const f = await fixture(t);
  git(f.root, 'restore', 'cjpm.toml');
  const work = path.join(f.root, '.srcbuild/workspace');
  const runtime = path.join(work, 'native-sources/runtime');
  const upstream = path.join(f.dir, 'runtime-origin');
  const commit = await repository(upstream, {'stdlib/build.py': '# tracked runtime file\n'});
  git(f.root, 'clone', '-q', upstream, runtime);
  const deps = stdDependencySources();
  for (const [name, files] of Object.entries({
    bounds: {'include/securec.h': 'bounds header', 'src/securecutil.c': 'bounds source'},
    pcre2: {'pcre2/CMakeLists.txt': 'pcre2 build', 'pcre2/src/pcre2.c': 'pcre2 source'},
  })) {
    const origin = path.join(f.dir, name);
    await repository(origin, files);
    deps[name].root = path.join(work, 'native-sources', name);
    git(f.root, 'clone', '-q', origin, deps[name].root);
  }
  const addStd = async (id, origin = runtime) => {
    const source = path.join(work, 'native-bootstrap/sources', id);
    git(f.root, 'clone', '-q', origin, source);
    await prepareStdDependencies({source, dependencies: deps});
    await write(path.join(source, 'stdlib/build/build/std.o'), id);
    return source;
  };
  return {...f, runtime, runtimeOrigin: upstream, commit, addStd};
}

test('stage handoffs restore the pinned runtime before its bootstrap std clones', async t => {
  const f = await stdFixture(t), clones = [];
  for (const [phase, id] of [['stage1-initial-std', 'std0'], ['stage1-std', 'stdBootstrap'],
    ['stage1-compiler', null], ['stage3', 'std1']]) {
    if (id) clones.push(await f.addStd(id));
    // aarch64 has the same checkout graph without the separate x64 stage3 SDK.
    const run = mode => f.run(mode, phase, {CJCJ_SRCBUILD_TARGET: 'linux-aarch64'});
    const packed = run('pack');
    assert.equal(packed.rc, 0, packed.output);
    const file = path.join(f.archive, 'manifest.json'), record = JSON.parse(await fs.readFile(file));
    const published = record.checkouts.map(row => path.join(f.root, row.path));
    if (phase === 'stage1-std') {
      // Simulate a pre-fix manifest: consumers cannot trust the producer order.
      record.checkouts.sort((a, b) => a.path < b.path ? -1 : 1);
      await fs.writeFile(file, JSON.stringify(record));
    }
    await fs.rm(path.join(f.root, '.srcbuild'), {recursive: true});
    const restored = run('restore');
    assert.equal(restored.rc, 0, restored.output);
    assert.equal(git(f.runtime, 'rev-parse', 'HEAD'), f.commit);
    for (const source of clones) {
      assert.ok(published.indexOf(f.runtime) < published.indexOf(source));
      assert.equal(git(source, 'rev-parse', 'HEAD'), f.commit);
      assert.equal(git(source, 'remote', 'get-url', 'origin'), f.runtime);
      assert.equal(await fs.readFile(path.join(source, 'stdlib/third_party/boundscheck-v1.1.16/include/securec.h'), 'utf8'), 'bounds header');
      assert.equal(await fs.readFile(path.join(source, 'stdlib/third_party/pcre2/pcre2/src/pcre2.c'), 'utf8'), 'pcre2 source');
      assert.equal(await fs.readFile(path.join(source, 'stdlib/build/build/std.o'), 'utf8'), path.basename(source));
    }
  }
});

test('std vendor files come from pinned inputs while generated siblings stay in the payload', async t => {
  const f = await stdFixture(t), std = await f.addStd('std0', f.runtimeOrigin);
  const deps = path.join(std, 'stdlib/third_party');
  const header = path.join(deps, 'boundscheck-v1.1.16/include/securec.h');
  const generated = path.join(deps, 'pcre2/pcre2/src/generated.h');
  const rel = file => path.relative(f.root, file).split(path.sep).join('/');
  await write(generated, 'configured header');
  await fs.appendFile(header, 'unexpected edit');
  const dirty = f.run('pack');
  assert.equal(dirty.rc, 1, dirty.output);
  assert.ok(dirty.output.includes('handoff std dependency copy differs from pinned input: ' + rel(header)), dirty.output);
  await write(header, 'bounds header');
  const packed = f.run('pack');
  assert.equal(packed.rc, 0, packed.output);
  const archive = path.join(f.archive, 'payload.tar'), names = members(archive);
  assert.ok(names.includes(rel(generated)));
  const copies = ['boundscheck-v1.1.16/include/securec.h', 'boundscheck-v1.1.16/src/securecutil.c',
    'pcre2/pcre2/CMakeLists.txt', 'pcre2/pcre2/src/pcre2.c'].map(file => rel(path.join(deps, file)));
  for (const copy of copies) assert.ok(!names.includes(copy), 'copied source in tar: ' + copy);
  // A pre-fix artifact contains these untracked files and has no copy rows.
  const file = path.join(f.archive, 'manifest.json');
  const record = JSON.parse(await fs.readFile(file));
  const appended = spawnSync('tar', ['-rf', archive, '-C', f.root, ...copies], {encoding: 'utf8'});
  assert.equal(appended.status, 0, appended.stderr);
  record.sha256 = crypto.createHash('sha256').update(await fs.readFile(archive)).digest('hex');
  await fs.writeFile(file, JSON.stringify(record));
  await f.checkout();
  const conflict = f.run('restore');
  assert.equal(conflict.rc, 1, conflict.output);
  assert.ok(conflict.output.includes('handoff payload carries source: ' + copies[0]), conflict.output);
  delete record.stdCopies;
  await fs.writeFile(file, JSON.stringify(record));
  await f.checkout();
  const legacy = f.run('restore');
  assert.equal(legacy.rc, 0, legacy.output);
  assert.equal(await fs.readFile(header, 'utf8'), 'bounds header');
  assert.equal(await fs.readFile(generated, 'utf8'), 'configured header');
});

test('checkout origin cycles fail before restoring even an independent checkout', async t => {
  const f = await fixture(t);
  const packed = f.run('pack');
  assert.equal(packed.rc, 0, packed.output);
  const file = path.join(f.archive, 'manifest.json');
  const record = JSON.parse(await fs.readFile(file));
  const a = '.srcbuild/a', b = '.srcbuild/b';
  record.checkouts.push({path: a, commit: f.pinned, url: path.join(f.root, b)},
    {path: b, commit: f.pinned, url: '../a'});
  await fs.writeFile(file, JSON.stringify(record));
  await f.checkout();
  const rejected = f.run('restore');
  assert.equal(rejected.rc, 1, rejected.output);
  assert.match(rejected.output, /handoff checkout dependency cycle: .srcbuild\/a/);
  await assert.rejects(fs.stat(path.join(f.root, '.srcbuild')), {code: 'ENOENT'});
});

test('a bootstrap std linked worktree restores without its producer .git pointer', async t => {
  const f = await fixture(t), source = path.join(f.root, '.srcbuild/workspace/native-bootstrap/sources/std0');
  git(path.join(f.root, nested), 'worktree', 'add', '-q', '--detach', source, f.pinned);
  assert.ok((await fs.stat(path.join(source, '.git'))).isFile());
  const packed = f.run('pack', 'stage1-initial-std');
  assert.equal(packed.rc, 0, packed.output);
  assert.ok(!members(path.join(f.archive, 'payload.tar')).some(rel => rel.split('/').includes('.git')));
  await f.checkout();
  const restored = f.run('restore', 'stage1-initial-std');
  assert.equal(restored.rc, 0, restored.output);
  assert.equal(git(source, 'rev-parse', 'HEAD'), f.pinned);
});

test('a different workspace root is refused before resolving producer-local paths', async t => {
  const f = await fixture(t);
  git(f.root, 'clone', '-q', path.join(f.root, nested), '.srcbuild/clone');
  const packed = f.run('pack');
  assert.equal(packed.rc, 0, packed.output);
  const receiver = path.join(f.dir, 'receiver');
  git(f.dir, 'clone', '-q', f.root, receiver);
  await fs.rm(f.root, {recursive: true});
  const rejected = f.run('restore', 'stage0', {GITHUB_WORKSPACE: receiver});
  assert.equal(rejected.rc, 1, rejected.output);
  assert.match(rejected.output, /handoff identity mismatch: workspace/);
  await assert.rejects(fs.stat(path.join(receiver, '.srcbuild')), {code: 'ENOENT'});
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
  git(path.join(f.root, '.srcbuild/workspace'), 'clone', '-q', f.upstream, 'cangjie_compiler');
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
  // Including a new directory (one or more levels) under a tracked source directory.
  for (const rel of ['packages/cjc/src/extra.cj', 'runtime_shim/extra_shim.c', 'packages/cjc/src/extra.h',
    'packages/cjc/src/newdir/extra.cj', 'packages/cjc/src/a/b/deep.cj', 'runtime_shim/sub/extra_shim.c']) {
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

test('red cut: restore rejects untracked source the receiving workspace already holds; outputs and a clean receiver restore', async t => {
  // The archive is legal and unchanged; only the receiver's checkout differs.
  for (const rel of ['packages/cjc/src/local.cj', 'packages/cjc/src/more/local.cj', 'runtime_shim/extra_shim.c', 'packages/cjc/src/extra.h']) {
    const f = await fixture(t);
    assert.equal(f.run('pack').rc, 0);
    await f.checkout();
    await write(path.join(f.root, rel), 'receiver residue\n');
    const rejected = f.run('restore');
    assert.equal(rejected.rc, 1, `${rel}: ${rejected.output}`);
    assert.match(rejected.output, new RegExp(`handoff untracked source: ${rel.replace(/[./]/g, '\\$&')}`));
  }
  // control: a generated source in an untracked build tree and an object beside
  // tracked sources are build outputs, so that receiver still restores
  const g = await fixture(t);
  assert.equal(g.run('pack').rc, 0);
  await g.checkout();
  await write(path.join(g.root, 'packages/cjc/target/gen/generated.cj'), 'generated\n');
  await write(path.join(g.root, 'runtime_shim/local.o'), 'object');
  const restored = g.run('restore');
  assert.equal(restored.rc, 0, restored.output);
  assert.equal(await fs.readFile(path.join(g.root, 'runtime_shim/cjc_runtime_config.o'), 'utf8'), 'object');
});

test('pack requires a clean compiler checkout, including its schema and manifests', async t => {
  const f = await fixture(t);
  for (const rel of ['schema/CMakeLists.txt', 'cjpm.toml']) {
    const file = nested + '/' + rel;
    await fs.appendFile(path.join(f.root, file), '# unrelated edit\n');
    const dirty = f.run('pack');
    assert.equal(dirty.rc, 1, dirty.output);
    assert.ok(dirty.output.includes('handoff modified tracked source: ' + file), dirty.output);
    git(path.join(f.root, nested), 'restore', rel);
  }
  const clean = f.run('pack');
  assert.equal(clean.rc, 0, clean.output);
  const manifest = JSON.parse(await fs.readFile(path.join(f.archive, 'manifest.json')));
  assert.deepEqual(manifest.derivations, []);
});

async function windowsFixture(t) {
  const f = await fixture(t), origin = path.join(f.dir, 'llvm-origin');
  const checkout = nested + '/third_party/llvm-project', dir = path.join(f.root, checkout);
  const files = [...putLlvmFolders(origin), ...putLlvmWindowsFixes(origin)];
  await repository(origin, {});
  git(f.dir, 'clone', '-q', origin, dir);
  prepareWindowsLlvmSource(dir);
  const expected = new Map(files.map(({file, expected}) => [checkout + '/' + path.relative(origin, file).split(path.sep).join('/'), Buffer.from(expected)]));
  return {...f, expected, checkoutPath: checkout, handoff: mode => f.run(mode, 'stage0', {CJCJ_SRCBUILD_TARGET: 'windows-x64'})};
}

test('Windows handoff replays only LLVM fetch edits over the pinned sources', async t => {
  const f = await windowsFixture(t);
  const packed = f.handoff('pack');
  assert.equal(packed.rc, 0, packed.output);
  const manifest = JSON.parse(await fs.readFile(path.join(f.archive, 'manifest.json')));
  const names = members(path.join(f.archive, 'payload.tar'));
  assert.deepEqual(new Set(manifest.derivations.map(row => row.path)), new Set(f.expected.keys()));
  for (const row of manifest.derivations) {
    assert.equal(row.kind, 'windows-llvm-fetch-patch');
    assert.equal(row.checkout, f.checkoutPath);
    assert.equal(row.sha256, crypto.createHash('sha256').update(f.expected.get(row.path)).digest('hex'));
    assert.ok(!names.includes(row.path), row.path);
  }
  await f.checkout();
  const restored = f.handoff('restore');
  assert.equal(restored.rc, 0, restored.output);
  for (const [rel, bytes] of f.expected) assert.deepEqual(await fs.readFile(path.join(f.root, rel)), bytes, rel);
  assert.equal(git(path.join(f.root, nested), 'diff', '--name-only', 'HEAD'), '');
});

test('Windows LLVM replay rejects a dirty receiver, a wrong digest or a missing row', async t => {
  const f = await windowsFixture(t), rel = f.expected.keys().next().value;
  assert.equal(f.handoff('pack').rc, 0);
  git(f.root, 'restore', 'cjpm.toml');
  const dirty = f.handoff('restore');
  assert.notEqual(dirty.rc, 0);
  assert.match(dirty.output, /handoff derivation target is not the pinned file/);
  const manifest = path.join(f.archive, 'manifest.json'), data = JSON.parse(await fs.readFile(manifest));
  const row = data.derivations.find(row => row.path === rel);
  row.sha256 = '0'.repeat(64);
  await fs.writeFile(manifest, JSON.stringify(data));
  await f.checkout();
  const digest = f.handoff('restore');
  assert.notEqual(digest.rc, 0);
  assert.ok(digest.output.includes('handoff derivation digest mismatch: ' + rel), digest.output);
  data.derivations = data.derivations.filter(r => r !== row);
  await fs.writeFile(manifest, JSON.stringify(data));
  await f.checkout();
  const missing = f.handoff('restore');
  assert.notEqual(missing.rc, 0);
  assert.ok(missing.output.includes('handoff restored checkout differs from its manifest: ' + rel), missing.output);
});
