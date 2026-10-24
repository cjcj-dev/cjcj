#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';
const arm = process.env.ARM;
assert.ok(['candidate', 'cut-producer', 'cut-consumer', 'restored'].includes(arm), 'unknown iOS arm');
const temporary = process.env.RUNNER_TEMP;
assert.ok(temporary, 'RUNNER_TEMP is required');
if (argv.action === 'prepare') {
  let restoration;
  const file = arm === 'cut-consumer' ? 'ci/release/cross-runtime.mjs' : 'ci/srcbuild/lib/ios-runtime.mjs';
  if (arm !== 'candidate') {
    const source = await fs.readFile(file, 'utf8');
    const needle = arm === 'cut-consumer' ? 'await fs.copyFile(path.join(root, file.path), destination);'
      : "`${target.runtimeArch}_Release`, 'libboundscheck.dylib'";
    assert.equal(source.split(needle).length, 2, 'one product bearing line');
    const cut = arm === 'cut-consumer' ? 'await fs.writeFile(destination, "cut");'
      : "`${target.runtimeArch}_Release`, 'libcangjie-runtime.dylib'";
    await fs.writeFile(file, source.replace(needle, cut));
    if (arm === 'restored') restoration = source;
  }
  const diff = (await $({stdio: 'pipe'})`git diff`).stdout;
  await fs.writeFile(path.join(temporary, 'ios-cut.diff'), diff);
  if (restoration) await fs.writeFile(file, restoration);
  await $`shasum -a 256 ci/srcbuild/lib/ios-runtime.mjs ci/release/cross-runtime.mjs ci/release/verify-ios-runtime.mjs`;
} else {
  assert.equal(argv.action, 'verify', 'action must be prepare or verify');
  const result = await $({nothrow: true, stdio: 'pipe'})`node ci/release/verify-ios-runtime.mjs`;
  const output = result.stdout + result.stderr;
  await fs.writeFile(path.join(temporary, 'ios-assertion.log'), output);
  console.log(output);
  console.log(`IOS_ARM=${arm} ASSERT_RC=${result.exitCode}`);
  assert.equal(result.exitCode, arm.startsWith('cut-') ? 1 : 0);
  if (arm === 'cut-producer') assert.match(output, /IOS_BOUNDSCHECK_SAME_BUILD_BYTES/);
  if (arm === 'cut-consumer') assert.match(output, /IOS_INSTALLED_RUNTIME_BYTES/);
}
