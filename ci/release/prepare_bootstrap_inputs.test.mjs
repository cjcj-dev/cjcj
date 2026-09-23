import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';

test('artifact wins over an available fallback tuple', () => fixture(({artifact, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_TUPLE=${artifact}\n`), result.stdout);
  console.log('ASSERT artifact-precedence executed');
}));

test('reviewed sums pin rejects altered tuple bytes', () => fixture(({env, fallback, run}) => {
  // Isolate the digest contract from artifact-selection policy.
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  fs.writeFileSync(path.join(fallback, 'SHA256SUMS'), 'altered');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /SHA256SUMS disagrees/);
  console.log('ASSERT reviewed-pin rejection executed');
}));

test('explicit tuple fallback remains usable with the same reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_TUPLE=${fallback}\n`));
  console.log('ASSERT fallback executed');
}));

test('nested kkk2 depot remains a fallback under the same reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  delete env.CJCJ_BOOTSTRAP_COLOUR_TUPLE;
  env.CJCJ_LLVM_DEPOT_ROOT = path.join(path.dirname(fallback), 'depot');
  env.CANGJIE_COMPILER_SHA = 'c'.repeat(40);
  const nested = path.join(env.CJCJ_LLVM_DEPOT_ROOT, env.LLVM_SHA, env.CANGJIE_COMPILER_SHA);
  fs.mkdirSync(nested, {recursive: true});
  fs.copyFileSync(path.join(fallback, 'SHA256SUMS'), path.join(nested, 'SHA256SUMS'));
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_TUPLE=${nested}\n`));
  console.log('ASSERT nested-depot fallback executed');
}));
