import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

function fixture(check) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-inputs-'));
  try {
    const sdk = path.join(dir, 'sdk');
    const artifact = path.join(dir, 'artifact');
    const fallback = path.join(dir, 'fallback');
    for (const d of [sdk, artifact, fallback]) fs.mkdirSync(d);
    const so = path.join(sdk, 'host.so');
    const ast = path.join(sdk, 'ast.a');
    fs.writeFileSync(so, 'host fixture');
    fs.writeFileSync(ast, 'ast fixture');
    for (const d of [artifact, fallback]) {
      fs.writeFileSync(path.join(d, 'SHA256SUMS'), 'reviewed fixture sums');
    }
    const digest = crypto.createHash('sha256').update('reviewed fixture sums').digest('hex');
    const dylib = path.join(dir, 'dylib');
    fs.mkdirSync(dylib);
    const libraryBytes = process.env.DYLIB_TEST_FILE
      ? fs.readFileSync(process.env.DYLIB_TEST_FILE) : Buffer.from('reviewed dylib fixture');
    fs.writeFileSync(path.join(dylib, 'libLLVM-15.so'), libraryBytes);
    const dylibSha = crypto.createHash('sha256').update(libraryBytes).digest('hex');
    fs.writeFileSync(path.join(dylib, 'manifest.json'), JSON.stringify({
      llvm_sha: 'a'.repeat(40), sha256: dylibSha, targets: ['X86', 'ARM', 'AArch64']}));
    const dylibFallback = path.join(dir, 'dylib-fallback');
    fs.cpSync(dylib, dylibFallback, {recursive: true});
    const env = {...process.env, CJCJ_BOOTSTRAP_COLOUR_DYLIB: dylibFallback, CJCJ_BOOTSTRAP_DYLIB_ARTIFACT: dylib, LLVM_DYLIB_SHA256: dylibSha, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_TUPLE_ARTIFACT: artifact, CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback,
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, LLVM_SHA: 'a'.repeat(40),
      CJCJ_BOOTSTRAP_CJCJ_SHA: 'b'.repeat(40), LLVM_TUPLE_SUMS_SHA: digest};
    const run = () => spawnSync(process.execPath,
      [new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    check({env, artifact, fallback, dylib, dylibSha, so, run});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

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
