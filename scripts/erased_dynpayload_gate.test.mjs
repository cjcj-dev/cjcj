#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '..');
const gate = path.join(import.meta.dirname, 'erased_dynpayload_gate.mjs');
const header = [
  'module', 'function', 'rule', 'instruction', 'dest_as', 'src_as', 'length',
  'dest_root', 'src_root', 'source_type',
].join('\t');
const rule = 'Bare memcpy/memmove payload provenance is unknown; use a typed helper.';
const p1p0 = ['std.unittest.common', 'Range.provide$withoutTI', rule, 'memcpy', '1', '0',
  '%7', 'call', 'alloca', 'i8*'].join('\t');
const p1p1 = ['std.net', 'ExternallyLockedLazy.compute$withoutTI', rule, 'memcpy', '1', '1',
  '%52', 'argument', 'call', 'i8* addrspace(1)*'].join('\t');
const other = ['std.core', 'unrelated', rule, 'memcpy', '0', '1', '16',
  'alloca', 'argument', 'record*'].join('\t');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'erased-dynpayload-gate-'));
try {
  const write = (name, rows) => {
    const file = path.join(temporary, `${name}.tsv`);
    fs.writeFileSync(file, `${[header, ...rows].join('\n')}\n`);
    return file;
  };
  const baseline = write('baseline', [p1p0, p1p1, other]);
  const candidates = {
    green: write('green', [other]),
    'box-cut': write('box-cut', [p1p0, other]),
    'step5-cut': write('step5-cut', [p1p1, other]),
  };
  const run = (reportExpectation, candidate) => spawnSync(process.execPath, [gate,
    '--source-root', repoRoot,
    '--baseline-report', baseline,
    '--candidate-report', candidate,
    '--report-expect', reportExpectation,
  ], {encoding: 'utf8'});

  for (const [expectation, candidate] of Object.entries(candidates)) {
    const result = run(expectation, candidate);
    assert.equal(result.status, 0, `${expectation}\n${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /PASS report\.baseline-positive/);
    assert.match(result.stdout, /PASS report\.new-empty: NEW=0/);
    assert.match(result.stdout, /PASS report\.other-unchanged: removed_other=0/);
  }

  const knownWrong = run('box-cut', candidates.green);
  assert.notEqual(knownWrong.status, 0);
  assert.match(knownWrong.stdout, /FAIL report\.p1p0\.kept/);
  console.log('PASS report ruler rejects a known over-removal');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
