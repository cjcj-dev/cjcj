import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {zxCommand} from '../../../../../ci/test-zx.mjs';

const entry = fileURLToPath(new URL('../steps/verify-source-pins.mjs', import.meta.url));
const pins = [
  ['cangjie_compiler', 'COMPILER_SRC_URL', 'CANGJIE_COMPILER_SHA'],
  ['cangjie_runtime', 'RUNTIME_SRC_URL', 'CJCJ_NATIVE_RUNTIME_REF'],
  ['cjcj-tools', 'TOOLS_SRC_URL', 'TOOLS_REF'],
  ['cangjie_stdx', 'STDX_SRC_URL', 'STDX_REF'],
];

test('Verify source revisions reads the four selected worktrees', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'verify-source-pins-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  // On POSIX, backslashes are literal filename bytes; on Windows they are separators.
  const workspace = path.join(root, 'a\\cjcj\\cjcj workspace');
  const env = {...process.env, CANGJIE_WORKSPACE: workspace};
  const expectedArgs = [];
  for (const [directory, urlKey, refKey] of pins) {
    const source = path.join(workspace, directory);
    fs.mkdirSync(source, {recursive: true});
    const git = (...args) => execFileSync('git', ['-C', source, ...args], {encoding: 'utf8'}).trim();
    git('init', '-q');
    env[urlKey] = 'https://example.org/' + directory + '.git';
    git('remote', 'add', 'origin', env[urlKey]);
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.org', 'commit', '--no-gpg-sign', '--allow-empty', '-qm', directory);
    env[refKey] = git('rev-parse', 'HEAD');
    expectedArgs.push(['-C', source, 'config', '--get', 'remote.origin.url'], ['-C', source, 'rev-parse', 'HEAD']);
  }

  const shellLog = path.join(root, 'shell.log');
  // A zx shell writes this marker even on hosts where bash happens to quote the path correctly.
  const [node, ...args] = zxCommand(['--prefix', 'echo git-shell >> "$PIN_SHELL_LOG";', entry]);
  const run = overrides => spawnSync(node, args, {encoding: 'utf8', env: {...env, PIN_SHELL_LOG: shellLog, ...overrides}});
  await t.test('Git receives each complete -C argument without a shell', () => {
    const trace = path.join(root, 'git-trace.jsonl');
    const result = run({GIT_TRACE2_EVENT: trace});
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /SOURCE_PINS_PASS checked=4/);
    const starts = fs.readFileSync(trace, 'utf8').trim().split('\n').map(JSON.parse).filter(row => row.event === 'start');
    assert.deepEqual(starts.map(row => row.argv.slice(1)), expectedArgs);
    assert.equal(fs.existsSync(shellLog), false, 'Git pin reads passed through the zx shell');
  });
  await t.test('the selected checkout URL remains exact', () => {
    const result = run({RUNTIME_SRC_URL: env.RUNTIME_SRC_URL.slice(0, -4)});
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /runtime URL mismatch:/);
  });
  await t.test('a different commit is rejected', () => {
    const result = run({TOOLS_REF: 'f'.repeat(40)});
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /tools ref mismatch:/);
  });
});
