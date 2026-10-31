#!/usr/bin/env zx
// Real CLI regression. The caller supplies a compiler and matching target std.core; compiler execution libraries and target libraries are separate.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const [compiler, workArg, targetLd] = process.argv.slice(process.argv.findIndex(x => x.endsWith('.mjs')) + 1);
assert.ok(compiler && path.isAbsolute(compiler) && workArg && targetLd,
  'usage: zx ci/test-catch-unit-any.mjs ABS_COMPILER NEW_WORK TARGET_LD_LIBRARY_PATH; set paired compiler environment');
const work = path.resolve(workArg);
assert.ok(!fs.existsSync(work), 'evidence directory must be new');
fs.mkdirSync(work, {recursive: true});
const fixture = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/catch_unit_any');
const rows = [];
function run(name, argv, env = process.env) {
  const started = new Date().toISOString();
  const out = fs.openSync(path.join(work, name + '.stdout'), 'wx');
  const err = fs.openSync(path.join(work, name + '.stderr'), 'wx');
  const p = spawnSync(argv[0], argv.slice(1), {cwd: work, env, stdio: ['ignore', out, err], timeout: 300000});
  fs.closeSync(out); fs.closeSync(err);
  rows.push({name, argv, cwd: work, started, ended: new Date().toISOString(), pid: p.pid,
    rc: p.status, signal: p.signal, error: p.error?.message ?? null});
  fs.writeFileSync(path.join(work, 'commands.json'), JSON.stringify(rows, null, 2) + '\n');
  assert.equal(p.error, undefined, name); assert.equal(p.signal, null, name); assert.equal(p.status, 0, name);
  return fs.readFileSync(path.join(work, name + '.stdout'), 'utf8');
}
const exe = path.join(work, 'catch-main');
fs.mkdirSync(path.join(work, 'temps'));
run('main', [compiler, path.join(fixture, 'Main.cj'), '-O0',
  '--save-temps=' + path.join(work, 'temps'), '-o', exe]);
const markers = {unit: ['explicit_unit', 'empty_unit', 'unit_finally_once'],
  control: ['normal_value', 'caught_value', 'catch_return', 'catch_throw']};
for (const [name, assertions] of Object.entries(markers)) {
  const stdout = run(name, [exe, name], {...process.env, LD_LIBRARY_PATH: targetLd});
  for (const marker of assertions) assert.ok(stdout.includes('CATCH_ASSERT ' + marker + '\n'), marker);
  assert.ok(stdout.includes('CATCH_CASE_PASS ' + name + '\n'), name);
}
console.log('CATCH_UNIT_ANY cases=2 assertions=7 PASS');
