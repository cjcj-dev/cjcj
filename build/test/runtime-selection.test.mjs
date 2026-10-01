import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {sourceFetchArguments} from '../lib/git.mjs';
import {fixture} from '../../ci/release/prepare_bootstrap_fixture.mjs';

const repo = path.resolve(import.meta.dirname, '../..');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const tuple = 'linux_x86_64_cjnative';
const pin = Object.fromEntries(fs.readFileSync(path.join(repo, 'ci/runtime_pin.env'), 'utf8')
  .trim().split('\n').map(line => line.split('=')));
function execute(command, env = process.env) {
  const result = spawnSync(command[0], command.slice(1), {env, encoding: 'utf8'});
  return {...result, output: result.stdout + result.stderr};
}
function ok(command, env) {
  const result = execute(command, env);
  assert.equal(result.status, 0, result.output);
  return result.stdout.trim();
}
function exported(result) {
  assert.equal(result.status, 0, result.stderr);
  return Object.fromEntries(result.stdout.split('\n').filter(line => /^[A-Z][A-Z0-9_]*=/.test(line))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}
function refreshRoot(f) {
  const file = path.join(f.runtime, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(file));
  for (const rel of Object.keys(manifest.files)) manifest.files[rel] = hash(path.join(f.runtime, rel));
  fs.writeFileSync(file, JSON.stringify(manifest));
  f.env.COLOUR_RT_MANIFEST_SHA256 = hash(file);
}
function useFormalRuntime(f) {
  delete f.env.CJCJ_RUNTIME_REF_OVERRIDE; delete f.env.CJCJ_ALLOW_RUNTIME_OVERRIDE;
  f.env.RUNTIME_REF = pin.RUNTIME_REF;
  const file = path.join(f.runtime, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(file)); manifest.runtime_sha = pin.RUNTIME_REF;
  fs.writeFileSync(file, JSON.stringify(manifest)); refreshRoot(f);
  const headerFile = path.join(f.sdk, 'build/build/shim-headers.json');
  const header = JSON.parse(fs.readFileSync(headerFile)); header.runtime.sha = pin.RUNTIME_REF;
  fs.writeFileSync(headerFile, JSON.stringify(header));
  const paired = path.join(f.sdk, 'third_party/paired-runtime');
  fs.rmSync(paired, {recursive: true});
  ok(['git', 'init', '-q', paired]);
  ok(['git', '-C', paired, 'remote', 'add', 'origin', pin.RUNTIME_SRC_URL]);
  const source = process.env.GC_FIX_RUNTIME_CHECKOUT;
  const fetch = source ? ['fetch', '--depth', '1', source, pin.RUNTIME_REF]
    : sourceFetchArguments(pin.RUNTIME_SRC_URL, pin.RUNTIME_REF);
  ok(['git', '-C', paired, ...fetch]);
  ok(['git', '-C', paired, 'checkout', '-q', '--detach', 'FETCH_HEAD']);
}
function assembled(f, selected = f.env.RUNTIME_REF, expectedFailure) {
  const libs = path.join(f.dir, 'elf');
  fs.mkdirSync(libs);
  const files = {
    runtime: `int g_cjLoadBadMask; const char stamp[]="CJRT-COMMIT:${selected}";`,
    host: 'int host_only;', bounds: 'int bounds_only;',
    std: 'extern int g_cjLoadBadMask; int *reference=&g_cjLoadBadMask;',
  };
  for (const [name, source] of Object.entries(files)) {
    fs.writeFileSync(path.join(libs, name + '.c'), source);
    ok(['cc', '-fPIC', '-c', path.join(libs, name + '.c'), '-o', path.join(libs, name + '.o')]);
    ok(['cc', '-shared', path.join(libs, name + '.o'), '-o', path.join(libs, name + '.so')]);
    ok(['ar', 'rcs', path.join(libs, name + '.a'), path.join(libs, name + '.o')]);
  }
  for (const [rel, name] of [
    [`runtime/lib/${tuple}/libcangjie-runtime.so`, 'runtime.so'],
    [`runtime/lib/${tuple}/libboundscheck.so`, 'bounds.so'],
    [`lib/${tuple}/libcangjie-runtime.a`, 'runtime.a'],
    [`lib/${tuple}/libcangjie-std-core.a`, 'std.a'],
    [`runtime/lib/${tuple}/libcangjie-std-core.so`, 'std.so'],
    ['lib/libstdFFI.so', 'host.so'],
  ]) fs.copyFileSync(path.join(libs, name), path.join(f.runtime, rel));
  // SDK assembler itself records and checks this compiler/std lineage.
  const compiler = path.join(f.dir, 'compiler');
  fs.copyFileSync('/bin/true', compiler);
  fs.writeFileSync(path.join(f.runtime, 'std-producer.json'), JSON.stringify({compiler_sha256: hash(compiler)}));
  refreshRoot(f);
  const inputs = exported(f.run());
  const base = path.join(f.dir, 'sdk-base');
  fs.mkdirSync(path.join(base, 'bin'), {recursive: true});
  fs.copyFileSync(compiler, path.join(base, 'bin/cjc'));
  fs.writeFileSync(path.join(base, 'envsetup.sh'), '# isolated SDK fixture environment\n');
  for (const rel of [`runtime/lib/${tuple}/libcangjie-runtime.so`, `runtime/lib/${tuple}/libboundscheck.so`]) {
    fs.mkdirSync(path.dirname(path.join(base, rel)), {recursive: true});
    fs.copyFileSync(path.join(libs, 'host.so'), path.join(base, rel));
  }
  for (const rel of [`lib/${tuple}/libcangjie-runtime.a`, `lib/${tuple}/libcangjie-std-core.a`]) {
    fs.mkdirSync(path.dirname(path.join(base, rel)), {recursive: true});
    fs.copyFileSync(path.join(libs, 'host.a'), path.join(base, rel));
  }
  fs.mkdirSync(path.join(base, 'modules', tuple), {recursive: true});
  fs.writeFileSync(path.join(base, 'modules', tuple, 'std.core.cjo'), 'host module fixture');
  fs.copyFileSync(path.join(libs, 'host.so'), path.join(base, 'runtime/lib', tuple, 'libcangjie-std-core.so'));
  fs.copyFileSync(path.join(libs, 'host.so'), path.join(base, 'lib/libstdFFI.so'));
  fs.writeFileSync(path.join(base, 'std-producer.json'), JSON.stringify({compiler_sha256: hash(compiler)}));
  const target = path.join(f.dir, 'sdk-target');
  const command = ['bash', path.join(repo, 'ci/bootstrap/sdk_build.sh'),
    '--from', base, '--to', target, '--target', tuple,
    '--runtime-pin', inputs.CJCJ_BOOTSTRAP_RUNTIME_PIN, '--runtime', f.runtime,
    '--runtime-commit', selected, '--std', f.runtime, '--cjc', compiler,
    '--colour-runtime', path.join(libs, 'runtime.so'), '--host-runtime', path.join(libs, 'host.so')];
  const result = execute(command, f.env);
  // Inspect the actual assembler result/lock, not a synthesized resolver return.
  console.log(`SDK_SELECTION_ASSERT selected=${selected} rc=${result.status} product=${hash(path.join(repo, 'ci/bootstrap/sdk_build.sh'))} runtime=${hash(path.join(libs, 'runtime.so'))} boundscheck=${hash(path.join(libs, 'bounds.so'))} compiler=${hash(compiler)}`);
  if (expectedFailure) {
    assert.notEqual(result.status, 0);
    assert.ok(result.output.includes(expectedFailure), result.output);
    console.log(`SDK_STAMP_TARGET_ASSERT_EXECUTED ${expectedFailure}`);
    return;
  }
  assert.equal(result.status, 0, result.output);
  const lock = JSON.parse(fs.readFileSync(path.join(target, 'SDK.lock.json')));
  assert.equal(lock.components.runtime.commit, selected);
  assert.equal(lock.files[`runtime/lib/${tuple}/libboundscheck.so`].sha256, hash(path.join(libs, 'bounds.so')));
  console.log(`SDK_SELECTION_LOCK runtime=${lock.components.runtime.commit} lock=${hash(path.join(target, 'SDK.lock.json'))}`);
  return {inputs, target, libs, command, compiler, base};
}
function sdkConsumer(f, a) {
  return execute([process.execPath, '--input-type=module', '-e',
    `import {verifyBootstrapRuntimeSdk} from ${JSON.stringify(path.join(repo, 'ci/bootstrap/runtime_sdk.mjs'))};
     await verifyBootstrapRuntimeSdk(process.argv[1], process.argv[2]);`, a.target, tuple],
  {...f.env, ...a.inputs});
}
for (const candidate of [false, true]) {
  test(`real loader, prepare, SDK assembler and independent verifier: ${candidate ? 'authorized candidate' : 'formal default'}`, () => fixture(f => {
    if (!candidate) useFormalRuntime(f);
    const loaderEnv = path.join(f.dir, 'loader.env');
    ok([process.execPath, path.join(repo, 'ci/load_runtime_pin.mjs')], {...f.env, GITHUB_ENV: loaderEnv});
    assert.match(fs.readFileSync(loaderEnv, 'utf8'), new RegExp(`RUNTIME_REF=${f.env.RUNTIME_REF}`));
    const a = assembled(f);
    const verified = sdkConsumer(f, a);
    console.log(`SDK_CONSUMER_ASSERT candidate=${candidate} rc=${verified.status} ${verified.output}`);
    assert.equal(verified.status, 0, verified.output);
    assert.match(verified.output, new RegExp(`BOOTSTRAP_SDK_RUNTIME_VERIFIED runtime=${f.env.RUNTIME_REF}`));
    // Host-role assembler must keep its official runtime/std independent.
    const host = path.join(f.dir, 'sdk-host');
    fs.mkdirSync(path.join(a.base, 'runtime/lib', tuple), {recursive: true});
    fs.copyFileSync(path.join(a.libs, 'host.so'), path.join(a.base, 'runtime/lib', tuple, 'libcangjie-runtime.so'));
    const h = execute(['bash', path.join(repo, 'ci/bootstrap/sdk_build.sh'), '--from', a.base,
      '--to', host, '--host', '--runtime-pin', a.inputs.CJCJ_BOOTSTRAP_RUNTIME_PIN,
      '--colour-runtime', path.join(a.libs, 'runtime.so'), '--host-runtime', path.join(a.libs, 'host.so')], f.env);
    assert.equal(h.status, 0, h.output);
    assert.equal(hash(path.join(host, 'runtime/lib', tuple, 'libcangjie-runtime.so')), hash(path.join(a.libs, 'host.so')));
    console.log(`HOST_CONTROL_ASSERT rc=${h.status}`);
  }));
}
for (const [label, corrupt, marker] of [
  ['SDK boundscheck', (f, a) => fs.appendFileSync(path.join(a.target, 'runtime/lib', tuple, 'libboundscheck.so'), 'changed'), 'BOOTSTRAP_SDK_RUNTIME_MISMATCH: runtime/lib/'],
  ['SDK runtime', (f, a) => fs.appendFileSync(path.join(a.target, 'runtime/lib', tuple, 'libcangjie-runtime.so'), 'changed'), 'BOOTSTRAP_SDK_RUNTIME_MISMATCH: runtime/lib/'],
  ['SDK archive', (f, a) => fs.appendFileSync(path.join(a.target, 'lib', tuple, 'libcangjie-runtime.a'), 'changed'), 'BOOTSTRAP_SDK_RUNTIME_MISMATCH: lib/'],
  ['SDK lock', (f, a) => {
    const file = path.join(a.target, 'SDK.lock.json'); const lock = JSON.parse(fs.readFileSync(file));
    lock.files[`runtime/lib/${tuple}/libboundscheck.so`].sha256 = '0'.repeat(64);
    fs.writeFileSync(file, JSON.stringify(lock));
  }, 'BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: runtime/lib/'],
]) {
  test(`actual SDK consumer rejects changed ${label}`, () => fixture(f => {
    const a = assembled(f); corrupt(f, a);
    const result = sdkConsumer(f, a);
    console.log(`SDK_MISMATCH_ASSERT ${label} rc=${result.status} marker=${marker}`);
    assert.notEqual(result.status, 0);
    assert.match(result.output, new RegExp(marker));
  }));
}
for (const [label, edit, marker] of [
  ['authorization', f => delete f.env.CJCJ_ALLOW_RUNTIME_OVERRIDE, 'explicit dry-run/test authorization'],
  ['short SHA', f => f.env.CJCJ_RUNTIME_REF_OVERRIDE = 'd', 'full 40-character'],
  ['environment ref', f => f.env.RUNTIME_REF = 'e'.repeat(40), 'runtime ref mismatch'],
  ['environment URL', f => f.env.RUNTIME_SRC_URL = 'https://example.invalid/wrong', 'runtime source URL mismatch'],
  ['external pin', f => {
    const file = path.join(f.dir, 'wrong.env');
    fs.writeFileSync(file, `RUNTIME_REF=${pin.RUNTIME_REF}\nRUNTIME_SRC_URL=${pin.RUNTIME_SRC_URL}\n`);
    f.env.CJCJ_BOOTSTRAP_RUNTIME_PIN = file;
  }, 'runtime selection pin mismatch'],
  ['header source', f => {
    const file = path.join(f.sdk, 'build/build/shim-headers.json'); const m = JSON.parse(fs.readFileSync(file));
    m.runtime.sha = pin.RUNTIME_REF; fs.writeFileSync(file, JSON.stringify(m));
  }, 'SHIM_HEADERS_SOURCE_MISMATCH: runtime'],
  ['header HEAD', f => ok(['git', '-C', path.join(f.sdk, 'third_party/paired-runtime'), '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-q', '-m', 'wrong headers source']), 'SHIM_HEADERS_SOURCE_HEAD_MISMATCH: runtime'],
  ['header bytes', f => fs.appendFileSync(path.join(f.sdk, 'build/build/include/fixture.h'), 'changed'), 'SHIM_HEADERS_DIGEST_MISMATCH'],
]) {
  test(`real preparation rejects ${label} at its target guard`, () => fixture(f => {
    edit(f); const result = f.run();
    console.log(`SELECTION_REJECTION_ASSERT ${label} rc=${result.status}`);
    assert.notEqual(result.status, 0);
    assert.ok(result.stderr.includes(marker), result.stderr);
    assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_RUNTIME_PIN=/m);
  }));
}

