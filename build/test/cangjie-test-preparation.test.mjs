import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const execute = promisify(execFile);
for (const [name, script, marker] of [
  ['bootstrap independent compiler identity', '../../ci/cangjie-test/verify_bootstrap_identity.py', 'BOOTSTRAP_OFFICIAL_TARGET rejected= True'],
  ['seven-way upstream result triage', '../../ci/cangjie-test/verify_classify.py', 'CLASSIFY_EXACT_DELTA'],
  ['compiler producer and frontend SDK entry', '../../ci/bootstrap/compiler-identity.integration.test.mjs', 'SDK_VERIFY_FRONTEND_RESTORED'],
]) {
  test(name, {concurrency: true}, async () => {
    const result = await execute(script.endsWith('.mjs') ? process.execPath : 'python3',
      [fileURLToPath(new URL(script, import.meta.url))]).catch(error => {
        // Nested node:test failures report their diagnostic TAP on stdout.
        process.stdout.write(error.stdout || '');
        process.stderr.write(error.stderr || '');
        throw error;
      });
    assert.match(result.stdout, new RegExp(marker));
    process.stdout.write(result.stdout);
  });
}
