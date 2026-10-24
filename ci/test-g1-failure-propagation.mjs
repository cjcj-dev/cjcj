#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {repo, cliArgs, pin} from './entry-common.mjs';
const source = repo;
assert.equal(cliArgs.length, 2, 'usage: test-g1-failure-propagation.mjs NEW_EVIDENCE INPUTS_JSON');
const evidence = path.resolve(cliArgs[0]);
fs.mkdirSync(evidence);
const {inventory, expandInputs} = await import(path.join(source, 'ci/g1-entry-branches.mjs'));
const rows = inventory();
const prepared = JSON.parse(fs.readFileSync(cliArgs[1]));
for (const [name, expected] of [['runtime', pin(path.join(repo, 'ci/runtime_pin.env')).RUNTIME_REF],
  ['llvm', pin(path.join(repo, 'ci/llvm_pin.env')).LLVM_SHA],
  ['chainRuntime', '4909b2dec1af7f522133c6401e2ce960b0ef511d']]) {
  const actual = spawnSync('git', ['-C', prepared[name], 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(actual.status, 0, actual.stderr);
  assert.equal(actual.stdout.trim(), expected);
}
const empty = path.join(evidence, 'empty.git');
assert.equal(spawnSync('git', ['init', '--bare', '--quiet', empty]).status, 0);
const tuple = prepared.tuple;
const qualified = spawnSync('sha256sum', ['--strict', '-c', 'SHA256SUMS'], {cwd: tuple, encoding: 'utf8'});
assert.equal(qualified.status, 0, qualified.stdout + qualified.stderr);
fs.writeFileSync(path.join(evidence, 'tuple-input.log'), qualified.stdout + qualified.stderr);
const malformed = path.join(evidence, 'malformed-tuple');
fs.cpSync(tuple, malformed, {recursive: true});
fs.appendFileSync(path.join(malformed, 'lib/STATIC_LLVM.txt'), '\ncontrolled invalid input\n');
const cases = [
  {name: 'pipeline-producer-failure', entry: 'test-runtime-layout', inputs: [empty, prepared.llvm],
    artifacts: ['runtime.tar', 'llvm/llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h']},
  {name: 'header-redirection-failure', entry: 'test-runtime-layout', inputs: [prepared.runtime, empty],
    artifacts: ['runtime.tar', 'llvm/llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h']},
  {name: 'layout-check-failure', entry: 'test-codegen-layout-sync', inputs: [empty, prepared.llvm],
    artifacts: ['candidate.log', 'candidate.sha256']},
  {name: 'tuple-check-failure', entry: 'test-llvm-tuple-layout', inputs: [malformed],
    artifacts: ['green.log', 'static.saved']},
  {name: 'checked-copy-failure', entry: 'test-llvm-tuple-layout', inputs: [path.join(evidence, 'missing-tuple')],
    artifacts: ['green.log']},
  {name: 'capture-ref-failure', entry: 'test-llvm-runtime-chain', inputs: [prepared.chainRuntime, empty], artifacts: []},
  {name: 'checked-fetch-log-failure', entry: 'test-llvm-runtime-chain', inputs: [empty, prepared.chainOther],
    artifacts: ['fetch.log', 'build.log']},
];
const output = path.join(evidence, 'output');
const records = [];
const links = [];
try {
  for (const sample of cases) {
    const entry = `ci/${sample.entry}.mjs`;
    const old = path.join(source, 'ci', `.g1-old-failure-${sample.entry}.bash.txt`);
    if (!links.includes(old)) {
      fs.symlinkSync(`fixtures/g1/${sample.entry}.bash.txt`, old);
      links.push(old);
    }
    const expanded = expandInputs(rows.filter(row => row.entry === entry && row.kind === 'required'),
      {[entry]: {args: [output, ...sample.inputs], env: {}}}).filter(row => row.outcome === 'set');
    assert(expanded.length && expanded.every(row => row.status === 'READY'));
    for (const arm of ['old', 'candidate']) {
      const command = arm === 'old' ? ['bash', old, ...expanded[0].args]
        : ['npx', '--yes', 'zx@8', path.join(source, entry), ...expanded[0].args];
      const result = spawnSync(command[0], command.slice(1), {cwd: source, encoding: 'utf8', timeout: 60000,
        env: {...process.env, LC_ALL: 'C'}});
      const record = {name: sample.name, arm, command, inputs: expanded,
        result: {rc: result.status, signal: result.signal, error: result.error?.message,
          stdout: result.stdout, stderr: result.stderr},
        artifacts: Object.fromEntries(sample.artifacts.map(name => [name,
          fs.existsSync(path.join(output, name)) ? fs.readFileSync(path.join(output, name), 'utf8') : null]))};
      records.push(record);
      fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(records, null, 2));
      assert.ifError(result.error);
      assert.equal(result.signal, null);
      assert.notEqual(result.status, 0, 'invalid input must be rejected by the real entry');
      if (sample.name === 'tuple-check-failure') {
        assert.match(record.artifacts['green.log'], /STATIC_LLVM.txt: FAILED/);
        assert.equal(record.artifacts['green.log'].split('\n').filter(line => line.endsWith(': OK')).length, 9);
      }
      if (sample.name === 'checked-copy-failure') {
        assert.equal(result.status, 1);
        assert.match(result.stderr, /cannot stat/);
        assert(result.stderr.includes(sample.inputs[0]));
      }
      if (sample.name === 'checked-fetch-log-failure') {
        assert.equal(result.status, 128);
        assert.match(record.artifacts['fetch.log'], /(?:not our ref|couldn't find remote ref) 4909b2dec1af7f522133c6401e2ce960b0ef511d/);
        assert.equal(record.artifacts['build.log'], null);
      }
      fs.renameSync(output, path.join(evidence, `${sample.name}-${arm}`));
      console.log(`ERROR_TARGET_REACHED case=${sample.name} arm=${arm} rc=${result.status}`);
    }
  }
  const differences = [];
  for (const sample of cases) {
    const [before, after] = records.filter(record => record.name === sample.name);
    try { assert.deepEqual({result: after.result, artifacts: after.artifacts},
      {result: before.result, artifacts: before.artifacts}); }
    catch (error) {differences.push({name: sample.name, message: error.message});}
  }
  fs.writeFileSync(path.join(evidence, 'differences.json'), JSON.stringify(differences, null, 2));
  assert.deepEqual(differences, [], 'actual entry failure propagation and redirection artifacts must agree');
  console.log(`FAILURE_PARITY_PASS N=${cases.length}`);
} finally {
  for (const file of links) fs.unlinkSync(file);
}
