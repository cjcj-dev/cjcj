import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import path from 'node:path';

const runner = path.join(import.meta.dirname, 'test_difftest_timeout.mjs');
for (const args of [[], ['--matrix'], ['--lifecycle'], ['--lifecycle', '--cancel', 'SIGTERM'],
  ['--lifecycle', '--cancel', 'SIGINT'], ['--lifecycle', '--escape']]) {
  test(`difftest real CLI ${args.join(' ') || 'classification and G8'}`, {timeout: 160_000}, () => {
    const command = process.env.DIFFTEST_TEST_ZX ? process.execPath : 'npx';
    const prefix = process.env.DIFFTEST_TEST_ZX ? [process.env.DIFFTEST_TEST_ZX] : ['--offline', '--yes', 'zx@8'];
    const result = spawnSync(command, [...prefix, runner, ...args,
      ...(process.env.DIFFTEST_TEST_SCRIPT ? ['--script', process.env.DIFFTEST_TEST_SCRIPT] : [])],
      {encoding: 'utf8', timeout: 150_000, maxBuffer: 4 * 1024 * 1024});
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  });
}
