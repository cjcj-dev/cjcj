import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

export function fixture(check) {
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

