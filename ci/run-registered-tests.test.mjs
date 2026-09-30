import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {runScripts} from './run-registered-tests.mjs';
import {repoRoot} from './test-manifest.mjs';

test('script CLI executes the registered resource-selector assertions', async () => {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'registered-cli-'));
  try {
    const output = path.join(work, 'results');
    const child = spawnSync(process.execPath,
      ['ci/run-registered-tests.mjs', 'scripts', output, 'ci/test_build_resources.py'],
      {cwd: repoRoot, encoding: 'utf8'});
    const report = JSON.parse(await fs.readFile(path.join(output, 'results.json'), 'utf8'));
    assert.deepEqual(report.results.map(result => result.file), ['ci/test_build_resources.py']);
    const log = await fs.readFile(report.results[0].log, 'utf8');
    assert.match(log, /ASSERT oversized request capped to measured physical-memory budget/);
    assert.equal(report.results[0].rc, 0, log);
    assert.equal(child.status, 0, child.stdout + child.stderr);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('script executor preserves each real subprocess exit and output argument', async () => {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'registered-exit-'));
  try {
    await fs.writeFile(path.join(work, 'test_green.py'), 'print("CONTROL_GREEN")\n');
    await fs.writeFile(path.join(work, 'test_red.sh'), 'printf "%s\\n" "$1"\nexit 7\n');
    const results = await runScripts(work, [
      {file: 'test_green.py', executor: 'python3', args: []},
      {file: 'test_red.sh', executor: 'bash', args: ['{output}']},
    ], path.join(work, 'logs'));
    assert.deepEqual(results.map(result => result.rc), [0, 7]);
    assert.match(await fs.readFile(results[0].log, 'utf8'), /CONTROL_GREEN/);
    assert.equal((await fs.readFile(results[1].log, 'utf8')).trim(), path.join(work, 'logs/test_red.sh/output'));
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});
