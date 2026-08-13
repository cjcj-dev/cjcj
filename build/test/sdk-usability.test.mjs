import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  STATES,
  classifyToolVersion,
  countC9Instructions,
  identityCheck,
  layoutCheck,
  parseArguments,
  permissionsAndLinksCheck,
  summarizeResults,
} from '../../scripts/check_sdk_usable.mjs';

const root = path.resolve(import.meta.dirname, '..', '..');
const checker = path.join(root, 'scripts', 'check_sdk_usable.mjs');

const IDENTITY_ARTIFACTS = Object.freeze([
  ['runtime', 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', 'CJRT-COMMIT', '1'.repeat(40)],
  ['cjc', 'bin/cjc', 'CJCJ-COMMIT', '2'.repeat(40)],
  ['cjpm', 'tools/bin/cjpm', 'CJTOOL-COMMIT', '3'.repeat(40)],
  ['llc', 'third_party/llvm/bin/llc', 'CJLLVM-COMMIT', '4'.repeat(40)],
  ['opt', 'third_party/llvm/bin/opt', 'CJLLVM-COMMIT', '4'.repeat(40)],
]);

function digest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function identityFixture({legacy = false} = {}) {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-identity-'));
  const lines = legacy
    ? [`sdk_real\t${sdk}`, 'is_symlink\tno']
    : ['format\ttoolchain-lineage-v1', 'sdk_root\t.', 'is_symlink\tno', 'artifact_count\t5'];
  for (const [name, relative, prefix, commit] of IDENTITY_ARTIFACTS) {
    const file = path.join(sdk, relative);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, `${name}\0${prefix}:${commit}\0`);
    lines.push(`${name}_sha\t${digest(file)}`);
    if (!legacy) lines.push(
      `${name}_path\t${relative}`,
      `${name}_repository\thttps://example.invalid/${name}.git`,
      `${name}_commit\t${commit}`,
      `${name}_dirty\tno`,
      `${name}_lineage\t${prefix}:${commit}`,
    );
  }
  fs.writeFileSync(path.join(sdk, 'TOOLCHAIN_ID.tsv'), `${lines.join('\n')}\n`);
  return sdk;
}

function versionResult(status, output, overrides = {}) {
  return {
    status,
    output,
    stdout: output,
    stderr: '',
    signal: null,
    error: undefined,
    timedOut: false,
    ...overrides,
  };
}

test('argument parser refuses a GC sample smaller than the contract', () => {
  assert.throws(
    () => parseArguments(['--sdk', '/fixture', '--gc-runs', '9']),
    /--gc-runs must be an integer >= 10/,
  );
  assert.equal(parseArguments(['--sdk', '/fixture']).gcRuns, 10);
});

test('summary keeps FAIL and UNKNOWN separate while both fail closed', () => {
  const unknown = summarizeResults([
    {state: STATES.PASS},
    {state: STATES.UNKNOWN},
  ]);
  assert.deepEqual(unknown.counts, {pass: 1, fail: 0, unknown: 1});
  assert.equal(unknown.state, STATES.UNKNOWN);
  assert.equal(unknown.exitCode, 2);

  const failed = summarizeResults([
    {state: STATES.PASS},
    {state: STATES.FAIL},
    {state: STATES.UNKNOWN},
  ]);
  assert.deepEqual(failed.counts, {pass: 1, fail: 1, unknown: 1});
  assert.equal(failed.state, STATES.FAIL);
  assert.equal(failed.exitCode, 1);
});

test('generic lld unavailability is intentional but loader errors are not', () => {
  const intentional = classifyToolVersion(
    'third_party/llvm/bin/lld',
    versionResult(1, 'lld is a generic driver. Invoke ld.lld instead'),
  );
  assert.equal(intentional.state, STATES.PASS);
  assert.equal(intentional.intentional, true);

  const loaderFailure = classifyToolVersion(
    'third_party/llvm/bin/lld',
    versionResult(127, 'error while loading shared libraries: libLLVM.so: cannot open'),
  );
  assert.equal(loaderFailure.state, STATES.FAIL);
  assert.equal(loaderFailure.intentional, false);

  const inventedException = classifyToolVersion(
    'third_party/llvm/bin/future-tool',
    versionResult(1, 'lld is a generic driver.'),
  );
  assert.equal(inventedException.state, STATES.FAIL);
});

