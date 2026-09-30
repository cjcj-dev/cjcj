import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fixture} from './prepare_bootstrap_fixture.mjs';

for (const [target, run, artifact] of [
  ['linux-x64', 36588242795, 11046465284],
  ['linux-aarch64', 36611013257, 11053888167],
]) {
  test(`tuple platform selection ${target}`, () => {
    const env = {...process.env, CJCJ_SRCBUILD_TARGET: target};
    delete env.CJCJ_BOOTSTRAP_INPUTS_PIN;
    const result = spawnSync(process.execPath, [new URL('./tuple_pin.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    const actual = /^LLVM_TUPLE_ARTIFACT_ID=(.+)$/m.exec(result.stdout)?.[1] || 'MISSING';
    console.log(`ASSERT tuple-selected target=${target} artifact=${actual} rc=${result.status}`);
    assert.equal(actual, String(artifact), result.stderr);
    assert.match(result.stdout, new RegExp(`^LLVM_TUPLE_RUN_ID=${run}$`, 'm'));
    assert.equal(result.status, 0, result.stderr);
  });

  test(`tuple prepare consumes platform bytes ${target}`, () => fixture(({env, fallback, run: prepare}) => {
    env.LLVM_TUPLE_SUMS_SHA = '0'.repeat(64);
    const result = prepare();
    const selected = /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=(.+)$/m.exec(result.stdout)?.[1];
    const bytes = selected ? fs.readFileSync(path.join(selected, 'SHA256SUMS'), 'utf8') : 'MISSING';
    console.log(`ASSERT tuple-bytes target=${target} bytes=${bytes} rc=${result.status}`);
    assert.equal(bytes, fs.readFileSync(path.join(fallback, 'SHA256SUMS'), 'utf8'), result.stderr);
    assert.equal(result.status, 0, result.stderr);
  }, target));
}

for (const [target, platform] of [['darwin-x64', 'darwin_x86_64'], ['darwin-arm64', 'darwin_aarch64']]) {
  test(`tuple missing platform fails precisely ${target}`, () => {
    const env = {...process.env, CJCJ_SRCBUILD_TARGET: target};
    delete env.CJCJ_BOOTSTRAP_INPUTS_PIN;
    const result = spawnSync(process.execPath, [new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    console.log(`ASSERT tuple-missing target=${target} rc=${result.status}`);
    assert.match(result.stderr, new RegExp(`LLVM_TUPLE_PIN_MISSING platform=${platform}`));
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stdout, /BOOTSTRAP_SOURCE|CJCJ_BOOTSTRAP_COLOUR_TUPLE=/);
  });
}

test('tuple explicit pin cannot cross platforms', () => fixture(({pinFile, run}) => {
  const pin = JSON.parse(fs.readFileSync(pinFile));
  pin.platform = 'linux_x86_64';
  fs.writeFileSync(pinFile, JSON.stringify(pin));
  const result = run();
  console.log(`ASSERT tuple-platform-rejection rc=${result.status}`);
  assert.match(result.stderr, /LLVM_TUPLE_PIN_PLATFORM_MISMATCH expected=linux_aarch64 actual=linux_x86_64/);
  assert.notEqual(result.status, 0);
}, 'linux-aarch64'));
