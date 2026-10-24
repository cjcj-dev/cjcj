#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';

const [candidatePath, cutPath, restoredPath, output] = process.argv.slice(2);
assert(candidatePath && cutPath && restoredPath && output,
  'usage: verify-arms.mjs CANDIDATE_RESULTS CUT_RESULTS RESTORED_RESULTS NEW_RESULT');
const names = ['root', 'delegated', 'implicit', 'const_finalized', 'const_nested',
  'const_temporary', 'const_plain', 'control'];
const key = row => `${row.name}/${row.phase}/${row.optimization}`;
const expected = names.flatMap(name => ['raw', 'opt'].flatMap(phase =>
  ['O0', 'O2'].map(optimization => `${name}/${phase}/${optimization}`)));
const targeted = new Set(['root_event_before_normal_exit',
  'derived_constructor_reaches_root_event', 'const_batch_retains_runtime_event']);
const observations = [];

for (const [arm, file] of [['candidate', candidatePath], ['cut', cutPath], ['restored', restoredPath]]) {
  const rows = JSON.parse(readFileSync(file, 'utf8'));
  assert.equal(rows.length, expected.length, `${arm}: incomplete matrix`);
  const byKey = new Map(rows.map(row => [key(row), row]));
  assert.equal(byKey.size, expected.length, `${arm}: duplicate input`);
  let preciseRed = 0, independentControls = 0, readers = 0;
  for (const label of expected) {
    const row = byKey.get(label);
    assert(row, `${arm}: missing ${label}`);
    assert.equal(row.command.rc, 0, `${arm}/${label}: compile failed before assertions`);
    assert.equal(row.command.signal, null, `${arm}/${label}: compile signal`);
    assert.equal(row.command.error, null, `${arm}/${label}: executor error`);
    assert(row.artifact && row.status !== 'NOT_RUN', `${arm}/${label}: missing CHIR assertion`);
    assert(row.name === 'control' || Object.hasOwn(row.checks, 'root_event_before_normal_exit'),
      `${arm}/${label}: root assertion missing`);
    if (row.name === 'control' && row.phase === 'opt')
      assert(Object.hasOwn(row.checks, 'scalar_const_still_folds'), `${arm}/${label}: scalar control missing`);
    if (row.name === 'const_plain' && row.phase === 'opt')
      assert(Object.hasOwn(row.checks, 'plain_const_still_materializes'), `${arm}/${label}: plain control missing`);
    for (const [check, value] of Object.entries(row.checks)) {
      if (check === 'serialization_reader') continue;
      const want = !(arm === 'cut' && targeted.has(check));
      assert.equal(value, want, `${arm}/${label}/${check}`);
      if (!want) preciseRed++;
      if (check === 'scalar_const_still_folds' || check === 'plain_const_still_materializes')
        independentControls++;
    }
    if (row.name === 'root' || (row.name === 'control' && row.phase === 'opt')) {
      assert(row.reader, `${arm}/${label}: real product reader not run`);
      const wantRc = arm === 'cut' && row.name === 'root' ? 1 : 0;
      assert.equal(row.reader.rc, wantRc, `${arm}/${label}: reader rc`);
      assert.equal(row.reader.signal, null, `${arm}/${label}: reader signal`);
      assert.equal(row.reader.error, null, `${arm}/${label}: reader execution error`);
      const stdout = readFileSync(row.artifact.replace(/\/output_CHIR\/[^/]+$/, '/reader.stdout'), 'utf8');
      const marker = row.name === 'control' ? 'TARGET deserialized_scalar_fold=true' :
        `TARGET deserialized_root_return=${wantRc === 0 ? 'true' : 'false'}`;
      assert(stdout.includes(marker), `${arm}/${label}: reader target not reached`);
      assert.equal(row.checks.serialization_reader, wantRc === 0);
      readers++;
    }
  }
  assert.equal(independentControls, 4, `${arm}: independent controls incomplete`);
  assert.equal(readers, 6, `${arm}: binary CHIR reader matrix incomplete`);
  if (arm === 'cut') assert(preciseRed > 0, 'cut never reached a target rejection');
  observations.push({arm, file, cases: rows.length, preciseRed, independentControls, readers});
}
writeFileSync(output, JSON.stringify({status: 'PASS_FINITE_CHIR_CUT_RESTORE', observations,
  runtimeQualification: 'NOT_GRANTED'}, null, 2) + '\n', {flag: 'wx'});
console.log('TARGET root-return cut/controls/restoration PASS');