test('C9 counts only the comma-terminated mask inside String.[]', () => {
  const positive = [
    '0000000000000000 <unrelated>:',
    '   0: 48 b8 ff ff ff ff ff  movabs $0xffffffffffff,%rax',
    '',
    '0000000000000100 <_CNat6StringixHl>:',
    ' 100: 48 b8 ff ff ff ff ff  movabs $0xffffffffffff,%rax',
    '',
    '0000000000000200 <other>:',
    ' 200: 48 b8 ff ff ff ff ff  movabs $0xffffffffffff,%rax',
  ].join('\n');
  assert.deepEqual(countC9Instructions(positive), {anchored: true, count: 1});

  const missingComma = positive.replace('movabs $0xffffffffffff,%rax', 'movabs $0xffffffffffff')
    .replace('movabs $0xffffffffffff,%rax', 'movabs $0xffffffffffff')
    .replace('movabs $0xffffffffffff,%rax', 'movabs $0xffffffffffff');
  assert.deepEqual(countC9Instructions(missingComma), {anchored: true, count: 0});
  assert.deepEqual(countC9Instructions('0000 <other>:\n'), {anchored: false, count: 0});
});

test('layout requires Linux bitcode but accepts the official Windows zero-bitcode shape', () => {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-layout-'));
  const add = (relative, contents = '') => {
    const destination = path.join(sdk, relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, contents);
  };
  try {
    for (const [tuple, sharedSuffix] of [
      ['linux_x86_64_cjnative', 'so'],
      ['windows_x86_64_cjnative', 'dll'],
    ]) {
      add(`modules/${tuple}/std/std.core.cjo`);
      add(`lib/${tuple}/libcangjie-std-core.a`);
      add(`lib/${tuple}/libcangjie-std-coreFFI.a`);
      add(`runtime/lib/${tuple}/libcangjie-std-core.${sharedSuffix}`);
    }
    add('modules/linux_x86_64_cjnative/std/libstd.core.bc');
    assert.deepEqual(layoutCheck(sdk), {
      state: STATES.PASS,
      detail: 'tuples=2 cjo=2 bc=1 ffi_a=2',
    });

    fs.rmSync(path.join(sdk, 'modules', 'linux_x86_64_cjnative', 'std', 'libstd.core.bc'));
    const missingLinuxBitcode = layoutCheck(sdk);
    assert.equal(missingLinuxBitcode.state, STATES.FAIL);
    assert.match(missingLinuxBitcode.detail, /linux_x86_64_cjnative: std cjo=1 bc=0/);
  } finally {
    fs.rmSync(sdk, {recursive: true, force: true});
  }
});

test('U8 accepts official 750 and only rejects owner-unreadable entries', () => {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-u8-'));
  const add = (relative, mode) => {
    const destination = path.join(sdk, relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, 'fixture\n');
    fs.chmodSync(destination, mode);
  };
  try {
    add('LICENSE', 0o750);
    add('bin/cjc', 0o750);
    add('include/cangjie/AST/Node.h', 0o750);
    fs.chmodSync(path.join(sdk, 'include'), 0o750);
    fs.chmodSync(path.join(sdk, 'include', 'cangjie'), 0o750);
    fs.chmodSync(path.join(sdk, 'include', 'cangjie', 'AST'), 0o750);
    fs.symlinkSync('cjc', path.join(sdk, 'bin', 'cjc.alias'));
    const official = permissionsAndLinksCheck(sdk);
    assert.equal(official.state, STATES.PASS, official.detail);
    assert.match(official.detail, /bad_modes=0/);

    add('secret.bin', 0o000);
    const unreadable = permissionsAndLinksCheck(sdk);
    assert.equal(unreadable.state, STATES.FAIL);
    assert.match(unreadable.detail, /bad_modes=1/);
    assert.match(unreadable.detail, /secret.bin:0/);
  } finally {
    fs.rmSync(sdk, {recursive: true, force: true});
  }
});

