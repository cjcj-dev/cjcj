import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {bindEvidence} from './evidence-binding-fixture.mjs';
import {allReleasePlatforms, getReleasePlatform, getTarget} from '../build/lib/targets.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci/release-gates.mjs');
const hash = 'a'.repeat(64);
const gates = ['G3', 'G6', 'G7', 'G9', 'G10'];
function git(root, ...args) {
  const r = spawnSync('git', ['-C', root, ...args], {encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
}
async function write(root, name, value) {
  const file = path.join(root, name);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, typeof value === 'string' ? value : JSON.stringify(value));
}
const platforms = allReleasePlatforms().map(key => {
  const p = getReleasePlatform(key), {spec} = getTarget(p.host);
  return {...p, llvm: spec.llvmPlatform, tuples: [...new Set([spec.runtimeTuple, ...p.crossTuples])]};
});
// Independent fixtures specify producer fields, not the consumer's requirements helper.
function platformData(gate) {
  const rows = gate === 'G6' ? [...new Set(platforms.map(p => p.llvm))].map(id => ({id,
    checks: ['producer', 'manifest_pin', 'llc_sha', 'opt_sha', 'llc_version', 'opt_version', 'shim'], artifacts: ['llc.gz', 'opt.gz', 'manifest', 'shim']})) :
    platforms.flatMap(p => gate === 'G3' ? p.tuples.map(tuple => ({id: `${p.key}/${tuple}`,
      checks: ['producer', 'assertFinalStd'], artifacts: ['final_std']})) : [{id: p.key,
      checks: gate === 'G7' ? ['archive_manifest', 'clean_stamp', 'artifact_sha'] :
        ['package', 'smoke', 'checksums', ...(p.host.startsWith('darwin-') ? ['darwin_lto'] : [])],
      artifacts: gate === 'G7' ? ['archive', 'manifest'] : ['archive', 'manifest', 'checksums']}]);
  return {schema: 1, gate, records: rows.map(r => ({id: r.id,
    checks: Object.fromEntries(r.checks.map(name => [name, {rc: 0, log: 'checks.log'}])),
    artifacts: Object.fromEntries(r.artifacts.map(name => [name, {name, bytes: 10, sha256: hash}]))}))};
}
function g10Data(head) {
  const corpus = Array.from({length: 50}, (_, i) => ({id: `case_${i}`, file: `${i}.cj`, expected_rc: 0, sha256: hash}));
  const ok = () => ({rc: 0, signal: null, error: null, timed_out: false, skipped_who: 0, signature: 'OK'});
  return {schema: 1, gate: 'G10', head, status: 'MET', failures: [], not_run: {}, injection: null, skipped_who: 0, corpus,
    arms: Object.fromEntries(['official', 'selfhost'].map(arm => [arm, {status: 'ran', compiler_sha256: hash,
      runtime: {'libcangjie-runtime.so': hash, 'libboundscheck.so': hash}}])),
    records: ['official', 'selfhost'].flatMap(arm => ['version', 'compile', 'crashsweep'].flatMap(phase =>
      (phase === 'crashsweep' ? corpus.map(c => c.id) : Array.from({length: 20}, (_, i) => String(i + 1))).map(id =>
        ({arm, phase, id, ...(phase === 'version' ? {invoke: ok()} : {compile: ok(), run: ok(), source_sha256: hash, elf_sha256: hash})}))))};
}
async function fixture(t, gate) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'release-run-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const checkout = path.join(root, 'checkout'), evidence = path.join(root, 'evidence', gate);
  for (const file of ['build/lib/targets.mjs', 'build/lib/errors.mjs', '.github/workflows/release.yml']) {
    await write(checkout, file, await fs.readFile(path.join(repo, file), 'utf8'));
  }
  // Fixture checkout freezes the actual registry and workflow with its error dependency.
  await write(checkout, 'ops/coord/RELEASE_0_0_2_RUNBOOK.md', `export RELEASE_EVIDENCE_ROOT=${path.join(root, 'evidence')}\n`);
  git(checkout, 'init', '-q'); git(checkout, 'add', '.');
  git(checkout, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture');
  const head = git(checkout, 'rev-parse', 'HEAD');
  const data = gate === 'G10' ? g10Data(head) : platformData(gate);
  await write(evidence, 'checks.log', 'verifier fixture: rc=0\n');
  const save = async () => {
    await fs.rm(path.join(evidence, 'EVIDENCE_BINDING.json'), {force: true});
    await write(evidence, `${gate}_RESULTS.json`, data);
    return await bindEvidence(evidence, gate, checkout);
  };
  await save();
  await write(path.join(root, 'evidence'), 'GATE_EVIDENCE.json', {schema: 1, gates: {[gate]: gate}});
  return {root, checkout, evidence, data, save};
}
function run(s, gate, explicit = true) {
  const r = spawnSync(process.execPath, [command, gate, '--repo', s.checkout, '--json', ...(explicit ? ['--evidence', s.evidence] : [])], {encoding: 'utf8'});
  return {rc: r.status, ...JSON.parse(r.stdout)};
}
function check(t, r, status, needle) {
  // Emit the product result before the target assertion, also on passing runs.
  t.diagnostic(`TARGET gate=${r.gate} rc=${r.rc} status=${r.status} expected=${status} item=${needle || 'complete'}`);
  assert.equal(r.status, status, JSON.stringify(r));
  assert.equal(r.rc, {MET: 0, NOT_MET: 1, UNKNOWN: 2}[status]);
  if (needle) assert.ok(r.value.includes(needle), r.value);
}
for (const gate of gates) {
  test(`${gate} complete bound evidence through explicit and registry CLI`, async t => {
    const s = await fixture(t, gate);
    check(t, run(s, gate), 'MET'); check(t, run(s, gate, false), 'MET');
  });
  test(`${gate} stale binding and changed payload never pass`, async t => {
    const s = await fixture(t, gate);
    const binding = JSON.parse(await fs.readFile(path.join(s.evidence, 'EVIDENCE_BINDING.json')));
    binding.cjcj_head_sha = 'f'.repeat(40);
    await write(s.evidence, 'EVIDENCE_BINDING.json', binding);
    check(t, run(s, gate), 'UNKNOWN', 'cjcj_head_sha');
    await s.save(); await fs.appendFile(path.join(s.evidence, `${gate}_RESULTS.json`), ' ');
    check(t, run(s, gate), 'UNKNOWN', 'sha256 mismatch');
  });
  test(`${gate} missing result file is named`, async t => {
    const s = await fixture(t, gate);
    await fs.rm(path.join(s.evidence, `${gate}_RESULTS.json`));
    await fs.rm(path.join(s.evidence, 'EVIDENCE_BINDING.json'));
    await bindEvidence(s.evidence, gate, s.checkout);
    check(t, run(s, gate), 'UNKNOWN', `${gate}_RESULTS.json`);
  });
}
for (const gate of gates.filter(g => g !== 'G10')) {
  test(`${gate} every platform tuple or LLVM record is required`, async t => {
    const s = await fixture(t, gate);
    for (let i = 0; i < s.data.records.length; i++) {
      const [row] = s.data.records.splice(i, 1); await s.save();
      check(t, run(s, gate), 'NOT_MET', row.id);
      s.data.records.splice(i, 0, row);
    }
  });
  test(`${gate} every check and artifact is required and failed checks are NOT_MET`, async t => {
    const s = await fixture(t, gate);
    // Cover each distinct obligation, including Darwin LTO.
    const seen = new Set();
    for (const row of s.data.records) {
      for (const group of ['checks', 'artifacts']) for (const key of Object.keys(row[group])) {
        if (seen.has(`${group}/${key}`)) continue;
        seen.add(`${group}/${key}`);
        const field = row[group][key]; delete row[group][key]; await s.save();
        check(t, run(s, gate), 'UNKNOWN', `${row.id}:${group === 'artifacts' ? 'artifact:' : ''}${key}`);
        row[group][key] = field;
        if (group === 'checks') {
          field.rc = 7; await s.save(); check(t, run(s, gate), 'NOT_MET', `${row.id}:${key}:rc=7`); field.rc = 0;
        }
      }
    }
  });
  test(`${gate} duplicate and unexpected records do not pass`, async t => {
    const s = await fixture(t, gate);
    s.data.records.push(s.data.records[0]); await s.save();
    check(t, run(s, gate), 'NOT_MET', 'records=2');
    s.data.records.pop(); s.data.records.push({id: 'outside-registry'}); await s.save();
    check(t, run(s, gate), 'NOT_MET', 'unexpected record:outside-registry');
  });
}
test('G10 raw failure overrides forged MET summary and names exact case', async t => {
  const s = await fixture(t, 'G10');
  const row = s.data.records.find(r => r.arm === 'selfhost' && r.phase === 'crashsweep');
  row.run.rc = null; row.run.signal = 'SIGABRT'; row.run.signature = 'SIGNAL:SIGABRT';
  await s.save(); check(t, run(s, 'G10'), 'NOT_MET', 'selfhost/crashsweep/case_0:run:SIGNAL:SIGABRT');
});
test('G10 each arm phase has required records and compiler identity', async t => {
  const s = await fixture(t, 'G10');
  for (const arm of ['official', 'selfhost']) {
    for (const phase of ['version', 'compile', 'crashsweep']) {
      const index = s.data.records.findIndex(r => r.arm === arm && r.phase === phase);
      const [row] = s.data.records.splice(index, 1); await s.save();
      check(t, run(s, 'G10'), 'UNKNOWN', `${arm}/${phase}/${row.id}:records=0`);
      s.data.records.splice(index, 0, row);
    }
    const id = s.data.arms[arm].compiler_sha256; delete s.data.arms[arm].compiler_sha256;
    await s.save(); check(t, run(s, 'G10'), 'UNKNOWN', `${arm}:compiler_sha256`); s.data.arms[arm].compiler_sha256 = id;
  }
});
test('G10 skipped WHO, malformed records, NOT_RUN, short corpus and duplicate are rejected', async t => {
  const s = await fixture(t, 'G10'), original = structuredClone(s.data);
  for (const [mutate, status, needle] of [
    [d => { d.records[0].invoke.skipped_who = 1; }, 'NOT_MET', 'official/version/1:invoke'],
    [d => { delete d.records[0].invoke.signal; }, 'UNKNOWN', 'official/version/1:invoke'],
    [d => { d.arms.selfhost.status = 'NOT_RUN'; }, 'UNKNOWN', 'selfhost:NOT_RUN'],
    [d => { d.corpus.pop(); }, 'NOT_MET', 'unexpected record:selfhost/crashsweep/case_49'],
    [d => { d.records.push(d.records[0]); }, 'NOT_MET', 'official/version/1:records=2'],
    [d => { d.records[20].source_sha256 = ''; }, 'UNKNOWN', 'source_sha256'],
    [d => { d.records[20].elf_sha256 = ''; }, 'UNKNOWN', 'elf_sha256'],
    [d => { d.head = 'f'.repeat(40); }, 'UNKNOWN', 'G10_RESULTS.json:head'],
  ]) {
    Object.assign(s.data, structuredClone(original)); mutate(s.data); await s.save(); check(t, run(s, 'G10'), status, needle);
  }
});
