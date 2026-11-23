import assert from 'node:assert/strict';
import path from 'node:path';
import {toCommandPath} from './common.mjs';

const workspace = String.raw`D:\a\cjcj\cjcj`;
const runnerTemp = path.win32.join(workspace, String.raw`_temp`);
const cases = [
  path.win32.join(workspace, 'runtime-source'),
  path.win32.join(runnerTemp, 'cjv_windows_amd64.zip'),
  path.win32.join(runnerTemp, 'cjv-windows'),
  path.win32.join(workspace, '.platform-ci', 'fixed-toolchain', 'windows_x86_64', 'llc.gz'),
];

for (const input of cases) {
  const output = toCommandPath(input);
  assert.equal(output, input.replaceAll('\\', '/'));
  assert.doesNotMatch(output, /[\x00-\x1f\x7f]/);
  assert.doesNotMatch(output, /\\/);
}

const expandArchive = `Expand-Archive -LiteralPath '${toCommandPath(cases[1])}' -DestinationPath '${toCommandPath(cases[2])}' -Force`;
assert.doesNotMatch(expandArchive, /[\x00-\x1f\x7f]/);
console.log(`SIMULATED_OK paths=${cases.length} workspace=${toCommandPath(workspace)}`);
