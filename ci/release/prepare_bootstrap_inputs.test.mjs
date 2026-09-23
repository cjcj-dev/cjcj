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
    const env = {...process.env, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_SOURCE: 'depot', CJCJ_BOOTSTRAP_SOURCE_REASON: 'fixture explicit depot',
      CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback, CJCJ_BOOTSTRAP_INPUTS_WORK: path.join(dir, 'work'),
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, LLVM_SHA: 'a'.repeat(40),
      CJCJ_BOOTSTRAP_CJCJ_SHA: 'b'.repeat(40), LLVM_TUPLE_SUMS_SHA: digest};
    const pinFile = path.join(dir, 'pin.json');
    fs.writeFileSync(pinFile, JSON.stringify({version: 1, repository: 'cjcj-dev/cjcj', run: 123,
      attempt: 1, artifact: 456, commit: 'b'.repeat(40), files: [{path: 'SHA256SUMS',
      asset: 789, artifact_sha256: digest, release_sha256: digest}]}));
    env.CJCJ_BOOTSTRAP_INPUTS_PIN = pinFile;
    const run = () => spawnSync(process.execPath,
      [new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    check({env, artifact, fallback, run});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

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
