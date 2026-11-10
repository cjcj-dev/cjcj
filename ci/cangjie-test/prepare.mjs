#!/usr/bin/env zx
// Consume existing fixed worktrees. Source transfer belongs to cjops repo sync.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

export async function prepare(root) {
  const pins = JSON.parse(await fs.readFile(new URL('./inputs.json', import.meta.url), 'utf8'));
  const worktrees = {};
  for (const [name, commit] of Object.entries(pins)) {
    const directory = await fs.realpath(path.join(root, name));
    const git = (...args) => execFileSync('git', ['-C', directory, ...args], {encoding: 'utf8'}).trim();
    if (await fs.realpath(git('rev-parse', '--show-toplevel')) !== directory)
      throw Error('expected a worktree root: ' + directory);
    if (git('rev-parse', 'HEAD') !== commit)
      throw Error('input pin differs: ' + name + ' expected ' + commit);
    worktrees[name] = directory;
  }
  return {pins, worktrees};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length < 3 || process.argv.length > 4)
      throw Error('Usage: zx ci/cangjie-test/prepare.mjs WORKTREES [NEW_JSON]');
    const text = JSON.stringify(await prepare(path.resolve(process.argv[2])), null, 2) + '\n';
    if (process.argv[3]) await fs.writeFile(process.argv[3], text, {flag: 'wx'});
    else process.stdout.write(text);
  } catch (error) {
    console.error('CANGJIE_TEST_INPUTS: ' + error.message);
    process.exitCode = 2;
  }
}