test('U9 accepts exactly five clean relocatable lineage records', () => {
  const sdk = identityFixture();
  try {
    const details = [];
    const result = identityCheck(sdk, sdk, 5_000, details);
    assert.equal(result.state, STATES.PASS, result.detail);
    assert.match(result.detail, /hashes=5\/5 lineage=5\/5 failures=0 unknown=0/);
    assert.equal(details.length, 5);
    assert.ok(details.every(detail => /repository=https:\/\/example\.invalid\//.test(detail)));
    assert.ok(details.every(detail => /dirty=no/.test(detail)));
  } finally {
    fs.rmSync(sdk, {recursive: true, force: true});
  }
});

test('U9 fails a produced identity that marks any artifact dirty or loses its stamp', () => {
  const sdk = identityFixture();
  try {
    const identity = path.join(sdk, 'TOOLCHAIN_ID.tsv');
    fs.appendFileSync(identity, 'llc_dirty\tyes\n');
    let result = identityCheck(sdk, sdk, 5_000, []);
    assert.equal(result.state, STATES.FAIL);
    assert.match(result.detail, /duplicate keys=llc_dirty/);
    assert.match(result.detail, /llc: dirty=yes/);

    const cjpm = path.join(sdk, 'tools/bin/cjpm');
    fs.writeFileSync(cjpm, 'cjpm-without-stamp');
    let text = fs.readFileSync(identity, 'utf8').replace(/^cjpm_sha\t.*$/m, `cjpm_sha\t${digest(cjpm)}`);
    text = text.replace(/^llc_dirty\tno\nllc_dirty\tyes$/m, 'llc_dirty\tno');
    fs.writeFileSync(identity, text);
    result = identityCheck(sdk, sdk, 5_000, []);
    assert.equal(result.state, STATES.FAIL);
    assert.match(result.detail, /cjpm: no lineage stamp/);
  } finally {
    fs.rmSync(sdk, {recursive: true, force: true});
  }
});

test('U9 keeps the legacy hash-mismatch gate while distinguishing missing lineage as UNKNOWN', () => {
  const sdk = identityFixture({legacy: true});
  try {
    const identity = path.join(sdk, 'TOOLCHAIN_ID.tsv');
    let text = fs.readFileSync(identity, 'utf8').replace(/^cjc_sha\t.*$/m, `cjc_sha\t${'0'.repeat(64)}`);
    fs.writeFileSync(identity, text);
    let result = identityCheck(sdk, sdk, 5_000, []);
    assert.equal(result.state, STATES.FAIL);
    assert.match(result.detail, /cjc: sha mismatch/);

    const cjpm = path.join(sdk, 'tools/bin/cjpm');
    fs.writeFileSync(cjpm, 'legacy-cjpm-without-stamp');
    text = fs.readFileSync(identity, 'utf8')
      .replace(/^cjc_sha\t.*$/m, `cjc_sha\t${digest(path.join(sdk, 'bin/cjc'))}`)
      .replace(/^cjpm_sha\t.*$/m, `cjpm_sha\t${digest(cjpm)}`);
    fs.writeFileSync(identity, text);
    result = identityCheck(sdk, sdk, 5_000, []);
    assert.equal(result.state, STATES.UNKNOWN);
    assert.match(result.detail, /cjpm: no lineage stamp/);
  } finally {
    fs.rmSync(sdk, {recursive: true, force: true});
  }
});

test('an unreadable SDK emits every criterion as UNKNOWN and exits 2', () => {
  const result = spawnSync(process.execPath, [checker, '--sdk', '/does/not/exist/sdkusable'], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(result.status, 2, result.stderr);
  assert.match(result.stdout, /U1_DIRECT_CJC\tUNKNOWN\tSDK unreadable:/);
  assert.match(result.stdout, /C9_STD_UNCOLOUR\tUNKNOWN\tSDK unreadable:/);
  assert.match(result.stdout, /SDK-USABILITY-UNKNOWN pass=0 fail=0 unknown=10/);
});
