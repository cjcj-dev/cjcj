import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {parseSummary} from './g8.mjs';

const repo = path.resolve(import.meta.dirname, '../..');
const sha = 'c'.repeat(40);
const good = {
  schema: 1, campaign_id: `${sha}-20260930T010000Z-1`, cjcj_head_sha: sha,
  captured_utc: '2026-09-30T01:00:00Z',
  results: {
    difftest: {total: 2, pass: 2, mismatch: 0, fail: 0}, smoke: {pass: 3, fail: 0},
    bcgate: {shared: 4, byte_identical: 3, differing: 1, compile_errors: 0}, verify_exit: 0,
  },
};
const diff = 'TOTAL=2  PASS=2  MISMATCH=0  FAIL=0\n';
const smoke = '[smoke] summary: pass=3 fail=0 workdir=/work\n';
const bc = 'shared functions: 4  |  byte-identical: 3 (75.0%)  |  differing: 1\n' +
  'fully-identical samples: 1/2  |  compile-errors: 0\n';

test('G8 parses each real summary format without substituting zeros', () => {
  assert.deepEqual(parseSummary('difftest', diff), good.results.difftest);
  assert.deepEqual(parseSummary('smoke', smoke), good.results.smoke);
  assert.deepEqual(parseSummary('bcgate', bc), good.results.bcgate);
  for (const [name, output] of [['difftest', diff], ['smoke', smoke], ['bcgate', bc]]) {
    assert.throws(() => parseSummary(name, ''), /expected one summary/);
    assert.throws(() => parseSummary(name, output + output), /expected one summary/);
  }
  assert.throws(() => parseSummary('difftest', diff.replace('TOTAL=2', 'TOTAL=3')), /inconsistent/);
  assert.throws(() => parseSummary('difftest', 'TOTAL=0 PASS=0 MISMATCH=0 FAIL=0\n'), /empty/);
  assert.throws(() => parseSummary('smoke', smoke.replace('pass=3', 'pass=0')), /empty/);
  assert.throws(() => parseSummary('bcgate', bc.replace('functions: 4', 'functions: 5')), /inconsistent/);
});

async function fixture(t) {
  const base = process.env.RELEASE_EVIDENCE_TEST_ROOT || os.tmpdir();
  await fs.mkdir(base, {recursive: true});
  const root = await fs.mkdtemp(path.join(base, 'g8-producer-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const floor = path.join(root, 'build/lib/full-gate-release-floor.mjs');
  const results = path.join(root, 'G8_FULL_GATE.json');
  const writer = value => {
    return fs.writeFile(results, JSON.stringify(value)).then(() => spawnSync(process.execPath,
      [path.join(repo, 'ci/write-full-gate-floor.mjs'), '--results', results, '--out', floor], {encoding: 'utf8'}));
  };
  const gate = () => {
    const result = spawnSync(process.execPath, [path.join(repo, 'ci/release-gates.mjs'),
      'G8', '--repo', root, '--evidence', root, '--json'], {encoding: 'utf8'});
    return {...result, value: JSON.parse(result.stdout)};
  };
  return {root, floor, results, writer, gate};
}

test('G8 preserves one wrong answer through the floor writer and release consumer', async t => {
  const f = await fixture(t);
  assert.equal((await f.writer(good)).status, 0);
  assert.equal(f.gate().value.status, 'MET');
  const broken = structuredClone(good);
  broken.results.difftest = parseSummary('difftest', 'TOTAL=2 PASS=1 MISMATCH=1 FAIL=0\n');
  const rejected = await f.writer(broken);
  assert.equal(rejected.status, 1);
  assert.match(rejected.stderr, /baseline.difftest.mismatch=1/);
  const red = f.gate();
  assert.equal(red.value.status, 'NOT_MET');
  assert.match(red.value.value, /difftest=1\/2 mismatch=1 fail=0/);
  assert.doesNotMatch(red.value.value, /smoke=|bcgate=|verify_exit=/);
  console.log('TARGET G8 difftest=1/2 mismatch=1 fail=0; other surfaces unchanged');
});

test('G8 floor writer names every omitted result field and preserves the floor', async t => {
  const f = await fixture(t);
  assert.equal((await f.writer(good)).status, 0);
  const before = await fs.readFile(f.floor, 'utf8');
  const fields = ['schema', 'campaign_id', 'cjcj_head_sha', 'captured_utc',
    ...Object.entries(good.results).flatMap(([key, value]) => typeof value === 'object'
      ? Object.keys(value).map(field => `results.${key}.${field}`) : [`results.${key}`])];
  for (const field of fields) {
    const value = structuredClone(good);
    const parts = field.split('.');
    const last = parts.pop();
    delete parts.reduce((obj, part) => obj[part], value)[last];
    const rejected = await f.writer(value);
    assert.equal(rejected.status, 1, `TARGET missing ${field}`);
    const label = field.replace(/^results\./, 'baseline.').replace('captured_utc', 'measured_utc');
    assert.ok(rejected.stderr.includes(label), rejected.stderr);
    assert.equal(await fs.readFile(f.floor, 'utf8'), before);
    console.log(`TARGET missing ${field} rejected`);
  }
});
