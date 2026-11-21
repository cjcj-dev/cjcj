import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {sdkExeSuffix, inputTool, toolchainIdentity} from './wasm-sdk-overlay.mjs';

const write = (file, body) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, body); };
function sdk(root, exe, hostByte) {
  write(path.join(root, 'libexec/compiler/cjcj-stage1' + exe), 'host' + hostByte);
  for (const t of ['opt', 'llc', 'wasm-ld']) write(path.join(root, '.native-tools/third_party/llvm/bin', t + exe), t + hostByte);
  write(path.join(root, 'runtime/lib/wasi_wasm32_cjnative/libcangjie-runtime.a'), 'rt');
  write(path.join(root, 'lib/wasi_wasm32_cjnative/libcangjie-std-core.a'), 'core');
  write(path.join(root, 'modules/wasi_wasm32_cjnative/std/core.cjo'), 'cjo');
  return root;
}

test('the toolchain id hashes only the target half, so Linux and Windows SDKs share it', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-host-'));
  const linux = sdk(path.join(tmp, 'linux'), '', 'L'), win = sdk(path.join(tmp, 'win'), '.exe', 'W');
  assert.equal(sdkExeSuffix(linux), '');
  assert.equal(sdkExeSuffix(win), '.exe');
  assert.match(toolchainIdentity(linux), /^cjw2-[0-9a-f]{32}$/);
  assert.equal(toolchainIdentity(linux), toolchainIdentity(win));
  write(path.join(win, 'modules/wasi_wasm32_cjnative/std/core.cjo'), 'changed');
  assert.notEqual(toolchainIdentity(linux), toolchainIdentity(win));
  write(path.join(win, 'libexec/compiler/cjcj-stage1'), 'both');
  assert.throws(() => sdkExeSuffix(win), /exactly one/);
});

test('input tools are found with or without the SDK suffix', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-tool-'));
  write(path.join(tmp, 'lld.exe'), ''); write(path.join(tmp, 'opt'), '');
  assert.equal(inputTool(tmp, 'lld', '.exe'), path.join(tmp, 'lld.exe'));
  assert.equal(inputTool(tmp, 'lld', ''), path.join(tmp, 'lld.exe'));
  assert.equal(inputTool(tmp, 'opt', '.exe'), path.join(tmp, 'opt'));
});

test('the installed runner prefers the SDK Node, then PATH, and honours CJ_WASM_NODE', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-runner-'));
  const runner = path.join(tmp, 'tools/wasm/run_wasi.mjs');
  write(runner, fs.readFileSync(new URL('./wasm-run-wasi.mjs', import.meta.url)));
  const fake = (file, tag) => { write(file, `#!/bin/sh\necho ${tag} >&2\nexit 7\n`); fs.chmodSync(file, 0o755); };
  fake(path.join(tmp, 'tools/bin/node'), 'sdk-node');
  fake(path.join(tmp, 'explicit'), 'explicit-node');
  const run = env => spawnSync(process.execPath, [runner, 'x.wasm'], {encoding: 'utf8', env: {PATH: process.env.PATH, ...env}});
  let r = run({});
  assert.equal(r.status, 7); assert.match(r.stderr, /sdk-node/);
  r = run({CJ_WASM_NODE: path.join(tmp, 'explicit')});
  assert.equal(r.status, 7); assert.match(r.stderr, /explicit-node/);
  fs.rmSync(path.join(tmp, 'tools/bin/node'));
  r = run({});  // PATH node re-executes with the flag and reaches the missing-module path
  assert.notEqual(r.status, 7); assert.doesNotMatch(r.stderr, /sdk-node|explicit-node/);
});
