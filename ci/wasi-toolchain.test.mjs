import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  WASM_SDK_LAYOUT, checkWasmSdk, installWasiSysroot, parseWasiPin, readWasiPin,
} from './wasi-toolchain.mjs';

const tmp = prefix => fs.mkdtempSync(path.join(os.tmpdir(), prefix));

function fakeSysrootTarball(dir) {
  const src = path.join(dir, 'src');
  fs.mkdirSync(path.join(src, 'wasi-sysroot/lib/wasm32-wasi'), {recursive: true});
  for (const name of ['libc.a', 'crt1-command.o']) fs.writeFileSync(path.join(src, 'wasi-sysroot/lib/wasm32-wasi', name), name);
  const tarball = path.join(dir, 'wasi-sysroot.tar.gz');
  assert.equal(spawnSync('tar', ['-czf', tarball, '-C', src, 'wasi-sysroot']).status, 0);
  return {tarball, sha256: createHash('sha256').update(fs.readFileSync(tarball)).digest('hex')};
}

function pinFor(sha256) {
  return parseWasiPin([
    'WASI_SYSROOT_URL=https://example.invalid/wasi-sysroot-17.0.tar.gz', `WASI_SYSROOT_SHA256=${sha256}`,
    'WASI_SYSROOT_VERSION=17.0', 'WASI_SYSROOT_LLVM_MAJOR=15', 'WASI_NODE_MIN_MAJOR=20',
  ].join('\n'));
}

function fakeNode(dir, version) {
  const node = path.join(dir, 'node');
  fs.writeFileSync(node, `#!/bin/sh\necho ${version}\n`, {mode: 0o755});
  return node;
}

// A complete fake SDK: every layout path present, sysroot installed through installWasiSysroot.
function fakeSdk(dir, pin, tarball, nodeVersion = 'v22.23.3') {
  const sdk = path.join(dir, 'sdk');
  installWasiSysroot({sdk, tarball, pin});
  for (const item of WASM_SDK_LAYOUT) {
    const file = path.join(sdk, item.path);
    if (fs.existsSync(file)) continue;
    fs.mkdirSync(path.dirname(file), {recursive: true});
    if (item.id === 'node') fakeNode(path.dirname(file), nodeVersion);
    else fs.writeFileSync(file, item.id);
  }
  return sdk;
}

test('the checked-in wasi pin is well formed and pins wasi-sdk 17 (LLVM 15) over https', () => {
  const pin = readWasiPin();
  assert.match(pin.WASI_SYSROOT_URL, /^https:\/\/github\.com\/WebAssembly\/wasi-sdk\/releases\/download\/wasi-sdk-17\//);
  assert.match(pin.WASI_SYSROOT_SHA256, /^[0-9a-f]{64}$/);
  assert.equal(pin.WASI_SYSROOT_LLVM_MAJOR, '15');
});

test('pin parsing rejects unknown, duplicated, missing and non-https records', () => {
  const good = pinFor('0'.repeat(64));
  const lines = Object.entries(good).map(([k, v]) => `${k}=${v}`);
  assert.throws(() => parseWasiPin([...lines, 'WASI_EXTRA=1'].join('\n')), /unknown wasi pin key/);
  assert.throws(() => parseWasiPin([...lines, lines[0]].join('\n')), /duplicated/);
  assert.throws(() => parseWasiPin(lines.slice(1).join('\n')), /must define WASI_SYSROOT_URL/);
  assert.throws(() => parseWasiPin(lines.map(l => l.replace('https://', 'http://')).join('\n')), /https/);
  assert.throws(() => parseWasiPin(lines.map(l => l.replace(/=0+$/, '=XYZ')).join('\n')), /lowercase sha256/);
});

test('install verifies the pinned sha256 before touching the SDK', () => {
  const dir = tmp('wasi-install-');
  const {tarball, sha256} = fakeSysrootTarball(dir);
  const sdk = path.join(dir, 'sdk');
  assert.throws(() => installWasiSysroot({sdk, tarball, pin: pinFor('f'.repeat(64))}), /sha256 mismatch/);
  assert.equal(fs.existsSync(path.join(sdk, 'third_party/wasi-sysroot')), false);
  const result = installWasiSysroot({sdk, tarball, pin: pinFor(sha256)});
  assert.equal(result.sha256, sha256);
  assert.ok(fs.existsSync(path.join(sdk, 'third_party/wasi-sysroot/lib/wasm32-wasi/libc.a')));
  assert.match(fs.readFileSync(path.join(sdk, 'third_party/wasi-sysroot/WASI-SYSROOT-PIN'), 'utf8'), new RegExp(sha256));
  assert.throws(() => installWasiSysroot({sdk, tarball, pin: pinFor(sha256)}), /already exists/);
  assert.doesNotThrow(() => installWasiSysroot({sdk, tarball, pin: pinFor(sha256), replace: true}));
});

test('a complete SDK passes the wasm layout check', () => {
  const dir = tmp('wasi-check-');
  const {tarball, sha256} = fakeSysrootTarball(dir);
  const result = checkWasmSdk(fakeSdk(dir, pinFor(sha256), tarball), {pin: pinFor(sha256)});
  assert.deepEqual(result, {ok: true, missing: [], problems: [], node: {ok: true, version: 'v22.23.3', major: 22}});
});

test('each missing layout path is reported alone (precise red)', () => {
  for (const item of WASM_SDK_LAYOUT) {
    const dir = tmp('wasi-red-');
    const {tarball, sha256} = fakeSysrootTarball(dir);
    const sdk = fakeSdk(dir, pinFor(sha256), tarball);
    fs.rmSync(path.join(sdk, item.path));
    const result = checkWasmSdk(sdk, {pin: pinFor(sha256)});
    assert.equal(result.ok, false, item.id);
    assert.deepEqual(result.missing, [item.id]);
  }
});

test('an old node and a sysroot from another pin are problems, not silent passes', () => {
  const dir = tmp('wasi-node-');
  const {tarball, sha256} = fakeSysrootTarball(dir);
  const sdk = fakeSdk(dir, pinFor(sha256), tarball, 'v18.20.0');
  const old = checkWasmSdk(sdk, {pin: pinFor(sha256)});
  assert.deepEqual([old.ok, old.missing], [false, []]);
  assert.match(old.problems.join('\n'), /older than v20/);
  const other = checkWasmSdk(sdk, {pin: pinFor('a'.repeat(64)), node: fakeNode(dir, 'v22.1.0')});
  assert.match(other.problems.join('\n'), /does not match ci\/wasi_pin.env/);
});
