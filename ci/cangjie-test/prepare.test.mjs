import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import test from 'node:test';

// Fixture commits exercise the real CLI; they do not qualify upstream inputs.
test('prepare consumes linked fixed worktrees and rejects a changed HEAD', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'cangjie-test-inputs-'));
  try {
    const repository = path.join(root, 'repository');
    await fs.mkdir(repository);
    const git = (...args) => execFileSync('git', ['-C', repository, ...args], {encoding: 'utf8'}).trim();
    git('init', '-q');
    await fs.writeFile(path.join(repository, 'test.cj'), 'main() {}\n');
    git('add', 'test.cj');
    git('-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture');
    const commit = git('rev-parse', 'HEAD');
    const pins = {};
    const worktrees = path.join(root, 'worktrees');
    await fs.mkdir(worktrees);
    for (const name of ['cangjie_test', 'cangjie_test_framework']) {
      pins[name] = commit;
      git('worktree', 'add', '-q', '--detach', path.join(worktrees, name), commit);
    }
    await fs.copyFile(new URL('./prepare.mjs', import.meta.url), path.join(root, 'prepare.mjs'));
    await fs.writeFile(path.join(root, 'inputs.json'), JSON.stringify(pins));
    const output = path.join(root, 'selection.json');
    const invoke = () => spawnSync(process.execPath, [path.join(root, 'prepare.mjs'), worktrees, output], {encoding: 'utf8'});
    const positive = invoke();
    assert.equal(positive.status, 0, positive.stderr);
    const selected = JSON.parse(await fs.readFile(output, 'utf8'));
    assert.deepEqual(selected, {pins, worktrees: Object.fromEntries(Object.keys(pins).map(name => [name, path.join(worktrees, name)]))});
    assert.deepEqual((await fs.readdir(root)).sort(), ['inputs.json', 'prepare.mjs', 'repository', 'selection.json', 'worktrees']);
    assert.equal(invoke().status, 2, 'existing output must not be overwritten');
    await fs.unlink(output);
    await fs.writeFile(path.join(repository, 'test.cj'), 'main() { println("changed") }\n');
    git('add', 'test.cj');
    git('-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'changed fixture');
    execFileSync('git', ['-C', path.join(worktrees, 'cangjie_test'), 'checkout', '-q', '--detach', git('rev-parse', 'HEAD')]);
    const negative = invoke();
    assert.equal(negative.status, 2);
    assert.match(negative.stderr, /input pin differs: cangjie_test/);
    await assert.rejects(fs.access(output));
    console.log('FIXED_WORKTREE_CLI positive=0 changed_head=2 upstream_suite=NOT_RUN');
  } finally {
    await fs.rm(root, {recursive: true, force: true});
  }
});
