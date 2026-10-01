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
  {...Object.fromEntries(Object.entries(f.env).filter(([key]) => !key.startsWith('COLOUR_RT_'))), ...a.inputs});
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
    assert.match(verified.output, new RegExp(`BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED runtime=${f.env.RUNTIME_REF}`));
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

test('actual runtime consumer rejects host role in assembly lock', () => fixture(f => {
  const a = assembled(f), file = path.join(a.target, 'SDK.lock.json');
  const lock = JSON.parse(fs.readFileSync(file)); lock.role = 'host';
  fs.writeFileSync(file, JSON.stringify(lock));
  const rejected = sdkConsumer(f, a); assert.notEqual(rejected.status, 0);
  assert.match(rejected.output, /BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: role/, rejected.output);
  console.log('RUNTIME_CONSUMER_ROLE_TARGET_ASSERT_EXECUTED');
}));

for (const rel of [`runtime/lib/${tuple}/libcangjie-runtime.so`, `lib/${tuple}/libcangjie-runtime.a`]) {
  test(`actual runtime consumer rejects self-consistent wrong chapter: ${rel}`, () => fixture(f => {
    const a = assembled(f);
    const file = path.join(a.target, rel);
    const bytes = fs.readFileSync(file);
    const wrong = Buffer.from(bytes.toString('latin1').replaceAll(`CJRT-COMMIT:${f.env.RUNTIME_REF}`, `CJRT-COMMIT:${'e'.repeat(40)}`), 'latin1');
    assert.notDeepEqual(wrong, bytes);
    fs.writeFileSync(file, wrong); fs.writeFileSync(path.join(f.runtime, rel), wrong);
    refreshRoot(f); a.inputs.COLOUR_RT_MANIFEST_SHA256 = f.env.COLOUR_RT_MANIFEST_SHA256;
    const lockFile = path.join(a.target, 'SDK.lock.json'), lock = JSON.parse(fs.readFileSync(lockFile));
    lock.files[rel].sha256 = hash(file);
    if (rel.endsWith('.so')) lock.components.runtime.so_sha256 = hash(file);
    fs.writeFileSync(lockFile, JSON.stringify(lock));
    const rejected = sdkConsumer(f, a);
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.output, /BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH/, rejected.output);
    console.log(`RUNTIME_CONSUMER_CHAPTER_TARGET_ASSERT file=${rel} self-consistent-hashes=1`);
  }));
}

