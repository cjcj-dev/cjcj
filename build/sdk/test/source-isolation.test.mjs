// 05b-stage1 and 06e-stage2 compile the same cjcj checkout. The first build's
// package-manager writes (cjpm.lock `version = 0` -> `version = 1`) used to stay
// behind, so 06e's runtime_shim/build_shim.mjs stamped `<sha>-dirty` and the
// final std built by that compiler was refused (STD_PROVENANCE 06-stdlib).
//
// These cases run the real compiler-stage entry (ci/bootstrap/sdk-native-stage.mjs
// --kind compiler) and the real stamping script on a pinned checkout; only the
// host cjpm is a stand-in that writes cjpm.lock the way cjpm 1.3 does and then
// produces no compiler (the stage stops at product lookup, after the build).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {compilerCommit, classifyStamp, writeStdProvenance} from '../../lib/provenance.mjs';
import {assertStdProvenance} from '../bootstrap.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const stage = path.join(repo, 'ci/bootstrap/sdk-native-stage.mjs');
const platform = `linux_${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}`;
const RUNTIME = 'b'.repeat(40);
const CHECKOUT_FILES = ['.gitignore', 'cjpm.toml', 'cjpm.lock', 'packages/option/cjpm.toml',
  'runtime_shim/build_shim.mjs', 'runtime_shim/cjc_runtime_config.c', 'runtime_shim/cjc_heap_defaults.c'];

function zxCli() {
  const found = spawnSync('sh', ['-c', 'command -v zx'], {encoding: 'utf8'}).stdout.trim();
  if (!found) throw new Error('ZX_REQUIRED: runtime_shim/build_shim.mjs is a zx script');
  const cli = fs.realpathSync(found);
  return /\.m?js$/.test(cli) ? cli : found;
}
const git = (dir, ...argv) => {
  const r = spawnSync('git', ['-C', dir, ...argv], {encoding: 'utf8', env: {...process.env,
    GIT_AUTHOR_NAME: 'fixture', GIT_AUTHOR_EMAIL: 'fixture@invalid', GIT_COMMITTER_NAME: 'fixture', GIT_COMMITTER_EMAIL: 'fixture@invalid'}});
  assert.equal(r.status, 0, `git ${argv.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
};

function fixture(label) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `source-isolation-${label}-`));
  const source = path.join(root, 'compiler-stage2-source');
  for (const rel of CHECKOUT_FILES) {
    fs.mkdirSync(path.dirname(path.join(source, rel)), {recursive: true});
    fs.copyFileSync(path.join(repo, rel), path.join(source, rel));
  }
  fs.mkdirSync(path.join(source, 'src'));
  fs.writeFileSync(path.join(source, 'src/main.cj'), 'main(): Int64 { 0 }\n');
  git(source, 'init', '-q'); git(source, 'add', '-A'); git(source, 'commit', '-q', '-m', 'pinned');
  const commit = git(source, 'rev-parse', 'HEAD');
  // N's installed shim pair, as compilerNativeShim reads it from the stage SDK.
  const sdk = path.join(root, 'sdk'), object = 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
  fs.mkdirSync(path.dirname(path.join(sdk, object)), {recursive: true});
  fs.writeFileSync(path.join(sdk, object), 'installed shim object\n');
  const bytes = fs.readFileSync(path.join(sdk, object));
  fs.writeFileSync(path.join(sdk, 'BUILD-INPUTS.json'), JSON.stringify({commits: {shim: commit, compiler: 'c'.repeat(40), llvm: 'd'.repeat(40)},
    nativeShim: {source: {commit}, compiler: {commit: 'c'.repeat(40)}, llvm: {commit: 'd'.repeat(40)},
      object: {path: object, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')}}}));
  // The host package manager: writes cjpm.lock like cjpm 1.3 and builds nothing.
  const host = path.join(root, 'host'), cjpm = path.join(host, 'tools/bin/cjpm');
  fs.mkdirSync(path.dirname(cjpm), {recursive: true});
  fs.writeFileSync(cjpm, `#!${process.execPath}\nconst fs=require('node:fs');\n`
    + `fs.appendFileSync(${JSON.stringify(path.join(root, 'cjpm-runs'))},process.cwd()+'\\n');\n`
    + `const lock='cjpm.lock';fs.writeFileSync(lock,fs.readFileSync(lock,'utf8').replace(/^version = 0$/m,'version = 1'));\n`);
  fs.chmodSync(cjpm, 0o755);
  return {root, source, commit, sdk, host, runs: () => fs.existsSync(path.join(root, 'cjpm-runs'))
    ? fs.readFileSync(path.join(root, 'cjpm-runs'), 'utf8').trim().split('\n').length : 0};
}

