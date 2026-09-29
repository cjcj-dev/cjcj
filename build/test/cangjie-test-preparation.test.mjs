import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const execute = promisify(execFile);
for (const [name, script, marker] of [
  ['seven-way upstream result triage', '../../ci/cangjie-test/verify_classify.py', 'CLASSIFY_EXACT_DELTA'],
  ['compiler producer and frontend SDK entry', '../../ci/bootstrap/test_compiler_identity.py', 'SDK_VERIFY_FRONTEND_RESTORED'],
]) {
  test(name, {concurrency: true}, async () => {
    const result = await execute('python3', [fileURLToPath(new URL(script, import.meta.url))]);
    assert.match(result.stdout, new RegExp(marker));
    process.stdout.write(result.stdout);
  });
}