test('formal-default preparation still publishes the formal pin', () => fixture(f => {
  useFormalRuntime(f);
  const result = f.run();
  const selected = path.join(f.env.CJCJ_BOOTSTRAP_INPUTS_WORK, 'runtime-selection.env');
  const text = fs.existsSync(selected) ? fs.readFileSync(selected, 'utf8') : '';
  console.log(`FORMAL_PUBLICATION_CONTROL_ASSERT rc=${result.status} pin=${text.trim()}`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(text, new RegExp(`RUNTIME_REF=${pin.RUNTIME_REF}`));
}));

for (const formal of [false, true]) {
test(`actual stage3 entry verifies promoted SDK before stage2: ${formal ? 'formal default' : 'candidate'}`, () => fixture(f => {
  fs.mkdirSync(path.join(f.runtimeSource, 'stdlib'));
  fs.writeFileSync(path.join(f.runtimeSource, 'stdlib/README'), 'input source identity fixture');
  for (const args of [['init', '-q', f.runtimeSource], ['-C', f.runtimeSource, 'add', '.'],
    ['-C', f.runtimeSource, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
      'commit', '-q', '-m', 'runtime source identity fixture']]) ok(['git', ...args],
        {...process.env, GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z', GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'});
  if (formal) {
    assert.ok(process.env.GC_FIX_RUNTIME_CHECKOUT, 'formal source objects required');
    ok(['git', '-C', f.runtimeSource, 'fetch', '--update-shallow', '-q', process.env.GC_FIX_RUNTIME_CHECKOUT, pin.RUNTIME_REF]);
    ok(['git', '-C', f.runtimeSource, 'checkout', '-q', '--detach', 'FETCH_HEAD']);
  }
  const selected = ok(['git', '-C', f.runtimeSource, 'rev-parse', 'HEAD']);
  f.env.RUNTIME_REF = selected; f.env.CJCJ_RUNTIME_REF_OVERRIDE = selected;
  const paired = path.join(f.sdk, 'third_party/paired-runtime');
  ok(['git', '-C', paired, 'fetch', '--update-shallow', '-q', f.runtimeSource, selected]);
  ok(['git', '-C', paired, 'checkout', '-q', '--detach', 'FETCH_HEAD']);
  for (const [file, key] of [[path.join(f.runtime, 'manifest.json'), 'runtime_sha'],
    [path.join(f.sdk, 'build/build/shim-headers.json'), 'runtime']]) {
    const data = JSON.parse(fs.readFileSync(file));
    if (key === 'runtime') data.runtime.sha = selected; else data[key] = selected;
    fs.writeFileSync(file, JSON.stringify(data));
  }
  refreshRoot(f);
  if (formal) useFormalRuntime(f);
  // Build the tuple fixtures and pass their authenticated manifest through the
  // same preparation entry as production; no resolver results are injected.
  const llvmSha = f.env.LLVM_SHA;
  const backend = path.join(f.dir, 'backend');
  const backendC = `${backend}.c`;
  fs.writeFileSync(backendC, `const char stamp[]="CJLLVM-COMMIT:${llvmSha}"; int main(){return 0;}\n`);
  ok(['cc', backendC, '-o', backend]);
  const dylib = path.join(f.dylib, 'libLLVM-15.so');
  ok(['cc', '-shared', '-fPIC', backendC, '-o', dylib]);
  f.env.LLVM_DYLIB_SHA256 = hash(dylib);
  fs.writeFileSync(path.join(f.dylib, 'manifest.json'), JSON.stringify({
    llvm_sha: llvmSha, sha256: hash(dylib), targets: ['X86', 'ARM', 'AArch64']}));
  const fields = {PLATFORM: 'linux_x86_64', LLVM_SHA: llvmSha,
    CANGJIE_COMPILER_SHA: 'b'.repeat(40), FLATBUFFERS_SHA: 'c'.repeat(40), SHIM_SHA256: hash(backend)};
  for (const [prefix, tool] of [['LLC', 'llc'], ['OPT', 'opt'], ['LLD', 'ld.lld']]) {
    fields[`${prefix}_SOURCE`] = `tuple:${llvmSha}`;
    fields[`${prefix}_VERSION`] = 'identity fixture'; fields[`${prefix}_SHA256`] = hash(backend);
    const compressed = spawnSync('gzip', ['-c', backend]); assert.equal(compressed.status, 0);
    fs.writeFileSync(path.join(f.fallback, 'fixed-llc', `${tool}.gz`), compressed.stdout);
  }
  fields.LLD_TOOL = 'ld.lld';
  fs.writeFileSync(path.join(f.fallback, 'fixed-llc', 'llvm-tools.manifest'), Object.entries(fields).map(([k,v]) => `${k}=${v}`).join('\n')+'\n');
  fs.writeFileSync(path.join(f.fallback, 'SHA256SUMS'), 'stage3 authenticated tuple fixture\n');
  f.env.LLVM_TUPLE_SUMS_SHA = hash(path.join(f.fallback, 'SHA256SUMS'));
  const tuplePin = JSON.parse(fs.readFileSync(f.pinFile));
  for (const file of tuplePin.files) file.artifact_sha256 = file.release_sha256 = hash(path.join(f.fallback, file.path));
  fs.writeFileSync(f.pinFile, JSON.stringify(tuplePin));
  const a = assembled(f);
  const workspace = path.join(f.dir, 'stage3-workspace');
  const sdk = path.join(workspace, 'software/cangjie');
  fs.mkdirSync(path.dirname(sdk), {recursive: true});
  // First promotion has no consumer SDK. Populate the real handoff producers.
  const work = path.join(workspace, 'bootstrap-work');
  fs.mkdirSync(work, {recursive: true});
  const input = path.join(work, 'sdk-stage1');
  fs.cpSync(a.target, input, {recursive: true, dereference: true});
  const write = (rel, text) => {
    const file = path.join(work, rel); fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, text);
  };
  for (const [root, rel, source] of [
    [input, 'tools/bin/cjpm', '/bin/true'], [a.base, 'tools/bin/cjpm', '/bin/true'],
    [a.base, 'third_party/llvm/lib/libLLVM-15.so', path.join(a.libs, 'host.so')],
    [input, 'third_party/llvm/bin/opt', backend], [input, 'third_party/llvm/bin/llc', backend],
    [input, 'third_party/llvm/bin/ld.lld', backend], [input, 'third_party/llvm/lib/libLLVM-15.so', dylib],
  ]) {
    const dest = path.join(root, rel); fs.mkdirSync(path.dirname(dest), {recursive: true});
    fs.copyFileSync(source, dest); fs.chmodSync(dest, 0o755);
  }
  const runSdk = path.join(f.dir, 'run-sdk');
  fs.mkdirSync(path.join(runSdk, 'third_party/llvm/lib'), {recursive: true});
  fs.copyFileSync(dylib, path.join(runSdk, 'third_party/llvm/lib/libLLVM-15.so'));
  const identities = path.join(f.dir, 'runner-identities.txt');
  fs.writeFileSync(identities, ['libcangjie-runtime.so', 'libboundscheck.so', 'libLLVM-15.so']
    .map(name => `linux_x86_64 ${name} ${hash(path.join(a.libs, 'host.so'))}`).join('\n')+'\n');
  const runner = execute(['bash', path.join(repo, 'ci/bootstrap/stage1_host_runner.sh'), input, a.base, a.base,
    hash(path.join(a.libs, 'host.so')), a.compiler, hash(a.compiler), runSdk, hash(dylib)],
    {...f.env, STAGE1_HOST_IDENTITIES: identities});
  assert.equal(runner.status, 0, runner.output);
  assert.match(runner.output, /STAGE1-RUNNER-OK/);
  console.log(`STAGE3_NATIVE_RUNNER_INPUT_ASSERT product=${hash(path.join(repo, 'ci/bootstrap/stage1_host_runner.sh'))}`);
  for (const name of ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o'])
    write(`cjcj-src-stage1/runtime_shim/${name}`, 'handoff object fixture');
  write('cjcj-stage2', '#!/bin/sh\necho STAGE2_EXECUTION_BOUNDARY >&2\nif [ "$FIXTURE_CONTINUE" != 1 ]; then exit 73; fi\nif [ -n "$FIXTURE_MUTATION" ]; then printf changed >> "$FIXTURE_MUTATION"; fi\nexit 0\n');
  fs.mkdirSync(path.join(work, 'stdlib-stage2/lib', tuple), {recursive: true});
  fs.copyFileSync(path.join(input, 'lib', tuple, 'libcangjie-std-core.a'),
    path.join(work, 'stdlib-stage2/lib', tuple, 'libcangjie-std-core.a'));
  fs.cpSync(f.runtimeSource, path.join(workspace, 'cangjie_runtime'), {recursive: true});
  const env = {...Object.fromEntries(Object.entries(f.env).filter(([key]) => !key.startsWith('COLOUR_RT_'))), ...a.inputs, CANGJIE_WORKSPACE: workspace, GITHUB_WORKSPACE: path.join(workspace, 'source'),
    CJCJ_BOOTSTRAP_WORK: path.join(workspace, 'bootstrap-work'), CJCJ_STAGE3_STDLIB_BUILD_TYPE: 'release',
    CJCJ_BOOTSTRAP_HOST_RT: a.base, CJCJ_STAGE3_DRY_RUN: '1', CJCJ_STAGE3_DRY_RUN_FINAL_STD: path.join(workspace, 'unused-std')};
  fs.mkdirSync(env.GITHUB_WORKSPACE, {recursive: true});
  fs.cpSync(path.join(repo, 'ci'), path.join(env.GITHUB_WORKSPACE, 'ci'), {recursive: true});
  const command = ['npx', '--yes', 'zx@8', path.join(repo, 'ci/srcbuild/steps/build-stage3.mjs')];
  const valid = execute(command, env);
  assert.match(valid.output, new RegExp(`BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED runtime=${selected}`), valid.output);
  assert.match(valid.output, /STAGE2_EXECUTION_BOUNDARY/, valid.output);
  assert.notEqual(valid.status, 0);
  console.log(`STAGE3_PROMOTION_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'} first-promotion=1`);
  for (const [name, rel, expected] of [
    ['runtime', `runtime/lib/${tuple}/libcangjie-runtime.so`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH:.*libcangjie-runtime.so/],
    ['bounds', `runtime/lib/${tuple}/libboundscheck.so`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH:.*libboundscheck.so/],
    ['archive', `lib/${tuple}/libcangjie-runtime.a`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH:.*libcangjie-runtime.a/],
    ['lock', 'SDK.lock.json', /BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: assembly lock/],
  ]) {
    // The stage1 SDK remains valid: mismatch arrives only through the real
    // std overlay after any producer-side verification.
    const bytes = fs.readFileSync(path.join(input, rel));
    const file = path.join(work, 'stdlib-stage2', rel);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, bytes);
    if (name === 'lock') {
      const lock = JSON.parse(bytes); lock.components.runtime.commit = 'e'.repeat(40);
      fs.writeFileSync(file, JSON.stringify(lock));
    } else fs.appendFileSync(file, 'changed');
    const wrong = execute(command, env);
    assert.notEqual(wrong.status, 0); assert.match(wrong.output, expected, wrong.output);
    assert.doesNotMatch(wrong.output, /STAGE2_EXECUTION_BOUNDARY|BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED/);
    console.log(`STAGE3_REPLACEMENT_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'} wrong=${name} rejected-before-stage2=1`);
    fs.rmSync(file);
  }
  const wrongName = execute(command, {...env, CJCJ_BOOTSTRAP_COLOUR_LLVM_SO: path.join(path.dirname(dylib), 'wrong-library.so')});
  assert.notEqual(wrongName.status, 0); assert.match(wrongName.output, /BOOTSTRAP_BACKEND_LIBRARY_NAME_MISMATCH/, wrongName.output);
  assert.doesNotMatch(wrongName.output, /STAGE2_EXECUTION_BOUNDARY/);
  console.log(`STAGE3_LIBRARY_NAME_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'}`);
  for (const rel of ['bin/opt-stage1', 'bin/llc-stage1', 'bin/ld.lld', 'lib/libLLVM-15.so']) {
    const file = path.join(input, 'third_party/llvm', rel), bytes = fs.readFileSync(file);
    fs.appendFileSync(file, 'changed');
    const wrong = execute(command, env);
    assert.notEqual(wrong.status, 0); assert.match(wrong.output, /BOOTSTRAP_BACKEND_HASH_MISMATCH/, wrong.output);
    assert.doesNotMatch(wrong.output, /STAGE2_EXECUTION_BOUNDARY/);
    fs.writeFileSync(file, bytes);
    console.log(`STAGE3_BACKEND_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'} wrong=${rel}`);
  }
  // A matching hash must not substitute for a matching source chapter.
  const tupleRoot = a.inputs.CJCJ_BOOTSTRAP_COLOUR_TUPLE;
  const manifestFile = path.join(tupleRoot, 'fixed-llc/llvm-tools.manifest');
  const pinBytes = fs.readFileSync(f.pinFile), manifestBytes = fs.readFileSync(manifestFile);
  const backendFile = path.join(input, 'third_party/llvm/bin/opt-stage1'), backendBytes = fs.readFileSync(backendFile);
  const wrongBackend = Buffer.from(backendBytes.toString('latin1').replaceAll(`CJLLVM-COMMIT:${llvmSha}`, `CJLLVM-COMMIT:${'e'.repeat(40)}`), 'latin1');
  fs.writeFileSync(backendFile, wrongBackend);
  fs.writeFileSync(manifestFile, manifestBytes.toString().replace(`OPT_SHA256=${fields.OPT_SHA256}`, `OPT_SHA256=${hash(backendFile)}`));
  const mutatedPin = JSON.parse(pinBytes);
  for (const file of mutatedPin.files) file.artifact_sha256 = file.release_sha256 = hash(path.join(tupleRoot, file.path));
  fs.writeFileSync(f.pinFile, JSON.stringify(mutatedPin));
  const backendChapter = execute(command, env);
  assert.notEqual(backendChapter.status, 0); assert.match(backendChapter.output, /BOOTSTRAP_BACKEND_STAMP_MISMATCH/, backendChapter.output);
  assert.doesNotMatch(backendChapter.output, /STAGE2_EXECUTION_BOUNDARY/);
  fs.writeFileSync(backendFile, backendBytes); fs.writeFileSync(manifestFile, manifestBytes); fs.writeFileSync(f.pinFile, pinBytes);
  console.log(`STAGE3_BACKEND_CHAPTER_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'}`);
  const libraryManifest = path.join(path.dirname(dylib), 'manifest.json');
  const libraryBytes = fs.readFileSync(dylib), libraryManifestBytes = fs.readFileSync(libraryManifest);
  const wrongLibrary = Buffer.from(libraryBytes.toString('latin1').replaceAll(`CJLLVM-COMMIT:${llvmSha}`, `CJLLVM-COMMIT:${'e'.repeat(40)}`), 'latin1');
  fs.writeFileSync(dylib, wrongLibrary);
  fs.writeFileSync(path.join(input, 'third_party/llvm/lib/libLLVM-15.so'), wrongLibrary);
  const changedLibraryManifest = JSON.parse(libraryManifestBytes); changedLibraryManifest.sha256 = hash(dylib);
  fs.writeFileSync(libraryManifest, JSON.stringify(changedLibraryManifest));
  const libraryChapter = execute(command, {...env, CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256: hash(dylib)});
  assert.notEqual(libraryChapter.status, 0); assert.match(libraryChapter.output, /BOOTSTRAP_BACKEND_STAMP_MISMATCH/, libraryChapter.output);
  assert.doesNotMatch(libraryChapter.output, /STAGE2_EXECUTION_BOUNDARY/);
  fs.writeFileSync(dylib, libraryBytes); fs.writeFileSync(path.join(input, 'third_party/llvm/lib/libLLVM-15.so'), libraryBytes);
  fs.writeFileSync(libraryManifest, libraryManifestBytes);
  console.log(`STAGE3_LIBRARY_CHAPTER_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'}`);
  const final = env.CJCJ_STAGE3_DRY_RUN_FINAL_STD;
  for (const [rel, text] of [
    [`modules/${tuple}/std.cjo`, 'final module'], [`modules/${tuple}/libstd.bc`, 'final bitcode'],
    [`lib/${tuple}/libcangjie-std-core.a`, 'new final std core'],
    [`lib/${tuple}/libcangjie-std-coreFFI.a`, 'final ffi'],
    [`runtime/lib/${tuple}/libcangjie-std-core.so`, 'final shared std'], ['PROVENANCE.txt', 'dry-run fixture'],
  ]) { const file = path.join(final, rel); fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text); }
  fs.mkdirSync(path.join(final, 'modules', tuple, 'std'));
  const continued = {...env, FIXTURE_CONTINUE: '1'};
  const finalControl = execute(command, continued);
  assert.equal(finalControl.status, 0, finalControl.output);
  assert.match(finalControl.output, /STAGE3_DRY_RUN_REACHED_BUILD=1/);
  console.log(`STAGE3_FINAL_OVERLAY_CONTROL_ASSERT identity=${formal ? 'formal' : 'candidate'}`);
  for (const [name, rel, expected] of [
    ['runtime', `runtime/lib/${tuple}/libcangjie-runtime.so`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH/],
    ['bounds', `runtime/lib/${tuple}/libboundscheck.so`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH/],
    ['archive', `lib/${tuple}/libcangjie-runtime.a`, /BOOTSTRAP_SDK_RUNTIME_MISMATCH/],
    ['lock', 'SDK.lock.json', /BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH/],
    ['backend', 'third_party/llvm/bin/opt-stage1', /BOOTSTRAP_BACKEND_HASH_MISMATCH/],
    ['library', 'third_party/llvm/lib/libLLVM-15.so', /BOOTSTRAP_BACKEND_HASH_MISMATCH/],
    ['loader', `lib/${tuple}/libLLVM-15.so`, /BOOTSTRAP_BACKEND_LOADER_MISMATCH/],
    ['backend-runner', 'third_party/llvm/bin/opt', /BOOTSTRAP_BACKEND_RUNNER_MISMATCH/],
    ['stage2', 'bin/cjcj-stage2', /bootstrap compiler identity mismatch/],
    ['entry', 'bin/cjc', /bootstrap compiler identity mismatch/],
    ['record', 'bootstrap-compiler.json', /bootstrap compiler independent producer mismatch/],
  ]) {
    const file = path.join(final, rel); fs.mkdirSync(path.dirname(file), {recursive: true});
    if (name === 'record') fs.writeFileSync(file, JSON.stringify({producer: path.join(work, 'cjcj-stage2'), compilerSha256: 'e'.repeat(64)}));
    else if (name === 'lock') { const lock = JSON.parse(fs.readFileSync(path.join(input, rel))); lock.components.runtime.commit = 'e'.repeat(40); fs.writeFileSync(file, JSON.stringify(lock)); }
    else if (name === 'loader') fs.copyFileSync(dylib, file);
    else fs.writeFileSync(file, 'invalid protected consumer input');
    const wrong = execute(command, continued);
    assert.notEqual(wrong.status, 0); assert.match(wrong.output, expected, wrong.output);
    assert.match(wrong.output, /STAGE2_EXECUTION_BOUNDARY/);
    assert.doesNotMatch(wrong.output, /STAGE3_DRY_RUN_REACHED_BUILD=1/);
    fs.rmSync(file);
    console.log(`STAGE3_FINAL_OVERLAY_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'} wrong=${name}`);
  }
  const producerFile = path.join(work, 'cjcj-stage2'), producerBytes = fs.readFileSync(producerFile);
  // Make the post-overlay producer, installed entity and self-record agree.
  // Only the independent pre-handoff expectation can reject this substitution.
  const changedProducer = Buffer.concat([producerBytes, Buffer.from('changed')]);
  const compilerOverlay = path.join(final, 'bin/cjcj-stage2');
  fs.mkdirSync(path.dirname(compilerOverlay), {recursive: true}); fs.writeFileSync(compilerOverlay, changedProducer);
  const recordOverlay = path.join(final, 'bootstrap-compiler.json');
  fs.writeFileSync(recordOverlay, JSON.stringify({producer: producerFile,
    compilerSha256: crypto.createHash('sha256').update(changedProducer).digest('hex'),
    entrySha256: hash(path.join(sdk, 'bin/cjc'))}));
  const producerWrong = execute(command, {...continued, FIXTURE_MUTATION: producerFile});
  assert.notEqual(producerWrong.status, 0);
  assert.match(producerWrong.output, /bootstrap compiler independent producer mismatch/, producerWrong.output);
  assert.doesNotMatch(producerWrong.output, /STAGE3_DRY_RUN_REACHED_BUILD=1/);
  fs.writeFileSync(producerFile, producerBytes);
  fs.rmSync(compilerOverlay); fs.rmSync(recordOverlay);
  console.log(`STAGE3_PRODUCER_TARGET_ASSERT identity=${formal ? 'formal' : 'candidate'}`);
  // Restore the shared pair and alter only the source HEAD.

  ok(['git', '-C', path.join(workspace, 'cangjie_runtime'), '-c', 'user.name=Zxilly',
    '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-q', '-m', 'wrong source']);
  const source = execute(command, env);
  assert.notEqual(source.status, 0); assert.match(source.output, /BOOTSTRAP_RUNTIME_SOURCE_MISMATCH/);
  console.log('STAGE3_SOURCE_TARGET_ASSERT_EXECUTED');
}));

}

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


