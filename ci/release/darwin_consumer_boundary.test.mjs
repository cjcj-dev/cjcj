import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {darwinConsumerHost} from './consume_darwin_inputs.mjs';
import {darwinPlatform} from './darwin_llvm.mjs';

test('both Darwin layouts come from the SDK platform mapping', () => {
  for (const platform of ['darwin_aarch64', 'darwin_x86_64']) {
    const native = darwinPlatform(platform);
    assert.equal(native.tuple, `${platform}_cjnative`);
    assert.equal(native.llvmLibrary, 'libLLVM.dylib');
    assert.equal(native.shared, '.dylib');
  }
  assert.throws(() => darwinPlatform('linux_x86_64'), /DARWIN_INPUT_PLATFORM/);
});
test('host/target guard precedes input acquisition', () => {
  assert.throws(() => darwinConsumerHost('linux-x64'),
    process.platform === 'darwin' ? /DARWIN_CONSUMER_HOST_TARGET/ : /DARWIN_CONSUMER_NATIVE_HOST/);
  if (process.platform === 'darwin') assert.equal(darwinConsumerHost(`darwin-${process.arch}`).arch, process.arch);
});
for (const entry of ['darwin_consumer_ci.mjs', 'consume_darwin_inputs.mjs']) {
  test(`actual ${entry} rejects incompatible target before commands or output`, () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-boundary-'));
    try {
      const output = path.join(root, 'not-created');
      const result = spawnSync(process.execPath, [new URL(entry, import.meta.url).pathname, output, 'linux-x64'], {
        env:{...process.env, CJCJ_SRCBUILD_TARGET:'linux-x64', PATH:root}, encoding:'utf8'});
      assert.equal(result.status, 1, result.stderr);
      assert.match(result.stderr, process.platform === 'darwin' ? /DARWIN_CONSUMER_HOST_TARGET/ : /DARWIN_CONSUMER_NATIVE_HOST/);
      assert.equal(fs.existsSync(output), false);
      assert.doesNotMatch(result.stderr, /ERR_MODULE_NOT_FOUND|ENOENT|COMMAND_FAILED/);
    } finally { fs.rmSync(root, {recursive:true, force:true}); }
  });
}
