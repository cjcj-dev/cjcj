#!/usr/bin/env zx
// Run against the compiler being tested, with its SDK environment set by the caller.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const compiler = path.resolve(process.argv[2]);
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'warning-group-'));
try {
  const source = path.join(work, 'api.cj');
  fs.writeFileSync(source, 'package warnfixture\npublic func answer(): Int64 { 42 }\n');
  const cjo = path.join(work, 'warnfixture.cjo');
  const compile = (options = []) => {
    const result = spawnSync(compiler, [source, '--experimental', '--output-type=chir',
      '--diagnostic-format=noColor', '--output-dir', work, '-o', work + '/', ...options],
    {cwd: work, encoding: 'utf8'});
    if (result.error) throw result.error;
    console.log(JSON.stringify({options, status: result.status, signal: result.signal, stderr: result.stderr}));
    return result;
  };
  assert.equal(compile().status, 0);
  assert.ok(fs.statSync(cjo).size > 0);
  // A directory in the file's place fails the real SaveCjo write, even as root.
  fs.unlinkSync(cjo);
  fs.mkdirSync(cjo);
  const rejected = compile(['-Woff', 'unused']);
  assert.equal(rejected.signal, null);
  assert.equal(rejected.status, 1);
  assert.ok(rejected.stderr.includes('warning: failed to write CJO: ' + cjo), rejected.stderr);
  assert.doesNotMatch(rejected.stderr, /this warning can be suppressed/);
  const quiet = compile(['-Woff', 'all']);
  assert.equal(quiet.status, 1);
  assert.doesNotMatch(quiet.stderr, /warning: failed to write CJO/);
} finally {
  fs.rmSync(work, {recursive: true, force: true});
}
