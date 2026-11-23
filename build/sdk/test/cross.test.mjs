import test from 'node:test';
import assert from 'node:assert/strict';
import {API_TUPLE, stdCompileFlags, stdProducerArgs, wasmStdPlan} from '../std.mjs';
import {ASSETS, CROSS_TUPLES} from '../targets.mjs';

const OFF = ['--experimental', '--enable-local-mode', '--cfg', 'local_mode_api=off'];

test('cross: every native and cross std tuple carries the local-mode flags with the API off', () => {
  for (const asset of ASSETS) for (const tuple of asset.tuples) assert.deepEqual(asset.std[tuple], OFF, `${asset.key} ${tuple}`);
  assert.ok(Object.keys(CROSS_TUPLES).length >= 9);
});

test('cross: Linux x64 may opt in to local_mode_api=on, every other tuple is refused', () => {
  assert.deepEqual(stdCompileFlags(API_TUPLE, {localModeApi: true}).at(-1), 'local_mode_api=on');
  assert.deepEqual(stdProducerArgs(API_TUPLE, {localModeApi: true}), ['--local-mode-api']);
  assert.deepEqual(stdProducerArgs(API_TUPLE), []);
  for (const tuple of ['linux_ohos_aarch64_cjnative', 'wasi_wasm32_cjnative', 'windows_x86_64_cjnative', 'linux_aarch64_cjnative'])
    assert.throws(() => stdCompileFlags(tuple, {localModeApi: true}), new RegExp(`^Error: STD_LOCAL_MODE_API_TUPLE ${tuple}`));
  assert.throws(() => stdCompileFlags('wasm32'), /^Error: STD_TUPLE wasm32/);
});

test('cross: Wasm WASI P1 builds the full std including std.core with the same flags', () => {
  assert.deepEqual(wasmStdPlan(), {tuple: 'wasi_wasm32_cjnative', packages: 'full', includesCore: true, flags: OFF});
  for (const key of ['linux-x64-wasm', 'darwin-arm64-wasm', 'win32-x64-wasm'])
    assert.equal(ASSETS.find(a => a.key === key).verification.cross.wasi_wasm32_cjnative, 'wasi-runtime');
});
