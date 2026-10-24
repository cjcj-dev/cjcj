import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import path from 'node:path';

const runner = path.join(import.meta.dirname, 'test_difftest_timeout.mjs');
for (const args of [[], ['--matrix'], ['--loader'], ['--lifecycle'], ['--lifecycle', '--cancel', 'SIGTERM'],
  ['--lifecycle', '--cancel', 'SIGINT'], ['--lifecycle', '--escape'],
  ['--lifecycle', '--cancel', 'SIGTERM', '--identity-delay'],
  ['--lifecycle', '--cancel', 'SIGINT', '--identity-delay'],
  ['--lifecycle', '--cancel', 'SIGTERM', '--identity-invalid'],
  ['--lifecycle', '--cancel', 'SIGTERM', '--identity-never']]) {
  test(`difftest real CLI ${args.join(' ') || 'classification and G8'}`, {timeout: 160_000}, () => {
    const command = process.env.DIFFTEST_TEST_ZX ? process.execPath : 'npx';
    const prefix = process.env.DIFFTEST_TEST_ZX ? [process.env.DIFFTEST_TEST_ZX] : ['--yes', 'zx@8'];
    const result = spawnSync(command, [...prefix, runner, ...args,
      ...(process.env.DIFFTEST_TEST_SCRIPT ? ['--script', process.env.DIFFTEST_TEST_SCRIPT] : [])],
      // Use the CI adapter's fixed-package syntax; real npm also stays offline.
      {env: {...process.env, npm_config_offline: 'true'},
        encoding: 'utf8', timeout: 150_000, maxBuffer: 4 * 1024 * 1024});
    assert.equal(result.error, undefined);
    const expectedPreparationError = args.includes('--identity-invalid') ? 'INVALID_DESCENDANT_IDENTITY'
      : args.includes('--identity-never') ? 'DESCENDANT_READY_TIMEOUT' : '';
    assert.equal(result.status, expectedPreparationError ? 1 : 0, `${result.stdout}\n${result.stderr}`);
    if (expectedPreparationError) {
      assert.match(result.stderr, new RegExp(expectedPreparationError));
      assert.doesNotMatch(result.stdout, /PASS descendant lifecycle/);
    } else {
      const completion = args.includes('--lifecycle') ? 'PASS descendant lifecycle, cancellation or bounded escaped-pipe failure'
        : args.includes('--matrix') ? 'PASS matrix controls, single-arm failures, loader, output/pipe bounds, unrelated process'
        : args.includes('--loader') ? 'PASS g8-preserves-match-and-unknown'
        : 'PASS g8-refuses-unqualified-normal-controls';
      assert.ok(result.stdout.split('\n').includes(completion),
        `difftest driver did not reach ${completion}\n${result.stdout}\n${result.stderr}`);
    }
  });
}
