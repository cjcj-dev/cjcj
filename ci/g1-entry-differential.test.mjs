import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {inventory, expandInputs} from './g1-entry-branches.mjs';

const root = path.resolve(import.meta.dirname, '..');
const rows = inventory();
const entries = [...new Set(rows.map(row => row.entry))];
function execute(command, cwd, env) {
  const result = spawnSync(command[0], command.slice(1), {cwd, env, encoding: 'utf8', timeout: 30000});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return {rc: result.status, stdout: result.stdout, stderr: result.stderr};
}

// These are missing/empty-argument branches only. Earlier arguments are real
// scratch paths, never executed or presented as qualified SDK/native inputs.
for (const entry of entries) test(`G1 actual entry required-argument parity: ${entry}`, () => {
  const parent = process.env.G1_EVIDENCE || os.tmpdir();
  fs.mkdirSync(parent, {recursive: true});
  const work = fs.mkdtempSync(path.join(parent, 'g1-arguments-'));
  const records = [];
  let completed = false;
  try {
    const oldRoot = path.join(work, 'old');
    fs.mkdirSync(path.join(oldRoot, 'ci'), {recursive: true});
    const name = path.basename(entry, '.mjs');
    const old = path.join(oldRoot, 'ci', `${name}.bash.txt`);
    fs.copyFileSync(path.join(root, 'ci/fixtures/g1', `${name}.bash.txt`), old);
    for (const pin of ['llvm_pin.env', 'runtime_pin.env'])
      fs.copyFileSync(path.join(root, 'ci', pin), path.join(oldRoot, 'ci', pin));
    const required = rows.filter(row => row.entry === entry && row.kind === 'required' && !row.scope.length);
    const count = Math.max(...required.map(row => row.position));
    const args = Array.from({length: count}, (_, i) => path.join(work, `input-${i + 1}`));
    for (const file of args) fs.writeFileSync(file, 'argument guard input; never execute\n');
    const table = expandInputs(required, {[entry]: {args, env: {}}})
      .filter(row => ['unset', 'empty'].includes(row.outcome));
    assert.equal(table.length, required.length * 2);
    for (const row of table) {
      assert.equal(row.status, 'READY');
      // Freeze shell diagnostic language explicitly for byte-for-byte parity.
      // Ambient gettext wording is checked separately below, not rewritten.
      const env = {...process.env, LC_ALL: 'C'};
      const before = execute(['bash', old, ...row.args], root, env);
      const after = execute(['npx', '--yes', 'zx@8', path.join(root, entry), ...row.args], root, env);
      records.push({row, locale: 'C', before, after});
      fs.writeFileSync(path.join(work, 'results.json'), JSON.stringify(records, null, 2));
      const normalize = result => ({...result, stderr: result.stderr
        .replaceAll(old, '<entry>').replaceAll(path.join(root, entry), '<entry>')
        .replaceAll(`${name}.sh`, '<name>').replaceAll(`${name}.mjs`, '<name>')});
      assert.equal(before.rc, 1, JSON.stringify({row, before}));
      assert.deepEqual(normalize(after), normalize(before), JSON.stringify({row, before, after}));
      console.log(`ASSERT G1 required entry=${entry} line=${row.line} outcome=${row.outcome} old_rc=${before.rc} candidate_rc=${after.rc}`);
    }
    const first = table[0];
    const branch = required.find(row => row.start === first.start);
    const label = branch.fallback.map(node => node.text).join('');
    const ambient = [['bash', old], ['npx', '--yes', 'zx@8', path.join(root, entry)]]
      .map(command => execute([...command, ...first.args], root, process.env));
    records.push({row: first, locale: 'ambient', before: ambient[0], after: ambient[1]});
    fs.writeFileSync(path.join(work, 'results.json'), JSON.stringify(records, null, 2));
    for (const [index, result] of ambient.entries()) {
      assert.equal(result.rc, 1);
      assert.equal(result.stdout, '');
      assert.equal(result.stderr.split('\n').length, 2);
      assert(result.stderr.startsWith(`${index === 0 ? old : path.join(root, entry)}: `));
      const normalized = result.stderr.replaceAll(`${name}.sh`, '<name>').replaceAll(`${name}.mjs`, '<name>');
      const message = label.replaceAll(`${name}.sh`, '<name>');
      assert(normalized.endsWith(` ${first.line}: ${branch.position}: ${message}\n`), result.stderr);
    }
    console.log(`ASSERT G1 ambient semantic diagnostic entry=${entry} line=${first.line} position=${branch.position}`);
    completed = true;
  } finally {
    if (completed && !process.env.G1_EVIDENCE) fs.rmSync(work, {recursive: true, force: true});
    else console.log(`G1_EVIDENCE=${work}`);
  }
});
