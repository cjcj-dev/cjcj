import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fixture} from '../release/prepare_bootstrap_fixture.mjs';

for (const [target, platform] of [['linux-x64', 'linux_x86_64'], ['linux-aarch64', 'linux_aarch64']]) {
  test(`producer CLI binds ${platform} runtime and coloured std`, () => fixture(({env, runtimeSource}) => {
    const output = path.join(path.dirname(runtimeSource), 'packaged');
    const result = spawnSync(process.execPath, [new URL('../release/colour_runtime.mjs', import.meta.url).pathname,
      runtimeSource, output], {encoding: 'utf8', env: {...env, COLOUR_RT_PLATFORM: platform,
      GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1', GITHUB_OUTPUT: ''}});
    assert.equal(result.status, 0, result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(output, 'manifest.json')));
    assert.equal(manifest.platform, platform);
    assert.equal(manifest.runtime_sha, env.RUNTIME_REF);
    for (const file of [`runtime/lib/${platform}_cjnative/libcangjie-runtime.so`,
      `runtime/lib/${platform}_cjnative/libboundscheck.so`, `lib/${platform}_cjnative/libcangjie-runtime.a`,
      `lib/${platform}_cjnative/libcangjie-std-core.a`, `modules/${platform}_cjnative/std.core.cjo`]) {
      assert.deepEqual(fs.readFileSync(path.join(output, file)), fs.readFileSync(path.join(runtimeSource, file)));
      assert.match(manifest.files[file], /^[a-f0-9]{64}$/);
    }
    console.log(`ASSERT producer ${platform} manifest and payload bytes executed`);
  }, target));

  test(`bootstrap CLI consumes ${platform} and rejects changed native runtime`, () => fixture(({runtime, run}) => {
    const accepted = run();
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.ok(accepted.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_RT=${runtime}\n`));
    const file = `runtime/lib/${platform}_cjnative/libcangjie-runtime.so`;
    fs.appendFileSync(path.join(runtime, file), 'changed runtime');
    const rejected = run();
    assert.notEqual(rejected.status, 0);
    assert.ok(rejected.stderr.includes(`COLOUR_RT_FILE_SHA256_MISMATCH: ${file}`), rejected.stderr);
    console.log(`ASSERT consumer ${platform} selected runtime bytes executed`);
  }, target));
}

test('aarch64 bootstrap rejects a valid x86_64 manifest before payload access', () => fixture(({env, run}) => {
  // Change only the requested platform; retain the real producer's manifest,
  // payloads, runtime SHA and reviewed digest, so the platform guard is tested.
  env.COLOUR_RT_PLATFORM = 'linux_aarch64';
  env.CJCJ_SRCBUILD_TARGET = 'linux-aarch64';
  const result = run();
  assert.match(result.stderr, /COLOUR_RT_MANIFEST_MISMATCH/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /CJCJ_BOOTSTRAP_COLOUR_RT=/);
  console.log('ASSERT cross-platform manifest rejection executed');
}));