test('actual same-run restore feeds verified root receipt to the real SDK consumer without parent fields', () => fixture(f => {
  const root = path.join(f.dir, 'handoff-workspace');
  for (const rel of ['.srcbuild/inputs', 'packages', 'runtime_shim']) fs.mkdirSync(path.join(root, rel), {recursive: true});
  fs.writeFileSync(path.join(root, 'cjpm.toml'), 'identity transport fixture');
  const archivedRoot = path.join(root, '.srcbuild/inputs/runtime');
  fs.cpSync(f.runtime, archivedRoot, {recursive: true});
  f.runtime = archivedRoot; f.env.CJCJ_BOOTSTRAP_COLOUR_RT = archivedRoot;
  f.env.CJCJ_BOOTSTRAP_INPUTS_WORK = path.join(root, '.srcbuild/inputs/bootstrap');
  const a = assembled(f);
  const sdk = path.join(root, '.srcbuild/sdk-target');
  fs.cpSync(a.target, sdk, {recursive: true, verbatimSymlinks: true});
  const archive = path.join(f.dir, 'handoff-artifact');
  const file = path.join(f.dir, 'restored-env');
  const env = {...f.env, ...a.inputs, GITHUB_WORKSPACE: root, GITHUB_SHA: '1'.repeat(40),
    GITHUB_RUN_ID: '123', CJCJ_SRCBUILD_TARGET: 'linux-x64', GITHUB_ENV: file,
    GITHUB_PATH: path.join(f.dir, 'restored-path')};
  const entry = path.join(repo, 'ci/srcbuild/job-handoff.mjs');
  ok([process.execPath, entry, 'pack', 'stage1-compiler', archive], env);
  fs.rmSync(root, {recursive: true}); fs.mkdirSync(root);
  const clean = Object.fromEntries(Object.entries(env).filter(([key]) =>
    !key.startsWith('COLOUR_RT_') && !key.startsWith('CJCJ_BOOTSTRAP_') && !key.startsWith('RUNTIME_')
      && !['CJCJ_RUNTIME_REF_OVERRIDE', 'CJCJ_ALLOW_RUNTIME_OVERRIDE'].includes(key)));
  ok([process.execPath, entry, 'restore', 'stage1-compiler', archive], clean);
  const restored = Object.fromEntries(fs.readFileSync(file, 'utf8').trim().split('\n')
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
  const result = sdkConsumer({env: {}}, {target: sdk, inputs: restored});
  console.log(`HANDOFF_SDK_RECEIPT_TARGET_ASSERT rc=${result.status} manifest=${restored.COLOUR_RT_MANIFEST_SHA256} ${result.output}`);
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, new RegExp(`BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED runtime=${a.inputs.RUNTIME_REF}`));
  assert.equal(restored.COLOUR_RT_MANIFEST_SHA256, a.inputs.COLOUR_RT_MANIFEST_SHA256);
  console.log('HANDOFF_SDK_RECEIPT_TARGET_ASSERT_EXECUTED parent-fields=absent');
}));
