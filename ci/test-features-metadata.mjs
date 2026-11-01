#!/usr/bin/env zx
// Package metadata stays untyped; source diagnostics and executable code still run.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [compiler, workArg, targetLd] = process.argv.slice(2);
assert.ok(compiler && path.isAbsolute(compiler) && workArg && targetLd,
  'usage: zx ci/test-features-metadata.mjs ABS_COMPILER NEW_WORK TARGET_LD; set paired compiler environment');
const work = path.resolve(workArg);
assert.ok(!fs.existsSync(work), 'preserve earlier evidence');
fs.mkdirSync(work, {recursive: true});
const records = [];
function run(name, argv, expected = 0, env = process.env) {
  const started = new Date().toISOString();
  const out = fs.openSync(path.join(work, name + '.stdout'), 'wx');
  const err = fs.openSync(path.join(work, name + '.stderr'), 'wx');
  const p = spawnSync(argv[0], argv.slice(1), {cwd: work, env,
    stdio: ['ignore', out, err], timeout: 300000});
  fs.closeSync(out); fs.closeSync(err);
  records.push({name, argv, cwd: work, started, ended: new Date().toISOString(),
    pid: p.pid, rc: p.status, signal: p.signal, error: p.error?.message ?? null, expected});
  fs.writeFileSync(path.join(work, 'commands.json'), JSON.stringify(records, null, 2) + '\n');
  assert.equal(p.error, undefined, name); assert.equal(p.signal, null, name); assert.equal(p.status, expected, name);
  return fs.readFileSync(path.join(work, name + '.stdout'), 'utf8');
}
const source = path.join(work, 'features.cj'), exe = path.join(work, 'features');
fs.writeFileSync(source, 'features {}\nmain() { println(7) }\n');
run('compile', [compiler, source, '--set-runtime-rpath', '-o', exe]);
assert.equal(run('target', [exe], 0, {...process.env, LD_LIBRARY_PATH: targetLd}).trim(), '7');
const scanDir = path.join(work, 'metadata'); fs.mkdirSync(scanDir);
fs.writeFileSync(path.join(scanDir, 'main.cj'), 'features { example.preview }\nmain() { println(7) }\n');
const info = JSON.parse(run('scan', [compiler, '-p', scanDir, '--scan-dependency']));
assert.deepEqual(info.features, ['example.preview'], 'the fix must not discard package metadata');
const bad = path.join(work, 'bad.cj');
fs.writeFileSync(bad, 'features {}\nmain() { let value: Int64 = "not an integer"; println(value) }\n');
run('bad-type', [compiler, bad, '-o', path.join(work, 'bad')], 1);
const diagnostic = fs.readFileSync(path.join(work, 'bad-type.stderr'), 'utf8');
assert.ok(diagnostic.includes('bad.cj'), 'real user declaration is diagnosed');
assert.ok(!/invalid sema type on features_/.test(diagnostic), 'metadata must not mask the declaration failure');
assert.ok(!fs.existsSync(path.join(work, 'bad')), 'invalid code must not produce an executable');
console.log('FEATURES_METADATA compile/run/metadata/type-rejection PASS');
