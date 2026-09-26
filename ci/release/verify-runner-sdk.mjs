#!/usr/bin/env node
// Real-input acceptance: invoke the installed SDK probe, then disconnect its
// producer and exit-status consumer in private source copies. No SDK is changed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {RELEASE_REQUIREMENTS} from '../../build/lib/targets.mjs';

const [requirement, destination] = process.argv.slice(2);
assert.ok(Object.hasOwn(RELEASE_REQUIREMENTS, requirement), 'known SDK requirement');
assert.ok(destination, 'evidence directory required');
const root = path.resolve(import.meta.dirname, '../..');
const evidence = path.resolve(destination);
fs.mkdirSync(evidence, {recursive: true});
const original = fs.readFileSync(path.join(root, 'ci/release/platform-matrix.mjs'), 'utf8');
const producer = requirement === 'xcode-ios'
  ? "return {present: true, detail: found.join(', ')};"
  : 'return {present: true, detail: `${variable}=${root}`};';
const consumer = 'return result.present ? 0 : 1;';
assert.ok(original.includes(producer), 'producer cut must match the product source');
assert.ok(original.includes(consumer), 'consumer cut must match the product source');
const arms = {
  candidate: original,
  'cut-producer': original.replace(producer, producer.replace('present: true', 'present: false')),
  'cut-consumer': original.replace(consumer, 'return result.present ? 1 : 0;'),
  restored: original,
};
const results = [];
await Promise.all(Object.entries(arms).map(async ([arm, source], index) => {
  const tree = path.join(evidence, arm);
  fs.mkdirSync(path.join(tree, 'ci/release'), {recursive: true});
  fs.cpSync(path.join(root, 'build/lib'), path.join(tree, 'build/lib'), {recursive: true});
  const script = path.join(tree, 'ci/release/platform-matrix.mjs');
  fs.writeFileSync(script, source);
  const run = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, 'probe', '--requirement', requirement], {env: process.env});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
  fs.writeFileSync(path.join(tree, 'output.log'), `${run.stdout ?? ''}${run.stderr ?? ''}`);
  const expected = arm.startsWith('cut-') ? 1 : 0;
  const record = {arm, requirement, sha256: createHash('sha256').update(source).digest('hex'), rc: run.status, expected};
  // The target assertion is identical in every arm. The outer harness checks
  // that only the disconnected arms fail it; it never rewrites the invariant.
  try {
    assert.deepEqual({rc: run.status, present: run.stdout?.startsWith(`PRESENT ${requirement}:`)},
      {rc: 0, present: true}, 'installed SDK capability reaches a successful CLI result');
    record.targetAssertionRc = 0;
  } catch (error) {
    record.targetAssertionRc = 1;
    record.targetAssertionFailure = error.message;
  }
  results[index] = record;
  // Emit the actual product result before asserting, so an earlier setup error
  // cannot be mistaken for reaching this capability assertion.
  console.log(JSON.stringify({...record, stdout: run.stdout, stderr: run.stderr}));
  record.stdout = run.stdout;
}));
fs.writeFileSync(path.join(evidence, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
for (const {arm, rc, expected, targetAssertionRc, stdout} of results) {
  assert.equal(rc, expected, `${arm}: target capability exit status`);
  assert.equal(targetAssertionRc, expected, `${arm}: unchanged target assertion verdict`);
  assert.match(stdout, new RegExp(`^${arm === 'cut-producer' ? 'MISSING' : 'PRESENT'} ${requirement}:`), `${arm}: target capability result`);
}
assert.equal(results[0].sha256, results[3].sha256);
for (const cut of results.slice(1, 3)) assert.notEqual(cut.sha256, results[0].sha256);
console.log(`SDK_PROBE_CAUSAL_CHECK requirement=${requirement} arms=${results.length}`);
