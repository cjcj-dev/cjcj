import assert from 'node:assert/strict';
import {test, before, after} from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {inventory, expandInputs} from './g1-entry-branches.mjs';

const root = path.resolve(import.meta.dirname, '..');
const parent = process.env.G1_EVIDENCE || os.tmpdir();
// The production checker creates this private temporary name on every call.
// Preserve every other byte, including diagnostic order, values and counts.
const normalize = text => text.replaceAll(/cjcj-runtime-layout\.[A-Za-z0-9]{6}(?=\/CangjieRuntimeLayout\.h)/g,
  'cjcj-runtime-layout.<random>');
let work, runtime, llvm;
let completed = 0;
after(() => {
  if (completed === 2 && !process.env.G1_EVIDENCE) fs.rmSync(work, {recursive: true});
});
function run(command) {
  const result = spawnSync(command[0], command.slice(1), {
    cwd: root, encoding: 'utf8', timeout: 120000,
    // The entries commit private producer/consumer snapshots. Equal source and
    // metadata must yield equal identities, rather than stripping SHA output.
    env: {...process.env, GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z',
      GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'},
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return {rc: result.status, stdout: result.stdout, stderr: result.stderr};
}
before(async () => {
  fs.mkdirSync(parent, {recursive: true});
  work = fs.mkdtempSync(path.join(parent, 'g1-layout-'));
  console.log(`G1_EVIDENCE=${work}`);
  const inputs = path.join(work, 'inputs');
  fs.mkdirSync(inputs);
  const pin = file => Object.fromEntries(fs.readFileSync(path.join(root, 'ci', file), 'utf8')
    .split('\n').filter(line => line.includes('=')).map(line => line.split('=')));
  if (process.env.G1_LAYOUT_INPUTS) {
    const prepared = JSON.parse(fs.readFileSync(process.env.G1_LAYOUT_INPUTS, 'utf8'));
    assert.equal(prepared.runtimeRef, pin('runtime_pin.env').RUNTIME_REF);
    assert.equal(prepared.llvmRef, pin('llvm_pin.env').LLVM_SHA);
    for (const side of ['runtime', 'llvm']) {
      const identity = run(['git', '-C', prepared[side], 'rev-parse', 'HEAD']);
      assert.equal(identity.rc, 0);
      assert.equal(identity.stdout.trim(), prepared[`${side}Ref`]);
    }
    ({runtime, llvm} = prepared);
    fs.writeFileSync(path.join(work, 'inputs.json'), JSON.stringify(prepared, null, 2));
    return;
  }
  for (const file of ['pinned-remote.mjs', 'runtime.pack'])
    fs.copyFileSync(path.join(root, 'ci/fixtures/git', file), path.join(inputs, file));
  const fd = fs.openSync(path.join(inputs, 'llvm.pack'), 'wx');
  try {
    for (const part of ['00', '01', '02'])
      fs.writeFileSync(fd, fs.readFileSync(path.join(root, `ci/fixtures/git/llvm.pack.${part}`)));
  } finally { fs.closeSync(fd); }
  const {pinnedRemote} = await import(pathToFileURL(path.join(inputs, 'pinned-remote.mjs')));
  runtime = pinnedRemote(inputs, 'runtime', pin('runtime_pin.env').RUNTIME_REF);
  llvm = pinnedRemote(inputs, 'llvm', pin('llvm_pin.env').LLVM_SHA);
  fs.unlinkSync(path.join(inputs, 'runtime.pack'));
  fs.unlinkSync(path.join(inputs, 'llvm.pack'));
  fs.writeFileSync(path.join(work, 'inputs.json'), JSON.stringify({runtime, llvm,
    runtimeRef: pin('runtime_pin.env').RUNTIME_REF, llvmRef: pin('llvm_pin.env').LLVM_SHA}, null, 2));
});

// These are the two CLI commands in test-llvm-tuple.yml. Both arms consume
// complete real pinned Git objects; no compiler, SDK or LLVM build is run.
for (const name of ['test-runtime-layout', 'test-codegen-layout-sync']) {
  test(`G1 workflow layout entry parity: ${name}`, () => {
    const entry = `ci/${name}.mjs`;
    const directory = path.join(work, name);
    const oldRoot = path.join(directory, 'old');
    fs.mkdirSync(path.join(oldRoot, 'ci'), {recursive: true});
    for (const file of ['check-llvm-runtime-abi.mjs', 'generate-codegen-runtime-layout.py', 'runtime_pin.env', 'llvm_pin.env'])
      fs.copyFileSync(path.join(root, 'ci', file), path.join(oldRoot, 'ci', file));
    const generated = 'packages/codegen/src/RuntimeLayout.cj';
    fs.mkdirSync(path.dirname(path.join(oldRoot, generated)), {recursive: true});
    fs.copyFileSync(path.join(root, generated), path.join(oldRoot, generated));
    const old = path.join(oldRoot, 'ci', `${name}.bash.txt`);
    fs.copyFileSync(path.join(root, 'ci/fixtures/g1', `${name}.bash.txt`), old);
    const output = path.join(directory, 'output');
    const rows = inventory().filter(row => row.entry === entry && row.kind === 'required');
    const table = expandInputs(rows, {[entry]: {args: [output, runtime, llvm], env: {}}})
      .filter(row => row.outcome === 'set');
    assert.equal(table.length, 3);
    assert(table.every(row => row.status === 'READY'));
    assert(table.every(row => JSON.stringify(row.args) === JSON.stringify(table[0].args)));
    // Identical concrete inputs for all three set rows execute once, retaining
    // their AST anchors; three aliases must not inflate the execution count.
    const records = [];
    for (const [arm, command] of [['old', ['bash', old]],
      ['candidate', ['npx', '--yes', 'zx@8', path.join(root, entry)]]]) {
      const result = run([...command, ...table[0].args]);
      records.push({arm, rows: table, command, result});
      fs.writeFileSync(path.join(directory, 'results.json'), JSON.stringify(records, null, 2));
      assert.equal(result.rc, 0, JSON.stringify(records.at(-1)));
      const files = ['candidate.log', 'restored.log', 'candidate.sha256', 'restored.sha256',
        ...(name === 'test-runtime-layout' ? ['consumer-cut.log', 'producer-cut.log', 'producer-restored.log'] : ['cut.log', 'cut.sha256'])];
      records.at(-1).artifacts = Object.fromEntries(files.map(file => [file, fs.readFileSync(path.join(output, file), 'utf8')]));
      fs.writeFileSync(path.join(directory, 'results.json'), JSON.stringify(records, null, 2));
      fs.renameSync(output, path.join(directory, `${arm}-output`));
    }
    const observation = record => ({result: {...record.result,
      stdout: normalize(record.result.stdout), stderr: normalize(record.result.stderr)},
      artifacts: Object.fromEntries(Object.entries(record.artifacts).map(([file, text]) => [file, normalize(text)]))});
    assert.deepEqual(observation(records[1]), observation(records[0]));
    completed++;
    console.log(`ASSERT G1 workflow ${entry} old_rc=0 candidate_rc=0 artifacts_equal=1`);
  });
}
