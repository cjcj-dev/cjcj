import assert from 'node:assert/strict';
import {test, before, after} from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

import {readSourcePins} from './native-llvm-inputs.mjs';
const root = path.resolve(import.meta.dirname, '..');
const parent = process.env.G1_EVIDENCE || os.tmpdir();
const names = ['test-llvm-tuple-layout', 'test-runtime-layout', 'test-codegen-layout-sync'];
const generated = 'llvm/llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h';
const normalize = text => text.replaceAll(/cjcj-runtime-layout\.[A-Za-z0-9]{6}(?=\/CangjieRuntimeLayout\.h)/g,
  'cjcj-runtime-layout.<random>');
const records = [], links = [];
let evidence, slot, callers, inputs, tuples;
const environment = {...process.env, LC_ALL: 'C', GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z',
  GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'};
function execute(command, cwd) {
  const result = spawnSync(command[0], command.slice(1), {cwd, env: environment,
    encoding: 'utf8', timeout: 120000});
  return {rc: result.status, signal: result.signal, error: result.error?.message,
    stdout: result.stdout, stderr: result.stderr};
}
function checked(command, cwd = root) {
  const result = execute(command, cwd);
  assert.equal(result.error, undefined, JSON.stringify(result));
  assert.equal(result.signal, null);
  assert.equal(result.rc, 0, JSON.stringify({command, cwd, result}));
  return result.stdout;
}
function link(target, name) { fs.symlinkSync(target, name); links.push(name); }
function pin(file) {
  return Object.fromEntries(fs.readFileSync(path.join(root, 'ci', file), 'utf8')
    .split('\n').filter(line => line.includes('=')).map(line => line.split('=')));
}
before(async () => {
  fs.mkdirSync(parent, {recursive: true});
  evidence = fs.mkdtempSync(path.join(parent, 'g1-cwd-'));
  console.log(`G1_CWD_EVIDENCE=${evidence}`);
  slot = `.g1 cwd ${path.basename(evidence)}`;
  callers = ['caller one', 'caller two'].map(name => path.join(evidence, name));
  for (const caller of callers) fs.mkdirSync(caller);
  inputs = path.join(evidence, 'inputs');
  fs.mkdirSync(inputs);
  const expected = {runtimeRef: pin('runtime_pin.env').RUNTIME_REF, llvmRef: pin('llvm_pin.env').LLVM_SHA};
  let prepared;
  if (process.env.G1_LAYOUT_INPUTS) prepared = JSON.parse(fs.readFileSync(process.env.G1_LAYOUT_INPUTS));
  else {
    for (const file of ['pinned-remote.mjs', 'runtime.pack'])
      fs.copyFileSync(path.join(root, 'ci/fixtures/git', file), path.join(inputs, file));
    const fd = fs.openSync(path.join(inputs, 'llvm.pack'), 'wx');
    try { for (const part of ['00', '01', '02']) fs.writeFileSync(fd,
      fs.readFileSync(path.join(root, `ci/fixtures/git/llvm.pack.${part}`))); }
    finally { fs.closeSync(fd); }
    const {pinnedRemote} = await import(pathToFileURL(path.join(inputs, 'pinned-remote.mjs')));
    prepared = {...expected, runtime: pinnedRemote(inputs, 'runtime', expected.runtimeRef),
      llvm: pinnedRemote(inputs, 'llvm', expected.llvmRef)};
    fs.unlinkSync(path.join(inputs, 'runtime.pack'));
    fs.unlinkSync(path.join(inputs, 'llvm.pack'));
  }
  for (const side of ['runtime', 'llvm']) {
    assert.equal(prepared[`${side}Ref`], expected[`${side}Ref`]);
    assert.equal(checked(['git', '-C', prepared[side], 'rev-parse', 'HEAD']).trim(), expected[`${side}Ref`]);
    link(prepared[side], path.join(inputs, side));
  }
  fs.writeFileSync(path.join(evidence, 'inputs.json'), JSON.stringify(prepared, null, 2));
  checked(['git', 'init', '--bare', '--quiet', path.join(inputs, 'empty.git')]);
  const fixture = path.join(evidence, 'tuple producer');
  checked(['npx', '--yes', 'zx@8', path.join(root, 'ci/test-llvm-tuple-layout.mjs'), fixture]);
  const llvmPin = readSourcePins(root).llvm;
  const origin = path.join(fixture, 'depot', llvmPin.LLVM_SHA, llvmPin.CANGJIE_COMPILER_SHA);
  tuples = ['caller-one', 'caller-two', 'repo-decoy'].map(identity => {
    const directory = path.join(evidence, identity);
    fs.cpSync(origin, directory, {recursive: true});
    // Three valid ten-payload tuples, with observably different consumed bytes.
    fs.appendFileSync(path.join(directory, 'lib/STATIC_LLVM.txt'), `R1_INPUT=${identity}\n`);
    const files = fs.readFileSync(path.join(directory, 'SHA256SUMS'), 'utf8').trimEnd()
      .split('\n').map(line => line.slice(66));
    assert.equal(files.length, 10);
    fs.writeFileSync(path.join(directory, 'SHA256SUMS'), checked(['sha256sum', '--', ...files], directory));
    checked(['sha256sum', '--strict', '-c', 'SHA256SUMS'], directory);
    return directory;
  });
  for (const [index, caller] of [...callers, root].entries()) {
    const directory = path.join(evidence, `aliases-${index}`);
    fs.mkdirSync(directory);
    link(tuples[index], path.join(directory, 'tuple'));
    // The repo has the same relative names but cannot provide the pinned source
    // objects. A caller-relative layout input must never resolve to these.
    for (const side of ['runtime', 'llvm', 'empty.git'])
      link(path.join(inputs, index === 2 ? 'empty.git' : side), path.join(directory, side));
    link(directory, path.join(caller, slot));
  }
  for (const name of names) link(`fixtures/g1/${name}.bash.txt`, path.join(root, 'ci', `.r1-${name}.bash.txt`));
});
after(() => {
  // Only remove links created by this test, never the supplied inputs or evidence.
  for (const file of links.reverse()) fs.unlinkSync(file);
});

function parity(name, sample, cwd, inputArgs, {relativeWork = false, rc = 0, marker} = {}) {
  const work = relativeWork ? 'output space' : path.join(cwd, 'output space');
  const output = path.resolve(cwd, work);
  const observations = [];
  for (const arm of ['old', 'candidate']) {
    const command = arm === 'old' ? ['bash', path.join(root, 'ci', `.r1-${name}.bash.txt`)]
      : ['npx', '--yes', 'zx@8', path.join(root, 'ci', `${name}.mjs`)];
    command.push(work, ...inputArgs);
    const result = execute(command, cwd);
    const artifacts = {};
    for (const file of ['green.log', 'cut.log', 'restored.log', 'static.saved', 'candidate.log',
      'candidate.sha256', 'restored.sha256', 'cut.sha256', 'consumer-cut.log', 'producer-cut.log',
      'producer-restored.log', generated]) {
      const full = path.join(output, file);
      artifacts[file] = fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : null;
    }
    const record = {name, sample, arm, command, cwd, result, artifacts};
    records.push(record);
    fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(records, null, 2));
    // Archive before asserting so a failed selection leaves its real output.
    if (fs.existsSync(output)) fs.renameSync(output, path.join(evidence, `${sample}-${arm}`));
    assert.equal(result.error, undefined, JSON.stringify(record));
    assert.equal(result.signal, null, JSON.stringify(record));
    assert.equal(result.rc, rc, JSON.stringify(record));
    if (marker !== undefined) {
      console.log(`R1_CALLER_TUPLE_SELECTION_REACHED sample=${sample} arm=${arm}`);
      assert.equal(artifacts['static.saved'], marker, 'R1_CALLER_TUPLE_SELECTION');
      assert.equal((artifacts['cut.log'].match(/: OK$/gm) || []).length, 9);
      assert.match(artifacts['cut.log'], /^\.\/lib\/STATIC_LLVM.txt: FAILED/gm);
      assert.equal(artifacts['restored.log'], artifacts['green.log']);
    }
    observations.push({result: {...result, stdout: normalize(result.stdout), stderr: normalize(result.stderr)},
      artifacts: Object.fromEntries(Object.entries(artifacts).map(([file, text]) => [file, text === null ? null : normalize(text)]))});
  }
  assert.deepEqual(observations[1], observations[0], `R1_PARITY ${sample}`);
  console.log(`R1_PARITY_PASS sample=${sample} old_rc=${rc} candidate_rc=${rc}`);
}

