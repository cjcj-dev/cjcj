// Execute the source workflow's actual shell entries against a downloaded input.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const [artifact, platform] = process.argv.slice(2);
assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform));
const workflow = fs.readFileSync('.github/workflows/srcbuild.yml', 'utf8');
function command(name) {
  const start = workflow.indexOf(`      - name: ${name}\n`);
  assert.notEqual(start, -1, name);
  const end = workflow.indexOf('\n      - ', start + 1);
  const step = workflow.slice(start, end === -1 ? undefined : end);
  const run = /^        run: (.*)$/m.exec(step);
  assert.ok(run, name);
  return run[1] === '|' ? step.slice(run.index + run[0].length + 1)
    .split('\n').filter(line => line.startsWith('          ')).map(line => line.slice(10)).join('\n') : run[1];
}
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-source-'));
const envFile = path.join(root, 'github-env');
const pin = `ci/colour-runtime/${platform}.env`;
const env = {...process.env, RUNTIME_PLATFORM: platform, GITHUB_ENV: envFile, RUNNER_TEMP: root};
const load = command('Load pinned colour runtime provenance');
const classify = command('Verify independent Darwin libraries and classify std input');
const run = (script, cwd = root) => spawnSync('bash', ['-c', script], {cwd, env, encoding: 'utf8'});
try {
  fs.mkdirSync(path.join(root, 'ci/colour-runtime'), {recursive: true});
  fs.copyFileSync(pin, path.join(root, pin));
  let result = run(load);
  assert.equal(result.status, 0, result.stderr);
  console.log(`SOURCE_PIN candidate ${platform} rc=${result.status}`);
  for (const line of fs.readFileSync(envFile, 'utf8').trim().split('\n')) {
    const split = line.indexOf('=');
    env[line.slice(0, split)] = line.slice(split + 1);
  }
  fs.unlinkSync(path.join(root, pin));
  result = run(load);
  assert.equal(result.status, 1);
  assert.equal(result.stderr.trim(), `COLOUR_RT_PLATFORM_PIN_MISSING: ${platform}`);
  console.log(`SOURCE_PIN cut ${platform} rc=${result.status} ${result.stderr.trim()}`);
  fs.copyFileSync(pin, path.join(root, pin));
  result = run(load);
  assert.equal(result.status, 0, result.stderr);
  console.log(`SOURCE_PIN restored ${platform} rc=${result.status}`);
  env.CJCJ_BOOTSTRAP_COLOUR_RT = path.resolve(artifact);
  result = run(classify, process.cwd());
  assert.notEqual(result.status, 0, 'incomplete std must not enter bootstrap');
  assert.match(result.stderr, new RegExp(`COLOUR_RT_STD_MISSING: ${platform}`));
  assert.equal(result.stdout.split('COLOUR_RT_LIBRARY_VERIFIED').length - 1, 3);
  console.log(result.stdout.trim());
  console.log(`SOURCE_CLASSIFICATION ${platform} rc=${result.status} COLOUR_RT_STD_MISSING`);
} finally { fs.rmSync(root, {recursive: true, force: true}); }
