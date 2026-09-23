import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';

test('reviewed sums pin rejects altered tuple bytes', () => fixture(({env, fallback, run}) => {
  // Isolate the digest contract from artifact-selection policy.
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  fs.writeFileSync(path.join(fallback, 'SHA256SUMS'), 'altered');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: SHA256SUMS/);
  console.log('ASSERT reviewed-pin rejection executed');
}));

test('explicit tuple fallback remains usable with the same reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED SHA256SUMS/);
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
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED SHA256SUMS/);
  console.log('ASSERT nested-depot fallback executed');
}));


test('prepare defaults to persistent source despite unavailable artifact run', () => fixture(({env, pinFile, run}) => {
  delete env.CJCJ_BOOTSTRAP_SOURCE;
  delete env.CJCJ_BOOTSTRAP_SOURCE_REASON;
  const pin = JSON.parse(fs.readFileSync(pinFile));
  pin.run = 999999999;
  fs.writeFileSync(pinFile, JSON.stringify(pin));
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_SOURCE mode=release/);
  const output = /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=(.+)$/m.exec(result.stdout)?.[1];
  assert.ok(output, result.stdout);
  assert.equal(fs.readFileSync(path.join(output, 'SHA256SUMS'), 'utf8'), 'reviewed fixture sums');
  console.log('ASSERT prepare persistent bytes exported with unavailable artifact run');
}));

test('prepare refuses changed persistent input before exporting bootstrap environment', () => fixture(({env, artifact, run}) => {
  delete env.CJCJ_BOOTSTRAP_SOURCE;
  fs.writeFileSync(path.join(artifact, 'SHA256SUMS'), 'replaced persistent sums');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: SHA256SUMS/);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT prepare persistent digest rejection executed');
}));

// Separate assertions make selection and integrity cuts independently visible.
test('ast artifact wins over an available fallback archive', () => fixture(({env, artifact, run}) => {
  const ast = path.join(artifact, 'libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  env.CJCJ_BOOTSTRAP_AST_ARTIFACT = ast;
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT=${ast}\n`));
  console.log('ASSERT ast artifact-precedence executed');
}));

test('ast reviewed pin rejects changed bytes while tuple stays valid', () => fixture(({env, run}) => {
  fs.writeFileSync(env.CJCJ_BOOTSTRAP_AST_SUPPORT, 'wrong archive');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ast-support archive SHA256 disagrees/);
  console.log('ASSERT ast reviewed-pin rejection executed');
}));

test('missing selected ast artifact cannot fall back', () => fixture(({env, artifact, run}) => {
  env.CJCJ_BOOTSTRAP_AST_ARTIFACT = path.join(artifact, 'missing.a');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ENOENT/);
}));

test('kkk2 ast build directory fallback uses the reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_AST_SUPPORT;
  env.CANGJIE_BUILD_ROOT = fallback;
  fs.mkdirSync(path.join(fallback, 'lib'));
  const ast = path.join(fallback, 'lib/libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT=${ast}\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256=${env.AST_SUPPORT_SHA256}\n`));
  console.log('ASSERT ast kkk2 fallback and reviewed digest executed');
}));
