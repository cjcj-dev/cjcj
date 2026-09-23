import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';

test('separate dylib artifact exports the reviewed identity and preserves host LLVM', () => fixture(({dylib, dylibSha, so, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_LLVM_SO=${dylib}/libLLVM-15.so\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256=${dylibSha}\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_LLVM_SO=${so}\n`));
  console.log('ASSERT separate-dylib identity executed');
}));

test('wrong dylib fails at its digest assertion without falling back', () => fixture(({env, dylib, run}) => {
  env.CJCJ_BOOTSTRAP_COLOUR_DYLIB = dylib;
  const wrong = path.join(path.dirname(dylib), 'wrong');
  fs.mkdirSync(wrong);
  const wrongBytes = process.env.DYLIB_TEST_WRONG_FILE
    ? fs.readFileSync(process.env.DYLIB_TEST_WRONG_FILE) : Buffer.from('wrong library');
  fs.writeFileSync(path.join(wrong, 'libLLVM-15.so'), wrongBytes);
  fs.copyFileSync(path.join(dylib, 'manifest.json'), path.join(wrong, 'manifest.json'));
  env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT = wrong;
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /LLVM_DYLIB_SHA256_MISMATCH expected=[a-f0-9]{64} actual=[a-f0-9]{64}/);
  assert.doesNotMatch(result.stdout, /CJCJ_BOOTSTRAP_COLOUR_LLVM_SO=/);
  console.log('ASSERT wrong-dylib digest executed');
}));

test('missing explicit dylib does not select an available fallback', () => fixture(({env, dylib, run}) => {
  env.CJCJ_BOOTSTRAP_COLOUR_DYLIB = dylib;
  env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT = path.join(dylib, 'missing');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /LLVM_DYLIB_MISSING:/);
}));

test('dylib manifest must match source pin and target set', () => fixture(({dylib, run}) => {
  const file = path.join(dylib, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(file));
  manifest.llvm_sha = 'd'.repeat(40);
  fs.writeFileSync(file, JSON.stringify(manifest));
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /LLVM_DYLIB_MANIFEST_MISMATCH:/);
}));

test('dylib depot fallback uses the same reviewed digest', () => fixture(({env, dylib, run}) => {
  delete env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT;
  delete env.CJCJ_BOOTSTRAP_COLOUR_DYLIB;
  env.CJCJ_LLVM_DEPOT_ROOT = path.join(path.dirname(dylib), 'depot');
  env.CANGJIE_COMPILER_SHA = 'c'.repeat(40);
  const nested = path.join(env.CJCJ_LLVM_DEPOT_ROOT, env.LLVM_SHA, env.CANGJIE_COMPILER_SHA, 'dylib');
  fs.mkdirSync(nested, {recursive: true});
  fs.cpSync(dylib, nested, {recursive: true});
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_LLVM_SO=${nested}/libLLVM-15.so\n`));
}));
