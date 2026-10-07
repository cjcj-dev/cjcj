import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';

const entry = path.join(import.meta.dirname, 'check-llvm-runtime-abi.mjs');
const invoke = args => spawnSync('npx', ['--yes', 'zx@8', entry, ...args], {encoding: 'utf8'});

for (const name of ['llvm_repo', 'llvm_ref', 'runtime_repo', 'runtime_ref']) {
  test(`ABI rejects underscore option --${name} before help`, () => {
    const result = invoke([`--${name}`, 'x', '--help']);
    assert.equal(result.status, 2, 'unknown option must exit 2 before help');
    assert.match(result.stderr, new RegExp(`ABI_PAIR=INVALID_ARGUMENT argument=--${name}\\n`));
    assert.equal(result.stdout, '');
  });
  const option = `--${name.replaceAll('_', '-')}`;
  test(`ABI accepts exact option ${option} before help`, () => {
    const result = invoke([option, 'x', '--help']);
    assert.equal(result.status, 0);
    assert.match(result.stdout, /^usage: check-llvm-runtime-abi\.mjs/);
    assert.equal(result.stderr, '');
  });
  test(`ABI rejects missing value for ${option}`, () => {
    const result = invoke([option]);
    assert.equal(result.status, 2);
    assert.equal(result.stderr, `ABI_PAIR=INVALID_ARGUMENT missing_value=${option}\n`);
  });
}
