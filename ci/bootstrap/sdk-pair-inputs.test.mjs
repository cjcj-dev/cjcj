import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {validateSourceInputs} from './sdk-inputs.mjs';
import {buildFlow} from './sdk-flow.mjs';

const gitEnv = {...process.env, GIT_AUTHOR_NAME: 'Zxilly', GIT_AUTHOR_EMAIL: 'zxilly@outlook.com',
  GIT_COMMITTER_NAME: 'Zxilly', GIT_COMMITTER_EMAIL: 'zxilly@outlook.com'};
function git(cwd, args) {
  const result = spawnSync('git', args, {cwd, env: gitEnv, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test('explicit inputs reject a macro source that is not this paired tree', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'sdk-pair-'));
  const repo = path.join(root, 'source');
  await fs.mkdir(path.join(repo, 'packages/macro/src'), {recursive: true});
  const expected = await fs.readFile(new URL('../../packages/macro/src/InvokeUtil.cj', import.meta.url));
  await fs.writeFile(path.join(repo, 'packages/macro/src/InvokeUtil.cj'), expected);
  git(repo, ['init', '-q']);
  git(repo, ['add', 'packages/macro/src/InvokeUtil.cj']);
  git(repo, ['commit', '-qm', 'test: paired macro source']);
  const commit = git(repo, ['rev-parse', 'HEAD']);
  const tree = git(repo, ['rev-parse', 'HEAD^{tree}']);
  const row = {repository: repo, commit, tree};
  await validateSourceInputs({llvm: row, runtime: row, ast: row, h1: row, compiler: row});
  await assert.rejects(validateSourceInputs({llvm: row, runtime: row, ast: row, h1: row,
    compiler: row, stdlib: {...row, tree: '0'.repeat(40)}}), /NATIVE_SOURCE_TREE stdlib/);
  await fs.writeFile(path.join(repo, 'packages/macro/src/InvokeUtil.cj'), expected + '\n');
  git(repo, ['add', 'packages/macro/src/InvokeUtil.cj']);
  git(repo, ['commit', '-qm', 'test: unpaired macro source']);
  const other = git(repo, ['rev-parse', 'HEAD']);
  const otherTree = git(repo, ['rev-parse', 'HEAD^{tree}']);
  await assert.rejects(validateSourceInputs({llvm: row, runtime: row, ast: row,
    h1: {...row, commit: other, tree: otherTree}, compiler: row}), /NATIVE_MACRO_SOURCE h1/);
});

test('resume without a recorded result is refused before the later command', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'sdk-resume-missing-'));
  const config = {work: path.join(root, 'work'), install: path.join(root, 'install'), repos: {}, finalStage: 'b',
    stages: [{id: 'a', commands: [{argv: [process.execPath, '-e', 'process.exit(99)']}]},
      {id: 'b', depends: ['a'], commands: [{argv: [process.execPath, '-e', 'process.exit(98)']}]}]};
  await assert.rejects(buildFlow(config, {from: 'b', through: 'b', packageOutput: false}), /WORK_INPUTS_MISSING/);
  assert.equal(await fs.stat(path.join(root, 'work', 'build-result.json')).then(() => true, () => false), false);
});
