#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const fixture = path.join(import.meta.dirname, 'cjcjcg_aggregate_ctype_fixtures');
const gate = path.join(import.meta.dirname, 'cjcjcg_aggregate_ctype_report_gate.py');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'aggregate-ctype-report-'));

try {
  const run = candidate => spawnSync('python3', [gate,
    '--baseline', path.join(fixture, 'report-baseline.tsv'),
    '--candidate', path.join(fixture, candidate),
    '--out', path.join(temporary, candidate),
  ], {cwd: root, encoding: 'utf8'});

  const green = run('report-green.tsv');
  assert.equal(green.status, 0, `${green.stdout}\n${green.stderr}`);
  assert.match(green.stdout, /PASS baselinePositiveControl/);
  assert.match(green.stdout, /PASS candidateWholeCopyEmpty/);
  assert.match(green.stdout, /PASS otherKeysStable/);
  assert.match(green.stdout, /PASS newKeysEmpty/);

  const wrong = run('report-known-new.tsv');
  assert.notEqual(wrong.status, 0);
  assert.match(wrong.stdout, /FAIL newKeysEmpty/);
  console.log('PASS aggregate CType report ruler rejects a known NEW row');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
