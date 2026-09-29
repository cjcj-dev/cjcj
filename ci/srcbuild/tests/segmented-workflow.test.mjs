import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

const file = path.resolve(import.meta.dirname, '../../../.github/workflows/srcbuild.yml');
const workflow = await fs.readFile(file, 'utf8');
const jobs = new Map([...workflow.matchAll(/^  ([\w-]+):\n([\s\S]*?)(?=^  [\w-]+:\n|$(?![\s\S]))/gm)]
  .map(([, name, body]) => [name, body]));
const phases = ['stage0', 'stage1-initial-std', 'stage1-std', 'stage1-compiler', 'stage3'];

test('each bootstrap phase has a distinct standard-runner job and verified predecessor', () => {
  for (const [index, phase] of phases.entries()) {
    const body = jobs.get(`source-${phase}`);
    assert.ok(body, phase);
    assert.match(body, /runs-on: \$\{\{ matrix.runner \}\}/);
    assert.match(body, /timeout-minutes: 360/);
    assert.match(body, new RegExp(`job-handoff.mjs pack ${phase} `));
    if (index) {
      const previous = phases[index - 1];
      assert.match(body, new RegExp(`needs: \\[plan, source-${previous}\\]`));
      assert.match(body, new RegExp(`job-handoff.mjs restore ${previous} `));
      const verify = body.indexOf(`job-handoff.mjs restore ${previous} `);
      const compile = body.search(/run: (bash ci\/bootstrap\/gha_run|npx.*build-stage3)/);
      assert.ok(compile > verify, `${phase}: consumer must execute after verification`);
    }
    assert.equal((body.match(/run: bash ci\/bootstrap\/gha_run.sh /g) || []).length, phase === 'stage3' ? 0 : 1);
  }
  console.log('PHASE_ASSERT distinct-jobs=5 verified-consumer-order=4');
});

test('native packaging, Android, MinGW and Windows std occupy distinct jobs', () => {
  for (const name of ['srcbuild', 'source-android', 'source-mingw', 'source-windows']) assert.ok(jobs.has(name), name);
  assert.match(jobs.get('srcbuild'), /needs: \[plan, source-stage3\]/);
  assert.match(jobs.get('source-android'), /needs: \[plan, source-stage3\]/);
  assert.match(jobs.get('source-mingw'), /needs: \[plan, source-stage3\]/);
  assert.match(jobs.get('source-windows'), /needs: \[plan, source-mingw\]/);
  assert.doesNotMatch(jobs.get('srcbuild'), /run:.*(build-android-final-std|install-mingw|build-windows-final-std)/);
  assert.doesNotMatch(jobs.get('source-windows'), /run:.*install-mingw/);
});
