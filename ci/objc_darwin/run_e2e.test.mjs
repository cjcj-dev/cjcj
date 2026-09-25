import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  MARKERS,
  TOKEN,
  assertPositiveArgv,
  knownProductIssues,
  negativeArmRejected,
  negativeCompileArgs,
  positiveCompileArgs,
  positiveTokenAccepted,
  prepareNegativeHome,
  prepareStubImport,
  scanObjcModules,
} from './run_e2e.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const harness = path.join(repoRoot, 'ci', 'objc_darwin', 'run_e2e.mjs');
const workflow = path.join(repoRoot, '.github', 'workflows', 'objc-darwin-e2e.yml');

async function writeTree(root, {darwin = true, linux = false, extra = false} = {}) {
  if (darwin) {
    const dir = path.join(root, 'modules', 'darwin_aarch64_cjnative');
    await fs.mkdir(dir, {recursive: true});
    await fs.writeFile(path.join(dir, 'objc.lang.cjo'), 'objc.lang NSObject');
    await fs.writeFile(path.join(dir, 'objc.internal.cjo'), 'objc.internal objCMsgSend');
    if (extra) await fs.writeFile(path.join(dir, 'std.core.cjo'), 'std.core');
  }
  if (linux) {
    const dir = path.join(root, 'modules', 'linux_x86_64_cjnative');
    await fs.mkdir(dir, {recursive: true});
    await fs.writeFile(path.join(dir, 'objc.lang.cjo'), 'objc.lang objc.internal objCMsgSend');
  }
}

function writeFake(file, body) {
  return fs.writeFile(file, `#!/usr/bin/env node\n${body}`, {mode: 0o755});
}

const acceptanceFake = `
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
const home = process.env.CANGJIE_HOME || '';
const log = process.env.OBJC_FAKE_LOG;
if (log) fs.appendFileSync(log, JSON.stringify({args, home}) + '\\n');
function hasMarker(root) {
  if (!root) return false;
  const dir = path.join(root, 'modules', 'darwin_aarch64_cjnative');
  let names;
  try { names = fs.readdirSync(dir); } catch { return false; }
  const buf = Buffer.concat(names.filter((name) => name.endsWith('.cjo')).map((name) => fs.readFileSync(path.join(dir, name))));
  return ['objc.lang', 'objc.internal', 'objCMsgSend'].every((marker) => buf.includes(Buffer.from(marker)));
}
const outIdx = args.indexOf('-o');
if (outIdx < 0 || !args[outIdx + 1]) process.exit(2);
const out = args[outIdx + 1];
if (args.includes('--import-path') || !hasMarker(home)) {
  process.stderr.write('objc module unavailable\\n');
  process.exit(1);
}
fs.mkdirSync(path.dirname(out), {recursive: true});
fs.writeFileSync(out, '#!/bin/sh\\necho OBJC_DARWIN_E2E_OK\\n');
fs.chmodSync(out, 0o755);
`;

const rejectionFake = `
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
const log = process.env.OBJC_FAKE_LOG;
if (log) fs.appendFileSync(log, JSON.stringify({args, home: process.env.CANGJIE_HOME || ''}) + '\\n');
const outIdx = args.indexOf('-o');
if (outIdx < 0 || !args[outIdx + 1]) process.exit(2);
const out = args[outIdx + 1];
fs.mkdirSync(path.dirname(out), {recursive: true});
fs.writeFileSync(out, '#!/bin/sh\\necho OBJC_DARWIN_E2E_OK\\n');
fs.chmodSync(out, 0o755);
`;

function spawnHarness(env) {
  return spawnSync(process.execPath, [harness], {encoding: 'utf8', env: {...process.env, ...env}});
}