test('G1 cwd relative tuple selects caller bytes, including same names in different directories', () => {
  for (let index = 0; index < callers.length; index++) parity('test-llvm-tuple-layout', `relative-tuple-${index}`,
    callers[index], [`./${slot}/tuple`], {relativeWork: index === 1,
      marker: fs.readFileSync(path.join(tuples[index], 'lib/STATIC_LLVM.txt'), 'utf8')});
});
test('G1 cwd absolute tuple control keeps the explicit target', () => {
  parity('test-llvm-tuple-layout', 'absolute-tuple-control', callers[1], [tuples[0]],
    {marker: fs.readFileSync(path.join(tuples[0], 'lib/STATIC_LLVM.txt'), 'utf8')});
});
for (const name of ['test-runtime-layout', 'test-codegen-layout-sync']) test(`G1 cwd layout parity ${name}`, () => {
  for (const [sample, args, relativeWork] of [
    ['relative', [`./${slot}/runtime`, `./${slot}/llvm`], true],
    ['absolute', [path.join(inputs, 'runtime'), path.join(inputs, 'llvm')], false],
    ['mixed-runtime', [`./${slot}/runtime`, path.join(inputs, 'llvm')], false],
    ['mixed-llvm', [path.join(inputs, 'runtime'), `./${slot}/llvm`], false],
  ]) parity(name, `${name}-${sample}`, callers[0], args, {relativeWork});
});
test('G1 cwd relative input errors preserve checked, pipeline, redirect and checker results', () => {
  parity('test-llvm-tuple-layout', 'missing-copy', callers[0], [`./${slot}/missing tuple`], {rc: 1});
  parity('test-runtime-layout', 'archive-failure', callers[0], [`./${slot}/empty.git`, `./${slot}/llvm`], {rc: 2});
  parity('test-runtime-layout', 'header-failure', callers[0], [`./${slot}/runtime`, `./${slot}/empty.git`], {rc: 128});
  parity('test-codegen-layout-sync', 'checker-failure', callers[0], [`./${slot}/empty.git`, `./${slot}/llvm`], {rc: 2});
});
