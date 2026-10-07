import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';

const entry = path.join(import.meta.dirname, 'fetch-llvm-runtime.mjs');
const env = {...process.env};
for (const key of ['CJCJ_LLVM_RUNTIME_MODE', 'CJCJ_LLVM_RUNTIME_URL', 'CJCJ_LLVM_RUNTIME_SHA']) delete env[key];
const invoke = args => spawnSync('npx', ['--yes', 'zx@8', entry, ...args], {env, encoding: 'utf8'});
const destination = path.join(import.meta.dirname, 'unused-fetch-destination');
for (const first of ['--check-input', '--verify-checkout']) {
  for (const second of ['--check-input', '--verify-checkout']) {
    test(`fetch rejects combined modes ${first} ${second}`, () => {
      const result = invoke([first, second, destination]);
      assert.equal(result.status, 1, 'combined modes must reject surplus arguments');
      assert.equal(result.stderr, 'LLVM_RUNTIME_INPUT_ERROR: expected one paired runtime destination\n');
      assert.equal(result.stdout, '');
    });
  }
  test(`fetch accepts single mode ${first}`, () => {
    const result = invoke([first, destination]);
    assert.equal(result.status, 0);
    assert.equal(result.stderr, '');
    assert.equal(result.stdout, '');
  });
  test(`fetch rejects missing destination for ${first}`, () => {
    const result = invoke([first]);
    assert.equal(result.status, 1);
    assert.equal(result.stderr, 'LLVM_RUNTIME_INPUT_ERROR: expected one paired runtime destination\n');
  });
}
