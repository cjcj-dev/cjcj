import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';
import {digest, runtimeFiles} from './colour_runtime.mjs';

test('runtime pair reaches bootstrap with explicit identity and host remains separate', () => fixture(({env, runtime, runtimeSource, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /COLOUR_RT_VERIFIED run=123 artifact=456/);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_RT=${runtime}\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_RT=${env.CJCJ_SRCBUILD_HOST_SDK}\n`));
  for (const rel of runtimeFiles) {
    assert.equal(digest(path.join(runtime, rel)), digest(path.join(runtimeSource, rel)));
    assert.equal(fs.lstatSync(path.join(runtime, rel)).isFile(), true);
  }
  console.log('ASSERT runtime producer bytes and consumer identity executed');
}));

test('runtime pin tampering fails only runtime identity assertion', () => fixture(({env, run}) => {
  env.COLOUR_RT_MANIFEST_SHA256 = '0'.repeat(64);
  const result = run();
  assert.match(result.stderr, /COLOUR_RT_SHA256_MISMATCH expected=0{64} actual=[a-f0-9]{64}/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stderr, /LLVM_DYLIB_|ast-support|SHA256SUMS disagrees/);
  assert.doesNotMatch(result.stdout, /CJCJ_BOOTSTRAP_COLOUR_RT=/);
  console.log('ASSERT runtime digest rejection executed');
}));

test('missing colour runtime cannot fall back to the available host SDK', () => fixture(({env, run}) => {
  delete env.CJCJ_BOOTSTRAP_COLOUR_RT;
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /COLOUR_RT_INPUT_MISSING/);
}));

for (const field of ['COLOUR_RT_RUN_ID', 'COLOUR_RT_RUN_ATTEMPT', 'RUNTIME_REF']) {
  test(`runtime manifest binds ${field}`, () => fixture(({env, run}) => {
    env[field] = field === 'RUNTIME_REF' ? 'e'.repeat(40) : '999';
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_MANIFEST_MISMATCH/);
  }));
}
for (const rel of runtimeFiles) {
  test(`runtime payload digest binds ${rel}`, () => fixture(({runtime, run}) => {
    fs.appendFileSync(path.join(runtime, rel), 'changed');
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_FILE_SHA256_MISMATCH/);
  }));
}

for (const rel of ['lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'modules/linux_x86_64_cjnative/std.core.cjo']) {
  test(`new std producer and consumer bind ${rel}`, () => fixture(({runtime, runtimeSource, run}) => {
    assert.equal(fs.readFileSync(path.join(runtime, rel), 'utf8'), fs.readFileSync(path.join(runtimeSource, rel), 'utf8'));
    assert.equal(run().status, 0);
    fs.appendFileSync(path.join(runtime, rel), 'changed std');
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_FILE_SHA256_MISMATCH/);
    console.log(`ASSERT new std bytes copied and checked ${rel}`);
  }));
}