function compilerStage(f, id) {
  const argv = [process.execPath, stage, '--kind', 'compiler', '--phase', 'stage2', '--source', f.source, '--commit', f.commit,
    '--sdk', f.sdk, '--host', f.host, '--output', path.join(f.root, id), '--target-dir', path.join(f.root, `${id}-target`),
    '--platform', platform, '--jobs', '2', '--zx', zxCli()];
  const env = {...process.env}; delete env.SOURCE_SDK_VERSION; delete env.CJCJ_COMMIT;
  const r = spawnSync(argv[0], argv.slice(1), {cwd: f.root, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const text = (r.stdout || '') + (r.stderr || '');
  fs.writeFileSync(path.join(f.root, `${id}.log`), text);
  const stamp = text.match(/^CJCJ_COMMIT=(\S+)$/m)?.[1];
  return {rc: r.status, text, stamp, object: path.join(f.source, 'runtime_shim/cjc_runtime_config.o')};
}

// The final std as writeStdProvenance records it for this compiler, then the
// bootstrap acceptance of that record (bootstrap.mjs, std steps).
async function finalStd(f, compiler, id) {
  const sourceDir = path.join(f.root, `${id}-std-source`), prefix = path.join(f.root, id);
  fs.mkdirSync(sourceDir); fs.mkdirSync(path.join(prefix, 'lib'), {recursive: true});
  fs.writeFileSync(path.join(prefix, 'lib/libcangjie-std-core.a'), 'std\n');
  await writeStdProvenance({sourceDir, sourceRevision: RUNTIME, installPrefix: prefix, compiler,
    buildSdk: f.sdk, coloured: 'true', preflightC2: 'not run', failClosed: false});
  return fs.readFileSync(path.join(prefix, 'PROVENANCE.txt'), 'utf8');
}

test('clean control: 05b then 06e on one checkout; the cjpm.lock write is given back and 06e stamps the pinned commit', async () => {
  const f = fixture('clean');
  const lockBefore = fs.readFileSync(path.join(f.source, 'cjpm.lock'));
  assert.match(lockBefore.toString(), /^version = 0$/m, 'the pinned lock carries version = 0');
  const first = compilerStage(f, 'stage1');
  assert.equal(f.runs(), 1, `05b reached cjpm build: ${first.text}`);
  assert.notEqual(first.rc, 0, 'the stand-in builds no compiler, so the stage stops at product lookup');
  assert.equal(first.stamp, f.commit);
  assert.deepEqual(fs.readFileSync(path.join(f.source, 'cjpm.lock')), lockBefore, 'cjpm.lock bytes given back after the build');
  assert.equal(git(f.source, 'status', '--porcelain'), '', 'checkout is clean for the next stage');
  const second = compilerStage(f, 'stage2');
  assert.equal(f.runs(), 2, `06e reached cjpm build: ${second.text}`);
  assert.equal(second.stamp, f.commit, '06e stamps the clean pinned commit, not -dirty');
  const stamped = await compilerCommit(second.object);
  assert.equal(stamped, f.commit); assert.equal(classifyStamp(stamped), 'stamped');
  const prov = await finalStd(f, second.object, 'final-std');
  assert.match(prov, new RegExp(`^BUILT_BY_CJC = ${f.commit}$`, 'm'));
  assert.doesNotThrow(() => assertStdProvenance(prov, {runtime: RUNTIME, cjcj: f.commit}, '06-stdlib'));
  console.log('SOURCE_ISOLATION_CLEAN_ASSERT_REACHED');
});

test('dirty control: a tracked source edit made before the build stays, is stamped -dirty, and its final std is refused', async () => {
  const f = fixture('dirty-source');
  fs.appendFileSync(path.join(f.source, 'src/main.cj'), '// local edit\n');
  const result = compilerStage(f, 'stage2');
  assert.equal(f.runs(), 1, result.text);
  assert.equal(result.stamp, `${f.commit}-dirty`);
  assert.match(git(f.source, 'status', '--porcelain'), /src\/main\.cj/, 'the real edit is not undone');
  const stamped = await compilerCommit(result.object);
  assert.equal(classifyStamp(stamped), 'stamped-unknown');
  const prov = await finalStd(f, result.object, 'final-std');
  assert.match(prov, /^BUILT_BY_CJC = unresolved: /m);
  assert.throws(() => assertStdProvenance(prov, {runtime: RUNTIME, cjcj: f.commit}, '06-stdlib'), /^Error: STD_PROVENANCE 06-stdlib$/);
  console.log('SOURCE_ISOLATION_DIRTY_SOURCE_ASSERT_REACHED');
});

test('dirty control: a cjpm.lock edit made before the build is given back as edited, not reset to HEAD, and stays rejected', async () => {
  const f = fixture('dirty-lock');
  const edited = '# local edit\n' + fs.readFileSync(path.join(f.source, 'cjpm.lock'), 'utf8');
  fs.writeFileSync(path.join(f.source, 'cjpm.lock'), edited);
  const result = compilerStage(f, 'stage2');
  assert.equal(f.runs(), 1, result.text);
  assert.equal(result.stamp, `${f.commit}-dirty`);
  assert.equal(fs.readFileSync(path.join(f.source, 'cjpm.lock'), 'utf8'), edited, 'pre-build bytes, not the build write and not HEAD');
  const prov = await finalStd(f, result.object, 'final-std');
  assert.throws(() => assertStdProvenance(prov, {runtime: RUNTIME, cjcj: f.commit}, '06-stdlib'), /STD_PROVENANCE/);
  console.log('SOURCE_ISOLATION_DIRTY_LOCK_ASSERT_REACHED');
});

test('std provenance acceptance is line-exact: a -dirty or foreign BUILT_BY_CJC and an uncoloured std are refused', () => {
  const cjcj = 'a'.repeat(40);
  const record = (built, coloured = 'true') => `STD_SOURCE_COMMIT = ${RUNTIME}\nBUILT_BY_CJC = ${built}\nCOLOURED = ${coloured}\n`;
  assert.doesNotThrow(() => assertStdProvenance(record(cjcj), {runtime: RUNTIME, cjcj}, 'x'));
  for (const text of [record(`${cjcj}-dirty`), record('c'.repeat(40)), record(cjcj, 'false'),
    record(cjcj).replace(RUNTIME, `${RUNTIME}-dirty`)])
    assert.throws(() => assertStdProvenance(text, {runtime: RUNTIME, cjcj}, 'x'), /^Error: STD_PROVENANCE x$/);
});
