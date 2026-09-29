import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

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

// This is a command-plan check of the real bootstrap CLI, not evidence that a
// hosted compiler build finished. Existing bootstrap tests cover combined mode.
test('split CLI routes each expensive build to exactly one phase and preserves cache settings', async () => {
  const harness = path.resolve(import.meta.dirname, '../../bootstrap/test_bootstrap.sh');
  const run = promisify(execFile);
  await Promise.all(['stage1-initial-std', 'stage1-std', 'stage1-compiler'].map(async phase => {
    const {stdout} = await run('bash', [harness, 'dry-run', phase], {
      env: {...process.env, CMAKE_C_COMPILER_LAUNCHER: '/cache/sccache',
        CMAKE_CXX_COMPILER_LAUNCHER: '/cache/sccache', SCCACHE_DIR: '/cache/objects'},
      maxBuffer: 4 * 1024 * 1024,
    });
    assert.match(stdout, new RegExp(`BOOTSTRAP-OK 到 ${phase} `));
    const builds = stdout.split('\n').filter(line => line.startsWith('CMD env -i ') && line.includes(' bash -c '));
    assert.equal(builds.length, 1, `${phase}: must plan exactly one expensive build`);
    assert.match(builds[0], /CMAKE_C_COMPILER_LAUNCHER=\/cache\/sccache/);
    assert.match(builds[0], /CMAKE_CXX_COMPILER_LAUNCHER=\/cache\/sccache/);
    assert.match(builds[0], /SCCACHE_DIR=\/cache\/objects/);
    assert.match(builds[0], phase === 'stage1-initial-std' ? /stdlib-stage1/
      : phase === 'stage1-std' ? /stdlib-stage2/ : /cjcj-src-stage1/);
    assert.equal((stdout.match(/^CMD cjpm build/gm) || []).length, phase === 'stage1-compiler' ? 1 : 0);
    console.log(`PHASE_ASSERT phase=${phase} expensive-builds=${builds.length} cache=inherited`);
  }));
});
