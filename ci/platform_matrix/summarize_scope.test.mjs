import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const runners = ['macos-26', 'macos-26-intel', 'macos-15', 'macos-15-intel',
  'ubuntu-24.04', 'ubuntu-24.04-arm', 'ubuntu-22.04', 'ubuntu-22.04-arm',
  'windows-2025', 'windows-2022'];
const switches = ['runtime_only', 'linux_native_only', 'std_evidence_only', 'darwin_runtime_only',
  'darwin_host_only', 'darwin_verify_only'];

function summary(inputs) {
  const dir = mkdtempSync(join(tmpdir(), 'matrix-scope-'));
  try {
    const path = join(dir, 'summary.md');
    const result = spawnSync(process.execPath, ['ci/platform_matrix/summarize_scope.mjs'], {
      env: { ...process.env, MATRIX_INPUTS: JSON.stringify(inputs), GITHUB_STEP_SUMMARY: path },
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    return readFileSync(path, 'utf8');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

for (const key of switches) {
  test(`${key} reports every skipped platform job`, () => {
    const text = summary({ [key]: true });
    assert.match(text, /this run does not establish a platform matrix pass/);
    assert.deepEqual(text.split('\n').filter(line => line.startsWith('- ')),
      runners.map(runner => `- ${runner} / runtime + cjcj + smoke`));
    assert.ok(text.includes(`\`${key}\``));
  });
}
test('full dispatch and push do not list skipped jobs', () => {
  for (const inputs of [{}, Object.fromEntries(switches.map(key => [key, false])),
    Object.fromEntries(switches.map(key => [key, 'false']))]) {
    const text = summary(inputs);
    assert.match(text, /Full platform matrix requested \(10 jobs\)/);
    assert.ok(!text.includes('skipped'));
    assert.ok(!text.includes('\n- '));
  }
});
test('combined subset inputs retain all reasons and one runner list', () => {
  const text = summary(Object.fromEntries(switches.map(key => [key, 'true'])));
  for (const key of switches) assert.ok(text.includes(`\`${key}\``));
  assert.equal(text.split('\n').filter(line => line.startsWith('- ')).length, runners.length);
});