test('real prepare publishes the selected pin after full-root validation', () => fixture(f => {
  const result = f.run();
  const file = path.join(f.env.CJCJ_BOOTSTRAP_INPUTS_WORK, 'runtime-selection.env');
  const record = fs.existsSync(file) ? Object.fromEntries(fs.readFileSync(file, 'utf8').trim().split('\n').map(x => x.split('='))) : {};
  const observed = {rc: result.status, ref: record.RUNTIME_REF, url: record.RUNTIME_SRC_URL};
  console.log(`SELECTION_PUBLICATION_TARGET_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rc: 0, ref: f.env.RUNTIME_REF, url: pin.RUNTIME_SRC_URL});
  console.log('SELECTION_PUBLICATION_TARGET_ASSERT_EXECUTED');
}));

test('real SDK assembly rejects a manifest-valid runtime with the wrong commit stamp', () => fixture(f => {
  assembled(f, 'e'.repeat(40), 'rule=RUNTIME_PIN');
}));

test('formal-default preparation still publishes the formal pin', () => fixture(f => {
  useFormalRuntime(f);
  const result = f.run();
  const selected = path.join(f.env.CJCJ_BOOTSTRAP_INPUTS_WORK, 'runtime-selection.env');
  const text = fs.existsSync(selected) ? fs.readFileSync(selected, 'utf8') : '';
  console.log(`FORMAL_PUBLICATION_CONTROL_ASSERT rc=${result.status} pin=${text.trim()}`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(text, new RegExp(`RUNTIME_REF=${pin.RUNTIME_REF}`));
}));

test('actual stage3 entry binds source and both SDK SOs before stage2 execution', () => fixture(f => {
  fs.mkdirSync(path.join(f.runtimeSource, 'stdlib'));
  fs.writeFileSync(path.join(f.runtimeSource, 'stdlib/README'), 'input source identity fixture');
  for (const args of [['init', '-q', f.runtimeSource], ['-C', f.runtimeSource, 'add', '.'],
    ['-C', f.runtimeSource, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
      'commit', '-q', '-m', 'runtime source identity fixture']]) ok(['git', ...args]);
  const selected = ok(['git', '-C', f.runtimeSource, 'rev-parse', 'HEAD']);
  f.env.RUNTIME_REF = selected; f.env.CJCJ_RUNTIME_REF_OVERRIDE = selected;
  const paired = path.join(f.sdk, 'third_party/paired-runtime');
  ok(['git', '-C', paired, 'fetch', '-q', f.runtimeSource, selected]);
  ok(['git', '-C', paired, 'checkout', '-q', '--detach', 'FETCH_HEAD']);
  for (const [file, key] of [[path.join(f.runtime, 'manifest.json'), 'runtime_sha'],
    [path.join(f.sdk, 'build/build/shim-headers.json'), 'runtime']]) {
    const data = JSON.parse(fs.readFileSync(file));
    if (key === 'runtime') data.runtime.sha = selected; else data[key] = selected;
    fs.writeFileSync(file, JSON.stringify(data));
  }
  refreshRoot(f);
  const a = assembled(f);
  const workspace = path.join(f.dir, 'stage3-workspace');
  const sdk = path.join(workspace, 'software/cangjie');
  fs.mkdirSync(path.dirname(sdk), {recursive: true});
  fs.cpSync(a.target, sdk, {recursive: true, verbatimSymlinks: true});
  fs.cpSync(f.runtimeSource, path.join(workspace, 'cangjie_runtime'), {recursive: true});
  const env = {...f.env, ...a.inputs, CANGJIE_WORKSPACE: workspace, GITHUB_WORKSPACE: repo,
    CJCJ_BOOTSTRAP_WORK: path.join(workspace, 'bootstrap-work'), CJCJ_STAGE3_STDLIB_BUILD_TYPE: 'release',
    CJCJ_STAGE3_DRY_RUN: '1', CJCJ_STAGE3_DRY_RUN_FINAL_STD: path.join(workspace, 'unused-std')};
  const command = ['npx', '--yes', 'zx@8', path.join(repo, 'ci/srcbuild/steps/build-stage3.mjs')];
  const valid = execute(command, env);
  // Stop at the existing absent stage2 handoff. This is guard admission, not
  // compiler execution or authorization of the synthetic SDK's std ABI.
  assert.match(valid.output, new RegExp(`BOOTSTRAP_SDK_RUNTIME_VERIFIED runtime=${selected}`), valid.output);
  assert.notEqual(valid.status, 0);
  fs.appendFileSync(path.join(sdk, 'runtime/lib', tuple, 'libboundscheck.so'), 'changed');
  const bounds = execute(command, env);
  assert.notEqual(bounds.status, 0);
  assert.match(bounds.output, /BOOTSTRAP_SDK_RUNTIME_MISMATCH: runtime\/lib\/.*libboundscheck.so/);
  assert.doesNotMatch(bounds.output, /BOOTSTRAP_SDK_RUNTIME_VERIFIED/);
  console.log(`STAGE3_ENTRY_TARGET_ASSERT source=${selected} accepted-guard=${valid.status} wrong-bounds=${bounds.status} no-stage2-executed=1`);
  // Restore the shared pair and alter only the source HEAD.
  fs.copyFileSync(path.join(a.libs, 'bounds.so'), path.join(sdk, 'runtime/lib', tuple, 'libboundscheck.so'));
  ok(['git', '-C', path.join(workspace, 'cangjie_runtime'), '-c', 'user.name=Zxilly',
    '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-q', '-m', 'wrong source']);
  const source = execute(command, env);
  assert.notEqual(source.status, 0); assert.match(source.output, /BOOTSTRAP_RUNTIME_SOURCE_MISMATCH/);
  console.log('STAGE3_SOURCE_TARGET_ASSERT_EXECUTED');
}));

for (const candidate of [false, true]) {
test(`actual GHA launcher passes the validated selected file into bootstrap: ${candidate ? 'candidate' : 'formal default'}`, () => fixture(f => {
  if (!candidate) useFormalRuntime(f);
  const inputs = exported(f.run());
  const env = {...f.env, ...inputs, GITHUB_WORKSPACE: repo, CANGJIE_WORKSPACE: path.join(f.dir, 'workspace')};
  const result = execute(['bash', path.join(repo, 'ci/bootstrap/gha_run.sh'), 'stage0'], env);
  const observed = /INPUT runtime-pin path=(.+) sha256=([a-f0-9]{64})/.exec(result.output);
  console.log(`GHA_RUNTIME_PIN_TARGET_ASSERT rc=${result.status} pin=${observed?.[1]} digest=${observed?.[2]}`);
  const actual = observed ? Object.fromEntries(fs.readFileSync(observed[1], 'utf8').trim().split('\n')
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)])) : {};
  assert.deepEqual([actual.RUNTIME_REF, actual.RUNTIME_SRC_URL],
    [f.env.RUNTIME_REF, pin.RUNTIME_SRC_URL], result.output);
  if (candidate) assert.deepEqual([observed[1], observed[2]],
    [inputs.CJCJ_BOOTSTRAP_RUNTIME_PIN, hash(inputs.CJCJ_BOOTSTRAP_RUNTIME_PIN)], result.output);
  // Synthetic fixture stops at the existing compiler-source qualification gate.
  assert.notEqual(result.status, 0);
  console.log('GHA_RUNTIME_PIN_TARGET_ASSERT_EXECUTED no-compilation=1');
}));
}
