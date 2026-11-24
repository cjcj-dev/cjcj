import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {loadPins, parseEnv, validatePins} from '../pins.mjs';
import {ASSETS, assetFileName, findAsset, validateReleaseSet} from '../targets.mjs';
import {plan} from '../cli.mjs';

const pins = loadPins();
const sha = 'a'.repeat(64);

test('pins: every repository is a full commit and the merged stdx/tools defaults are adopted', () => {
  assert.equal(pins.repos.stdx.commit, 'a124230201e938fb7a6aaecd56d1bd1c3e5243cc');
  assert.equal(pins.repos.tools.commit, '4d14d051c58a5574d6525314b2c695e2e5dd26e6');
  for (const repo of Object.values(pins.repos)) assert.match(repo.commit, /^[0-9a-f]{40}$/);
  assert.match(pins.wasi.sha256, /^[0-9a-f]{64}$/);
});

test('pins: illegal configuration is rejected with the precise code', () => {
  const source = parseEnv(fs.readFileSync(new URL('../source_pin.env', import.meta.url), 'utf8'));
  const wasi = parseEnv(fs.readFileSync(new URL('../wasi_pin.env', import.meta.url), 'utf8'));
  assert.equal(validatePins(source, wasi), true);
  assert.throws(() => validatePins({...source, STDX_REF: '76c9da37'}, wasi), /^Error: PIN_REF STDX_REF/);
  assert.throws(() => validatePins({...source, EXTRA_REF: 'x'}, wasi), /^Error: PIN_UNKNOWN EXTRA_REF/);
  assert.throws(() => validatePins(source, {...wasi, WASI_SYSROOT_SHA256: 'abc'}), /^Error: PIN_WASI_SHA256/);
  assert.throws(() => parseEnv('A=1\nA=2'), /^Error: PIN_DUPLICATE/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pins-'));
  fs.writeFileSync(path.join(dir, 's.env'), 'lowercase=1\n');
  assert.throws(() => loadPins({sourceFile: path.join(dir, 's.env')}), /^Error: PIN_SYNTAX/);
});

test('targets: exactly the 15 formal assets with their carriers', () => {
  assert.equal(ASSETS.length, 15);
  assert.deepEqual(ASSETS.map(a => a.key), ['linux-x64', 'linux-arm64', 'win32-x64', 'darwin-arm64', 'darwin-x64',
    'linux-x64-android', 'darwin-arm64-android', 'win32-x64-android', 'linux-x64-wasm', 'darwin-arm64-wasm', 'win32-x64-wasm',
    'linux-x64-ohos', 'darwin-arm64-ohos', 'win32-x64-ohos', 'darwin-arm64-ios']);
  assert.equal(ASSETS.filter(a => a.crossTuples.length === 0).length, 3);
  assert.deepEqual(findAsset('darwin-arm64-ios').crossTuples, ['ios_aarch64_cjnative', 'ios_simulator_aarch64_cjnative', 'ios_simulator_x86_64_cjnative']);
  assert.equal(assetFileName('win32-x64-wasm', '1.0.0'), 'cangjie-sdk-win32-x64-wasm-1.0.0.zip');
  assert.throws(() => findAsset('linux-riscv64'), /^Error: UNKNOWN_ASSET linux-riscv64/);
  assert.equal(plan().assets.length, 15);
});

test('release set: the 15 legal assets pass; a wrong asset, bad sha or missing asset is refused', () => {
  const v = pins.version, good = ASSETS.map(a => ({file: assetFileName(a.key, v), sha256: sha}));
  assert.equal(validateReleaseSet(good, v), true);
  assert.throws(() => validateReleaseSet([...good.slice(1), {file: `cangjie-sdk-linux-x64-${v}.zip`, sha256: sha}], v), /^Error: RELEASE_UNEXPECTED_ASSET/);
  assert.throws(() => validateReleaseSet(good.map((e, i) => i === 3 ? {...e, sha256: 'z'.repeat(64)} : e), v), /^Error: RELEASE_BAD_SHA/);
  assert.throws(() => validateReleaseSet(good.slice(0, 14), v), /^Error: RELEASE_MISSING_ASSET cangjie-sdk-darwin-arm64-ios/);
  assert.throws(() => validateReleaseSet([...good, good[0]], v), /^Error: RELEASE_DUPLICATE_ASSET/);
});
