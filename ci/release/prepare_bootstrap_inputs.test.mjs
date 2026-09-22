import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

test('artifact wins over depot; reviewed sums pin rejects altered bytes', () => {
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
    fs.writeFileSync(path.join(artifact, 'SHA256SUMS'), 'reviewed fixture sums');
    fs.writeFileSync(path.join(fallback, 'SHA256SUMS'), 'reviewed fixture sums');
    const digest = crypto.createHash('sha256').update('reviewed fixture sums').digest('hex');
    const env = {...process.env, GITHUB_ENV: '', CJCJ_SRCBUILD_HOST_SDK: sdk,
      CJCJ_BOOTSTRAP_HOST_LLVM_SO: so, CJCJ_BOOTSTRAP_AST_SUPPORT: ast,
      CJCJ_BOOTSTRAP_TUPLE_ARTIFACT: artifact, CJCJ_BOOTSTRAP_COLOUR_TUPLE: fallback,
      CJCJ_BOOTSTRAP_CPP_SRC: sdk, LLVM_SHA: 'a'.repeat(40),
      CJCJ_BOOTSTRAP_CJCJ_SHA: 'b'.repeat(40), LLVM_TUPLE_SUMS_SHA: digest};
    const run = () => spawnSync(process.execPath,
      [new URL('./prepare_bootstrap_inputs.mjs', import.meta.url).pathname], {env, encoding: 'utf8'});
    let result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_TUPLE=${artifact}\n`), result.stdout);
    console.log('ASSERT artifact-precedence executed');
    fs.writeFileSync(path.join(artifact, 'SHA256SUMS'), 'altered');
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /SHA256SUMS disagrees/);
    console.log('ASSERT reviewed-pin rejection executed');
    fs.writeFileSync(path.join(fallback, 'SHA256SUMS'), 'reviewed fixture sums');
    delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
    result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_TUPLE=${fallback}\n`));
    console.log('ASSERT fallback executed');
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
