import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '..');
const cli = path.join(repo, 'ci/release-gates.mjs');
const head = spawnSync('git', ['-C', repo, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).stdout.trim();
const suites = ['Conformance', 'HLT', 'LLT'];
const digest = digit => digit.repeat(64);
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g11-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const files = {};
  const manifest = {schema: 1, cjcj_head_sha: head, allowances: []};
  for (const [index, arm] of ['official', 'selfhost'].entries()) {
    manifest[arm] = {directory: arm, compiler_sha256: digest(String(index + 1)),
      runtime_sha256: {'runtime.so': digest(String(index + 3))},
      started_at: '2026-09-29T12:00:00Z', finished_at: '2026-09-29T13:00:00Z'};
    files[`${arm}/identity.json`] = {compiler_sha256: manifest[arm].compiler_sha256,
      runtime_sha256: manifest[arm].runtime_sha256, pins: {cangjie_test: 'a'.repeat(40)},
      jobs: 48, compiler_jobs: 1, recipe_sha256: digest('a'), source_manifest_sha256: digest('b'),
      adapter_hashes: {maple: digest('c')}, adapter_source_sha256: {'adapt.py': digest('d')},
      smoke_sha256: digest('e'), uptime_before: '12:00 load average: 1, 1, 1',
      uptime_after: '13:00 load average: 1, 1, 1'};
    for (const suite of suites) {
      files[`${arm}/${suite}/cases.json`] = [
        {name: 'success', category: 'pass', timeout_failure: false},
        {name: 'baseline-failure', category: 'fail', timeout_failure: false}];
      files[`${arm}/${suite}/summary.json`] = {status: 'ran', rc: 1, complete: true, total: 2,
        counts: {pass: 1, fail: 1, skip: 0, not_run: 0}};
    }
  }
  manifest.allowances = suites.map(suite => ({suite, name: 'baseline-failure', reason: 'Observed official fixture failure'}));
  files['G11.json'] = manifest;
  return {root, files};
}
async function runFixture(f, mode = 'G11') {
  for (const [relative, contents] of Object.entries(f.files)) {
    const file = path.join(f.root, relative);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, JSON.stringify(contents));
  }
  const result = spawnSync(process.execPath, [cli, mode, '--repo', repo, '--evidence', f.root, '--json'], {encoding: 'utf8'});
  assert.equal(result.error, undefined);
  const output = JSON.parse(result.stdout);
  return {rc: result.status, row: mode === 'all' ? output.find(row => row.gate === 'G11') : output};
}
function changeCase(f, suite, category, timeout = false) {
  const key = `selfhost/${suite}`;
  f.files[`${key}/cases.json`][0] = {name: 'success', category, timeout_failure: timeout};
  const summary = f.files[`${key}/summary.json`];
  summary.counts.pass--;
  summary.counts[category]++;
}

test('G11 actual CLI consumes all three suites and Q54-C official reasons', async t => {
  const f = await fixture(t);
  const {rc, row} = await runFixture(f);
  assert.equal(rc, 0);
  assert.equal(row.status, 'MET');
  assert.match(row.value, /selfhost_only_failures=0; official_allowances=3/);
  assert.doesNotMatch(JSON.stringify(row), /29060/);
});
for (const suite of suites) test(`G11 ${suite} selfhost-only failure reaches target verdict`, async t => {
  const f = await fixture(t);
  changeCase(f, suite, 'fail');
  const {rc, row} = await runFixture(f);
  assert.equal(row.status, 'NOT_MET', JSON.stringify(row));
  assert.equal(rc, 1);
  assert.deepEqual(row.failures, [{suite, name: 'success'}]);
});
test('G11 timeout failure cannot disappear through comparator exclusion', async t => {
  const f = await fixture(t);
  changeCase(f, 'LLT', 'fail', true);
  const {rc, row} = await runFixture(f);
  assert.equal(row.status, 'NOT_MET');
  assert.equal(rc, 1);
  assert.deepEqual(row.failures, [{suite: 'LLT', name: 'success'}]);
});
const invalid = {
  'missing suite': f => {delete f.files['selfhost/LLT/cases.json'];},
  'empty suite': f => {f.files['selfhost/LLT/cases.json'] = [];},
  'different recipe': f => {f.files['selfhost/identity.json'].jobs = 24;},
  'different case set': f => {f.files['selfhost/HLT/cases.json'][0].name = 'other';},
  'incomplete run': f => {f.files['selfhost/HLT/summary.json'].complete = false;},
  'missing reason': f => {f.files['G11.json'].allowances.pop();},
  'invented waiver': f => {f.files['G11.json'].allowances.push({suite: 'LLT', name: 'success', reason: 'not official failure'});},
  'stale final SHA': f => {f.files['G11.json'].cjcj_head_sha = 'f'.repeat(40);},
  'mismatched compiler': f => {f.files['selfhost/identity.json'].compiler_sha256 = digest('9');},
  'nonoverlapping intervals': f => {f.files['G11.json'].selfhost.started_at = '2026-09-30T12:00:00Z';},
  'summary disagreement': f => {f.files['selfhost/LLT/summary.json'].counts.fail = 0;},
  'selfhost newly skips case': f => changeCase(f, 'Conformance', 'skip'),
};
for (const [name, mutate] of Object.entries(invalid)) test(`G11 ${name} cannot establish MET`, async t => {
  const f = await fixture(t); mutate(f);
  const {rc, row} = await runFixture(f);
  assert.equal(row.status, 'UNKNOWN', JSON.stringify(row));
  assert.equal(rc, 2);
});
test('G11 missing archive remains UNKNOWN', () => {
  const result = spawnSync(process.execPath, [cli, 'G11', '--repo', repo, '--json'], {encoding: 'utf8'});
  assert.equal(result.status, 2);
  assert.equal(JSON.parse(result.stdout).status, 'UNKNOWN');
});
test('G11 all-gates CLI consumes the same evidence', async t => {
  const f = await fixture(t);
  const {rc, row} = await runFixture(f, 'all');
  assert.equal(rc, 0);
  assert.equal(row.status, 'MET');
});
