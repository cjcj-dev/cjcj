#!/usr/bin/env zx
// Run inside an admitted build/test unit with the installed compiler's SDK environment.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const [compiler, output, mode = 'saved'] = process.argv.slice(2);
assert(compiler && path.isAbsolute(compiler) && output && path.isAbsolute(output));
assert(['saved', 'normal', 'cached'].includes(mode));
fs.mkdirSync(output); // preserve first failures; never reuse an earlier run
const results = [];
const record = () => fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(results, null, 2));
const run = (name, program, args, cwd = output) => {
  const result = spawnSync(program, args, { cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  fs.writeFileSync(path.join(output, name + '.log'), (result.stdout ?? '') + (result.stderr ?? ''));
  results.push({ name, program, args, cwd, status: result.status, signal: result.signal, error: result.error?.message });
  record();
  return result;
};
const ok = (result) => assert.equal(result.status, 0, result.stderr);
try {
  for (const dir of ['p', 'child', 'lib', 'temps', 'app']) fs.mkdirSync(path.join(output, dir));
  fs.writeFileSync(path.join(output, 'p/p.cj'), 'package p\nprivate var parentSeed: Int64 = 10\npublic func parentValue(): Int64 { return parentSeed + 1 }\n');
  fs.writeFileSync(path.join(output, 'child/child.cj'), 'package p.partial\nprivate var childSeed: Int64 = 20\npublic func childValue(): Int64 { return childSeed + 2 }\n');
  fs.writeFileSync(path.join(output, 'app/main.cj'), 'import p.*\nimport p.partial.*\nmain(): Int64 {\n if (parentValue() != 11 || childValue() != 22) { return 1 }\n println("PARTIAL_LINK_TWO_PACKAGES_OK")\n return 0\n}\n');
  const args = ['-p', 'p', 'child', '--no-sub-pkg', '--output-type=staticlib', '--output-dir=lib', '-o=libpair.a', '-O0', '--apc=4', '-j8', '-V'];
  if (mode === 'saved') args.push('--save-temps=temps');
  if (mode === 'cached') args.push('--experimental', '--incremental-compile');
  const compiled = run('compile', compiler, args);
  // This is a product invariant, checked after real frontend/backend execution even if ar failed.
  const log = (compiled.stdout ?? '') + (compiled.stderr ?? '');
  const links = [...log.matchAll(/(?:^|\n)'[^'\n]*\/ld' '-o' '([^']+)' '-r' /g)].map(m => path.resolve(output, m[1]));
  assert.equal(links.length, 2, 'TARGET_NOT_REACHED: expected two real partial links');
  const localized = [...log.matchAll(/(?:^|\n)'[^'\n]*llvm-objcopy' '([^']+)' '([^']+)' '--localize-symbols=([^']+)'/g)];
  assert.equal(localized.length, 2, 'TARGET_NOT_REACHED: expected two localized package objects');
  const finalObjects = localized.map(m => path.resolve(output, m[2]));
  assert.equal(new Set(links).size, 2, 'PARTIAL_INTERMEDIATE_NOT_UNIQUE');
  assert(links.every(p => !finalObjects.includes(p)), 'PARTIAL_INTERMEDIATE_ALIASES_PACKAGE_OBJECT');
  results.push({ name: 'partial-path-isolation', status: 0, links, finalObjects }); record();
  ok(compiled);
  const archive = path.join(output, 'lib/libpair.a');
  const members = run('members', '/usr/bin/ar', ['t', archive]); ok(members);
  assert.deepEqual(members.stdout.trim().split('\n'), ['p.o', 'p.partial.o']);
  const symbols = run('symbols', '/usr/bin/nm', ['-A', '--defined-only', archive]); ok(symbols);
  assert.match(symbols.stdout, /p\.o:.* [TD] .*parentValue/);
  assert.match(symbols.stdout, /p\.partial\.o:.* [TD] .*childValue/);
  assert(!symbols.stdout.split('\n').some(l => /p\.partial\.o:.*parentValue|:p\.o:.*childValue/.test(l)), 'PACKAGE_DEFINITIONS_CROSSED');
  const index = run('index', '/usr/bin/nm', ['--print-armap', archive]); ok(index);
  assert.match(index.stdout, /parentValue.* in p\.o/);
  assert.match(index.stdout, /childValue.* in p\.partial\.o/);
  if (mode === 'saved') {
    assert(links.every(p => fs.existsSync(p)), 'SAVE_TEMPS_DROPPED_PARTIAL');
    for (const object of finalObjects) {
      const cmp = run('cache-' + path.basename(object), '/usr/bin/find', [output, '-path', '*/.cached/*.o']); ok(cmp);
      const objects = cmp.stdout.trim().split('\n').filter(Boolean);
      assert(objects.some(p => fs.readFileSync(p).equals(fs.readFileSync(object))), 'PACKAGE_CACHE_MISSING_OR_CROSSED');
    }
  } else assert(links.every(p => !fs.existsSync(p)), 'PARTIAL_NOT_CLEANED');
  if (mode === 'cached') {
    const warm = run('cache-reentry', compiler, args); ok(warm);
    assert(!/\/ld' '-o' /.test(warm.stdout + warm.stderr), 'NO_CHANGE_CACHE_REBUILT_PARTIAL');
  }
  ok(run('consumer-compile', compiler, ['app/main.cj', '--import-path=lib', '-Llib', '-lpair', '-o=app/main', '-j8']));
  const consumer = run('consumer-run', path.join(output, 'app/main'), []); ok(consumer);
  assert.match(consumer.stdout, /PARTIAL_LINK_TWO_PACKAGES_OK/);
  results.push({ name: 'two-package-consumer', status: 0 }); record();
  console.log('PARTIAL_LINK_REGRESSION_OK ' + mode);
} catch (error) {
  results.push({ name: 'assertion', status: 1, error: error.message }); record();
  console.error(error); process.exitCode = 1;
}
