import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {GUARDED_ROOTS, MAX_EXPANDED_BYTES, TARGET_WORKFLOW, expansionProblems, revisionReader, worktreeReader} from './workflow-expansion.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const read = worktreeReader(repo);
// The serial layout that hit "Maximum object size exceeded" (run 45347128058).
const SERIAL_LAYOUT = '26b09e3c8cbf092d69ee1c4161f671bf9fbe1af9';

// Exact static call graph of each guarded root: every reusable workflow is referenced once.
const EXPECTED_CALLS = {
  'release.yml': {'sdk-build.yml': 1, [TARGET_WORKFLOW]: 1, 'sdk-package.yml': 1},
  'prepare.yml': {'sdk-build.yml': 1, [TARGET_WORKFLOW]: 1},
  'sdk-build.yml': {[TARGET_WORKFLOW]: 1},
  'sdk-package.yml': {},
  'ci.yml': {[TARGET_WORKFLOW]: 1},
};

test('every guarded root holds at most one sdk-build-target.yml copy and expands below 400 KB', () => {
  assert.deepEqual([...GUARDED_ROOTS].sort(), Object.keys(EXPECTED_CALLS).sort());
  for (const name of GUARDED_ROOTS) {
    const result = expansionProblems(name, read);
    assert.deepEqual(result.problems, [], name);
    assert.deepEqual(result.copies, EXPECTED_CALLS[name], `${name} static call graph`);
    assert.ok(result.targetCopies <= 1, `${name}: ${result.targetCopies} copies`);
    assert.ok(result.bytes < MAX_EXPANDED_BYTES, `${name}: ${result.bytes} bytes`);
  }
  // The release root carries one copy of the 130 KB target workflow plus its own jobs.
  assert.ok(expansionProblems('release.yml', read).bytes < 300 * 1024);
});

const mutated = (name, change) => file => {
  const text = read(file);
  return file === name ? change(text) : text;
};

// Red cuts on the real files: each restores one way the old layout multiplied copies.
test('red cut: release.yml calling sdk-build.yml from 22 jobs again exceeds both limits', () => {
  const extra = Array.from({length: 21}, (_, i) =>
    `  source-p${i + 2}:\n    needs: plan\n    uses: ./.github/workflows/sdk-build.yml\n    with:\n      targets: linux-x64\n`).join('\n');
  const reader = mutated('release.yml', text => text.replace('  # The 15 release assets', `${extra}\n  # The 15 release assets`));
  const result = expansionProblems('release.yml', reader);
  assert.equal(result.copies['sdk-build.yml'], 22);
  assert.equal(result.targetCopies, 22);
  assert.ok(result.bytes > MAX_EXPANDED_BYTES);
  assert.match(result.problems.join('\n'), /22 static copies of sdk-build-target\.yml > 1/);
  assert.match(result.problems.join('\n'), /expanded JSON \d+ bytes >= 409600/);
});

test('red cut: a second sdk-build-target.yml call inside sdk-build.yml doubles the release copy', () => {
  const reader = mutated('sdk-build.yml', text => text.replace('\n  blocked:\n',
    '\n  prepare:\n    uses: ./.github/workflows/sdk-build-target.yml\n    with:\n      llvm_tools_only: true\n\n  blocked:\n'));
  for (const root of ['release.yml', 'prepare.yml', 'sdk-build.yml']) {
    const result = expansionProblems(root, reader);
    assert.equal(result.targetCopies, 2, root);
    assert.deepEqual(result.problems, [`${root}: 2 static copies of ${TARGET_WORKFLOW} > 1`]);
  }
});

test('red cut: sdk-package.yml regaining a nested call is caught in the package root and in release.yml', () => {
  const reader = mutated('sdk-package.yml', text => text.replace('\njobs:\n',
    '\njobs:\n  nested:\n    uses: ./.github/workflows/sdk-build-target.yml\n    with:\n      llvm_tools_only: true\n'));
  assert.deepEqual(expansionProblems('sdk-package.yml', reader).copies, {[TARGET_WORKFLOW]: 1});
  assert.deepEqual(expansionProblems('release.yml', reader).problems, [`release.yml: 2 static copies of ${TARGET_WORKFLOW} > 1`]);
});

// Control arm: the committed serial layout itself, when this checkout still has it.
const serialAvailable = spawnSync('git', ['-C', repo, 'cat-file', '-e', `${SERIAL_LAYOUT}^{commit}`]).status === 0;
test('control arm: the 26b09e3c serial layout fails the guard (44 copies, > 5.7 MB)', {skip: !serialAvailable && `${SERIAL_LAYOUT} not in this clone`}, () => {
  const result = expansionProblems('release.yml', revisionReader(repo, SERIAL_LAYOUT));
  assert.deepEqual(result.copies, {'sdk-build.yml': 22, [TARGET_WORKFLOW]: 44});
  assert.ok(result.bytes > 5.7e6, `${result.bytes} bytes`);
  assert.equal(result.problems.length, 2);
});
