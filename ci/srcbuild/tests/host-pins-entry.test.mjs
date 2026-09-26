import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fileSha256} from '../lib/final-compiler.mjs';

const cli = fileURLToPath(new URL('../../release/write_host_pins.py', import.meta.url));
const sdk = process.env.SOURCE_TUPLE_OFFICIAL_SDK;
const llvm = process.env.SOURCE_TUPLE_HOST_LLVM;
for (const changed of [null, 'CJCJ_HOST_RUNTIME_SHA256', 'CJCJ_HOST_BOUNDSCHECK_SHA256', 'CJCJ_BOOTSTRAP_HOST_LLVM_SHA256']) {
  test(`host identity entry ${changed ?? 'binds selected inputs'}`, {skip: !sdk || !llvm}, async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'host-pins-'));
    try {
      const rows = [
        ['libcangjie-runtime.so', path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'CJCJ_HOST_RUNTIME_SHA256'],
        ['libboundscheck.so', path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libboundscheck.so'), 'CJCJ_HOST_BOUNDSCHECK_SHA256'],
        ['libLLVM-15.so', llvm, 'CJCJ_BOOTSTRAP_HOST_LLVM_SHA256'],
      ];
      const env = {...process.env, CJCJ_SRCBUILD_HOST_SDK: sdk, CJCJ_BOOTSTRAP_HOST_LLVM_SO: llvm};
      for (const [, file, key] of rows) env[key] = await fileSha256(file);
      const expected = rows.map(([name, , key]) => `${name} ${env[key]}\n`).join('');
      if (changed) env[changed] = '0'.repeat(64);
      const output = path.join(dir, 'identities');
      const result = spawnSync('python3', [cli, output], {env, encoding: 'utf8'});
      console.log(`HOST_IDENTITY_ASSERT_REACHED input=${changed ?? 'valid'} rc=${result.status}`);
      assert.equal(result.status, changed ? 1 : 0, result.stderr);
      if (changed) {
        assert.match(result.stderr, /HOST_PIN_MISMATCH/);
        await assert.rejects(fs.stat(output), {code: 'ENOENT'});
      } else assert.equal(await fs.readFile(output, 'utf8'), expected);
    } finally { await fs.rm(dir, {recursive: true, force: true}); }
  });
}
