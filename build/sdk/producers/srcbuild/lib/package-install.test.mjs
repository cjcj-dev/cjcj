import test from 'node:test';
import assert from 'node:assert/strict';
import {packageConsumption} from './package-install.mjs';

test('native consumption executes on the host', () => {
  const result = packageConsumption({spec: {crossCompile: false, llvmPlatform: 'linux_x86_64'}});
  assert.deepEqual(result, {status: 'EXECUTED', platform: 'linux_x86_64'});
  assert.notEqual(result.status, 'PASS');
});

test('cross consumption is not a host pass', () => {
  const result = packageConsumption({spec: {crossCompile: true, llvmPlatform: 'windows_x86_64'}});
  assert.deepEqual(result, {status: 'NOT_RUN', reason: 'HOST_CROSS_EXEC', platform: 'windows_x86_64'});
  assert.notEqual(result.status, 'PASS');
  console.log('CROSS_CONSUMPTION_REACHED ' + JSON.stringify(result));
});
