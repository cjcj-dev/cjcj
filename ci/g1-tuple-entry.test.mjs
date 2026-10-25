import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {inventory, expandInputs} from './g1-entry-branches.mjs';
import {readSourcePins} from './native-llvm-inputs.mjs';
const root = path.resolve(import.meta.dirname, '..');
const entry = 'ci/test-llvm-tuple-layout.mjs';
function run(argv, cwd = root) {
  const result = spawnSync(argv[0], argv.slice(1), {cwd, encoding: 'utf8', timeout: 60000});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return {rc: result.status, stdout: result.stdout, stderr: result.stderr};
}

test('G1 registered tuple entry consumes default and explicit artifacts through AST inputs', () => {
  const parent = process.env.G1_EVIDENCE || os.tmpdir();
  fs.mkdirSync(parent, {recursive: true});
  const work = fs.mkdtempSync(path.join(parent, 'g1-tuple-'));
  const oldRoot = path.join(work, 'old');
  let complete = false;
  try {
    const registry = run([process.execPath, 'ci/run-registered-tests.mjs', 'scripts', path.join(work, 'registered'), entry]);
    fs.writeFileSync(path.join(work, 'registry.json'), JSON.stringify(registry, null, 2));
    assert.equal(registry.rc, 0, registry.stderr + registry.stdout);
    const manifest = JSON.parse(fs.readFileSync(path.join(work, 'registered/results.json'), 'utf8'));
    assert.equal(manifest.group, 'scripts');
    assert.equal(manifest.results.length, 1);
    const [result] = manifest.results;
    assert.equal(result.file, entry);
    assert.equal(result.rc, 0);
    assert.equal(result.command[3], entry);
    console.log('ASSERT G1 registered tuple target reached rc=0');
    const output = path.join(path.dirname(result.log), 'output');
    const identities = readSourcePins(root).llvm;
    const tuple = path.join(output, 'depot', identities.LLVM_SHA, identities.CANGJIE_COMPILER_SHA);
    assert.equal(fs.readFileSync(path.join(tuple, 'SHA256SUMS'), 'utf8').trim().split('\n').length, 10);
    const head = run(['git', 'rev-parse', 'HEAD']);
    assert.equal(head.rc, 0);
    const checkout = run(['git', 'worktree', 'add', '--detach', oldRoot, head.stdout.trim()]);
    assert.equal(checkout.rc, 0, checkout.stderr);
    // The retired Bash entry expects the old data name; feed the same selected compiler identity.
    fs.appendFileSync(path.join(oldRoot, 'ci/llvm_pin.env'), `CANGJIE_COMPILER_SHA=${identities.CANGJIE_COMPILER_SHA}\n`);
    const oldEntry = path.join(oldRoot, 'ci/tuple-baseline.bash.txt');
    fs.copyFileSync(path.join(root, 'ci/fixtures/g1/test-llvm-tuple-layout.bash.txt'), oldEntry);
    const rows = inventory().filter(row => row.entry === entry && row.kind === 'parameter' && row.position === 2);
    assert.equal(rows.length, 1);
    const table = expandInputs(rows, {[entry]: {args: [path.join(work, 'output'), tuple], env: {}}});
    const records = [];
    for (const row of table) {
      assert.equal(row.status, 'READY');
      const observations = [];
      for (const command of [['bash', oldEntry], ['npx', '--yes', 'zx@8', path.join(root, entry)]]) {
        const result = run([...command, ...row.args]);
        const logs = {};
        for (const file of ['green.log', 'cut.log', 'restored.log', 'static.saved']) {
          const full = path.join(work, 'output', file);
          logs[file] = fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : null;
        }
        observations.push({result, logs});
        records.push({row, command, result, logs});
        fs.writeFileSync(path.join(work, 'differential.json'), JSON.stringify(records, null, 2));
        assert.equal(result.rc, 0, JSON.stringify(records.at(-1)));
        fs.rmSync(path.join(work, 'output'), {recursive: true});
      }
      assert.deepEqual(observations[1], observations[0], JSON.stringify({row, observations}));
      console.log(`ASSERT G1 tuple outcome=${row.outcome} old_rc=0 candidate_rc=0 artifacts_equal=1`);
    }
    complete = true;
  } finally {
    if (complete) {
      assert.equal(run(['git', 'worktree', 'remove', '--force', oldRoot]).rc, 0);
      if (!process.env.G1_EVIDENCE) fs.rmSync(work, {recursive: true});
    }
    if (!complete || process.env.G1_EVIDENCE) console.log(`G1_EVIDENCE=${work}`);
  }
});
