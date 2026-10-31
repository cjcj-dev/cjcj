#!/usr/bin/env zx
// Real CLI regression. The caller supplies a compiler and matching target std.core; compiler execution libraries and target libraries are separate.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const [compiler, workArg, targetLd, llvmDis] = process.argv.slice(process.argv.findIndex(x => x.endsWith('.mjs')) + 1);
assert.ok(llvmDis && compiler && path.isAbsolute(compiler) && workArg && targetLd,
  'usage: zx ci/test-ref-struct-owner.mjs ABS_COMPILER NEW_WORK TARGET_LD_LIBRARY_PATH LLVM_DIS; set paired compiler environment');
const work = path.resolve(workArg);
assert.ok(!fs.existsSync(work), 'evidence directory must be new');
fs.mkdirSync(work, {recursive: true});
const fixture = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/ref_struct_owner');
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
fs.mkdirSync(path.join(work, 'temps'));
run('library', [compiler, path.join(fixture, 'Library.cj'), '--output-type=staticlib', '-O0',
  '--save-temps=' + path.join(work, 'temps'), '-o', path.join(work, 'libref_struct_owner.a')]);
const preopt = fs.readdirSync(path.join(work, 'temps'))
  .filter(n => /^\d+-.*\.bc$/.test(n) && !n.endsWith('.opt.bc')).sort();
assert.ok(preopt.length > 0, 'real pre-optimization modules');
const ir = preopt.map((name, index) => {
  const irPath = path.join(work, `preopt-${index}.ll`);
  run(`read-ir-${index}`, [llvmDis, path.join(work, 'temps', name), '-o', irPath]);
  return fs.readFileSync(irPath, 'utf8');
}).join('\n');
const functions = ir.match(/^define[^\n]*\{[\s\S]*?^}/gm) ?? [];
const evidence = [];
for (const name of ['heapSite', 'globalSite', 'localSite', 'relay', 'trySite']) {
  const fn = functions.filter(f => f.split('\n')[0].includes(name));
  assert.equal(fn.length, 1, name + ': exact source function reached');
  const call = fn[0].split('\n').filter(l => /\b(call|invoke)\b/.test(l) && /@[^ (]*3put/.test(l));
  assert.equal(call.length, 1, name + ': actual put call');
  evidence.push({name, signature: fn[0].split('\n')[0], call: call[0]});
  // This fixture's named source parameters give independent exact owners.
  // Match the hidden operand before value, not any later AS1 argument.
  const owner = call[0].match(/, i8 addrspace\(1\)\* ([^,]+), i8 addrspace\(1\)\* %value(?:,|\))/);
  assert.ok(owner, name + ': hidden owner operand located');
  const expected = {heapSite: '%holder', trySite: '%holder', relay: '%"$BP"',
    localSite: 'null', globalSite: 'inttoptr (i64 1 to i8 addrspace(1)*)'};
  assert.equal(owner[1], expected[name], name + ': exact final argument owner');
  evidence[evidence.length - 1].owner = owner[1];
  assert.ok(call[0].includes(name === 'trySite' ? 'invoke void' : 'call void'), name + ': call kind');

}
fs.writeFileSync(path.join(work, 'owner-calls.json'), JSON.stringify(evidence, null, 2) + '\n');
const exe = path.join(work, 'owner-main');
run('main', [compiler, path.join(fixture, 'Main.cj'), '--import-path', work, '-L', work,
  '-lref_struct_owner', '-O0', '-o', exe]);
const stdout = run('owner', [exe], {...process.env, LD_LIBRARY_PATH: targetLd});
for (const marker of ['heap', 'global', 'local', 'forwarded', 'try_apply', 'tuple_primitive']) {
  assert.ok(stdout.includes('OWNER_ASSERT ' + marker + '\n'), marker);
}
console.log('REF_STRUCT_OWNER call-sites=5 assertions=6 PASS');