test('darwin module bytes count and linux module bytes do not', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-scan-'));
  try {
    await writeTree(root, {darwin: true, linux: true, extra: true});
    const hit = await scanObjcModules(root);
    assert.equal(hit.ok, true);
    assert.deepEqual(hit.missing, []);
    for (const marker of MARKERS) assert.ok(hit.hits[marker].length > 0, marker);
    assert.ok(hit.hits['objc.lang'].every((file) => file.includes(`${path.sep}darwin_`)));
    await fs.rm(path.join(root, 'modules', 'darwin_aarch64_cjnative'), {recursive: true});
    const miss = await scanObjcModules(root);
    assert.equal(miss.ok, false);
    assert.deepEqual(miss.missing, [...MARKERS]);
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

test('scan-only fails closed without invoking the compiler', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-scan-only-'));
  const log = path.join(root, 'fake.log');
  try {
    await writeTree(root, {darwin: false, linux: true});
    const fake = path.join(root, 'fake-cjc');
    await writeFake(fake, acceptanceFake);
    const result = spawnSync(process.execPath, [harness, '--scan-only'], {
      encoding: 'utf8',
      env: {...process.env, CANGJIE_HOME: root, OBJC_E2E_STAGE1: fake, OBJC_FAKE_LOG: log},
    });
    assert.equal(result.status, 2);
    assert.match(result.stdout, /scan_ok=false/);
    await assert.rejects(fs.stat(log));
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

test('positive arm accepts the official modules and the stub arm does not', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-accept-'));
  const log = path.join(root, 'fake.log');
  try {
    await writeTree(root, {darwin: true, linux: true});
    const fake = path.join(root, 'fake-cjc');
    await writeFake(fake, acceptanceFake);
    const result = spawnHarness({
      CANGJIE_HOME: root,
      OBJC_E2E_STAGE1: fake,
      OBJC_FAKE_LOG: log,
      OBJC_E2E_WORK: path.join(root, 'work'),
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /OBJC_E2E_ASSERT positive_token=true/);
    assert.match(result.stdout, /OBJC_E2E_ASSERT negative_rejected/);
    assert.match(result.stdout, /OBJC_E2E_ASSERT pass/);
    const lines = (await fs.readFile(log, 'utf8')).trim().split('\n').map((line) => JSON.parse(line));
    assert.equal(lines[0].home, root);
    assert.equal(lines[0].args.includes('--import-path'), false);
    assert.equal(lines[0].args.some((arg) => arg.includes('objc_cpointer_fixtures')), false);
    assert.equal(lines[1].args.includes('--import-path'), true);
    assert.notEqual(lines[1].home, root);
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

test('a compiler that accepts the stub is rejected', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-reject-'));
  try {
    await writeTree(root, {darwin: true});
    const fake = path.join(root, 'fake-cjc');
    await writeFake(fake, rejectionFake);
    const result = spawnHarness({
      CANGJIE_HOME: root,
      OBJC_E2E_STAGE1: fake,
      OBJC_E2E_WORK: path.join(root, 'work'),
    });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stdout, /positive_token=true/);
    assert.match(result.stdout, /negative_accepted_stub/);
    assert.doesNotMatch(result.stdout, /OBJC_E2E_ASSERT pass/);
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

test('negative home drops marker cjo files and keeps unrelated ones', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-strip-'));
  try {
    await writeTree(root, {darwin: true, linux: true, extra: true});
    const dest = path.join(root, 'stripped');
    await prepareNegativeHome(root, dest);
    const scan = await scanObjcModules(dest);
    assert.equal(scan.ok, false);
    const kept = path.join(dest, 'modules', 'darwin_aarch64_cjnative', 'std.core.cjo');
    assert.equal(await fs.readFile(kept, 'utf8'), 'std.core');
    await assert.rejects(fs.stat(path.join(dest, 'modules', 'linux_x86_64_cjnative')));
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});

test('stub import dir is only the declaration sources', async () => {
  const dest = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-stub-'));
  try {
    await prepareStubImport(repoRoot, dest);
    assert.deepEqual((await fs.readdir(dest)).sort(), ['internal.cj', 'lang.cj']);
    const lang = await fs.readFile(path.join(dest, 'lang.cj'), 'utf8');
    assert.match(lang, /package objc\.lang/);
    assert.doesNotMatch(lang, /objCMsgSend/);
  } finally {
    await fs.rm(dest, {recursive: true, force: true});
  }
});

test('positive argv refuses an import path and the stub tree', () => {
  const fixture = path.join(repoRoot, 'ci', 'objc_darwin', 'fixture', 'main.cj');
  const args = positiveCompileArgs(fixture, path.join(os.tmpdir(), 'out'));
  assert.doesNotThrow(() => assertPositiveArgv(args));
  assert.throws(() => assertPositiveArgv([...args, '--import-path', 'stub']), /must not pass --import-path/);
  assert.equal(negativeCompileArgs(fixture, 'out', 'stub').includes('--import-path'), true);
});

test('token and product-issue classifiers', () => {
  assert.equal(positiveTokenAccepted(0, `x\n${TOKEN}\n`), true);
  assert.equal(positiveTokenAccepted(1, TOKEN), false);
  assert.equal(positiveTokenAccepted(0, 'other'), false);
  assert.deepEqual(negativeArmRejected(1, 1, ''), {ok: true, reason: 'negative_rejected'});
  assert.deepEqual(negativeArmRejected(0, 0, TOKEN), {ok: false, reason: 'negative_accepted_stub'});
  assert.deepEqual(negativeArmRejected(0, 0, 'ran'), {ok: false, reason: 'negative_ran_without_token'});
  assert.deepEqual(knownProductIssues('InsertStringConversions returned None'), ['cjcj#206']);
  assert.deepEqual(knownProductIssues('enableInteropCJMapping'), ['cjcj#185']);
  assert.deepEqual(knownProductIssues('no known issue'), []);
});

test('fixture names the real mirror and the fixed token', async () => {
  const text = await fs.readFile(path.join(repoRoot, 'ci', 'objc_darwin', 'fixture', 'main.cj'), 'utf8');
  assert.match(text, /import objc\.lang\.\*/);
  assert.match(text, /import objc\.internal\.\*/);
  assert.match(text, /@ObjCImpl/);
  assert.match(text, /E2EImpl <: NSObject/);
  assert.match(text, new RegExp(TOKEN));
  assert.doesNotMatch(text, /--import-path/);
  assert.doesNotMatch(text, /objc_cpointer_fixtures/);
});

function permissionsBody(text) {
  const lines = text.split('\n');
  const start = lines.indexOf('permissions:');
  if (start < 0) return [];
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith('  ') && !line.startsWith('   ')) body.push(line);
    else break;
  }
  return body;
}

test('cross-run tuple lookup is granted actions: read', async () => {
  const text = await fs.readFile(workflow, 'utf8');
  const permissionKeys = text.split('\n').filter((line) => line.trim() === 'permissions:');
  assert.deepEqual(permissionKeys, ['permissions:']);
  const body = permissionsBody(text);
  assert.ok(body.includes('  contents: read'));
  console.log('OBJC_E2E_ASSERT permissions_block=present contents_read=true');
  assert.ok(body.includes('  actions: read'), 'actions_read=false; fetch_llvm_tuple cross-run gh api is 403 without it');
  const fetchAt = text.indexOf('- name: Download native fixed LLVM tuple\n');
  const buildAt = text.indexOf('- name: Build stage1\n');
  assert.ok(fetchAt >= 0 && buildAt > fetchAt);
  const fetchStep = text.slice(fetchAt, buildAt);
  assert.match(fetchStep, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(fetchStep, /fetch_llvm_tuple\.mjs/);
  assert.equal(fetchStep.includes('TUPLE_ARTIFACT_DIR'), false);
  console.log('OBJC_E2E_ASSERT actions_read=true tuple_fallback=cross-run');
});

test('workflow is a bash 3.2 macOS arm pinned to cjpm_pin.env', async () => {
  const text = await fs.readFile(workflow, 'utf8');
  const pin = await fs.readFile(path.join(repoRoot, 'ci', 'cjpm_pin.env'), 'utf8');
  assert.match(pin, /^CJCJ_TOOLCHAIN=nightly-\S+$/m);
  assert.match(text, /workflow_dispatch:/);
  assert.match(text, /runs-on: macos-15\n/);
  assert.match(text, /cat ci\/cjpm_pin\.env >> "\$GITHUB_ENV"/);
  assert.match(text, /cat ci\/runtime_pin\.env >> "\$GITHUB_ENV"/);
  assert.match(text, /ci\/setup_sdk\.mjs/);
  assert.match(text, /node ci\/objc_darwin\/run_e2e\.mjs --scan-only/);
  assert.match(text, /node ci\/objc_darwin\/run_e2e\.mjs\n/);
  assert.match(text, /fetch_llvm_tuple\.mjs/);
  assert.match(text, /exit 78/);
  assert.match(text, /build_cjcj\.mjs/);
  assert.match(text, /build_runtime\.mjs/);
  assert.doesNotMatch(text, /nightly-\d+\.\d+\.\d+-alpha\.\d+/);
  assert.doesNotMatch(text, /mapfile/);
  assert.doesNotMatch(text, /local -A/);
  assert.doesNotMatch(text, /srcbuild_git\.sh/);
  assert.doesNotMatch(text, /continue-on-error/);
  assert.doesNotMatch(text, /\|\| true/);
  assert.doesNotMatch(text, /platform-matrix\.yml/);
  const matrix = await fs.readFile(path.join(repoRoot, '.github', 'workflows', 'platform-matrix.yml'), 'utf8');
  assert.doesNotMatch(matrix, /objc-darwin-e2e|run_e2e\.mjs/);
});
