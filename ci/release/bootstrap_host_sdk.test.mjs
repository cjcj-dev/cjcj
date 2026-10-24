import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import {baseSdkDownload} from '../../build/lib/release-component-provenance.mjs';
import {hostPlatform, readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {fixture} from './prepare_bootstrap_fixture.mjs';

const identities = new URL('../bootstrap/stage1_host_identities.txt', import.meta.url);
const records = () => fs.readFileSync(identities, 'utf8').split('\n')
  .filter(line => line.startsWith('# HOST_SDK_PROVENANCE '))
  .map(line => JSON.parse(line.slice('# HOST_SDK_PROVENANCE '.length)));
const platforms = {'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64',
  'darwin-x64': 'darwin_x86_64', 'darwin-arm64': 'darwin_aarch64', 'windows-x64': 'windows_x86_64'};
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

for (const [key, platform] of Object.entries(platforms)) {
  test(`checked-in bootstrap SDK identity preserves the authenticated ${key} archive`, () => {
    const matching = records().filter(record => record.platform === platform);
    const expected = baseSdkDownload(key, readHostToolchainPin(key));
    const observed = matching.map(({platform: _platform, ...record}) => record);
    console.log(`DEFAULT_RECORD_ASSERT platform=${platform} ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, [{archive: expected.archive, version: expected.version,
      url: expected.url, size: expected.size, sha256: expected.sha256}]);
  });
}

test('cross target preparation consumes the execution host SDK without changing target dependency pins', () => fixture(({env, run}) => {
  const result = run();
  const observed = {rc: result.status,
    host: result.stdout.includes(`HOST_SDK_VERIFIED platform=${hostPlatform()} `),
    targetLlvm: result.stdout.includes('HOST_LLVM_VERIFIED run=123 artifact=456 '),
    exported: /^CJCJ_BOOTSTRAP_BASE=/m.test(result.stdout)};
  console.log(`EXECUTION_HOST_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rc: 0, host: true, targetLlvm: true, exported: true}, result.stderr);
}, 'linux-aarch64'));

test('explicit current SDK pair retains its scalar toolchain under the production host selector', () => fixture(({env, run}) => {
  env.CJCJ_TOOLCHAIN = readHostToolchainPin();
  env.CJCJ_TOOLCHAIN_LINUX_AARCH64 = readHostToolchainPin('linux-aarch64');
  const result = run();
  const observed = {rc: result.status, verified: result.stdout.includes(`HOST_SDK_VERIFIED platform=${hostPlatform()} `),
    exported: /^CJCJ_BOOTSTRAP_BASE=/m.test(result.stdout)};
  console.log(`EXPLICIT_PAIR_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rc: 0, verified: true, exported: true}, result.stderr);
}));
