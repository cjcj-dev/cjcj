import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import test from 'node:test';
import {cleanSdkEnvironment, sdkEnvironment} from './sdk-platform.mjs';

function host(t, platform) {
  const descriptor = Object.getOwnPropertyDescriptor(process, 'platform');
  Object.defineProperty(process, 'platform', {...descriptor, value: platform});
  t.after(() => Object.defineProperty(process, 'platform', descriptor));
}

test('Darwin native compiler environments resolve a missing or empty SDKROOT once', t => {
  host(t, 'darwin');
  const lookup = t.mock.method(childProcess, 'execFileSync', (cmd, args) => {
    assert.equal(cmd, 'xcrun');
    assert.deepEqual(args, ['--sdk', 'macosx', '--show-sdk-path']);
    return '/Xcode SDK/MacOSX.sdk\n';
  });
  const base = {SDKROOT: ''};
  assert.equal(cleanSdkEnvironment('/host', 'darwin_aarch64', base).SDKROOT, '/Xcode SDK/MacOSX.sdk');
  assert.equal(sdkEnvironment('/sdk', 'darwin_x86_64', {}).SDKROOT, '/Xcode SDK/MacOSX.sdk');
  assert.equal(lookup.mock.callCount(), 1);
  assert.equal(base.SDKROOT, '');
});

test('explicit SDKROOT, other targets and non-Darwin hosts never query xcrun', t => {
  const lookup = t.mock.method(childProcess, 'execFileSync', () => assert.fail('unexpected SDK lookup'));
  host(t, 'darwin');
  assert.equal(cleanSdkEnvironment('/sdk', 'darwin_aarch64', {SDKROOT: '/explicit'}).SDKROOT, '/explicit');
  assert.equal(cleanSdkEnvironment('/sdk', 'linux_x86_64', {}).SDKROOT, undefined);
  Object.defineProperty(process, 'platform', {value: 'linux'});
  assert.equal(cleanSdkEnvironment('/sdk', 'darwin_x86_64', {SDKROOT: ''}).SDKROOT, '');
  assert.equal(lookup.mock.callCount(), 0);
});
