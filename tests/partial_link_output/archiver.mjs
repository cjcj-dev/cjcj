#!/usr/bin/env zx
// Narrow real-driver controls for the bundled archiver selection and failure propagation.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const [compiler, output] = process.argv.slice(2);
assert(compiler && path.isAbsolute(compiler) && output && path.isAbsolute(output));
fs.mkdirSync(output);
const results = [];
const run = (name, command, args, env = process.env) => {
  const r = spawnSync(command, args, { cwd: output, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  fs.writeFileSync(output + '/' + name + '.log', (r.stdout ?? '') + (r.stderr ?? ''));
  results.push({ name, command, args, status: r.status, signal: r.signal, error: r.error?.message });
  fs.writeFileSync(output + '/result.json', JSON.stringify(results, null, 2)); return r;
};
const ok = r => assert.equal(r.status, 0, r.stderr);
try {
  fs.writeFileSync(output + '/pkg.cj', 'package archivecontrol\npublic func archiveValue(): Int64 { return 41 }\n');
  fs.writeFileSync(output + '/foreign.c', 'int foreign_archive_marker(void) { return 73; }\n');
  ok(run('foreign-object', '/usr/bin/cc', ['-c', 'foreign.c', '-o', 'foreign.o']));
  const base = ['pkg.cj', '--output-type=staticlib', '-O0', '--apc=4', '-j8', '-V'];
  for (const [name, extra] of [['default', []], ['tool-dir', ['-B', '/usr/bin']], ['foreign', ['foreign.o']], ['lto', ['--lto=full']]]) {
    const r = run(name, compiler, [...base, ...extra, '-o=' + name + '.a']); ok(r);
    const log = r.stdout + r.stderr;
    if (name === 'default') assert.match(log, /\/llvm-ar' 'crD'/);
    else assert.match(log, /\/usr\/bin\/ar' 'crD'/);
    const members = run(name + '-members', '/usr/bin/ar', ['t', name + '.a']); ok(members);
    const index = run(name + '-index', '/usr/bin/nm', ['--print-armap', name + '.a']); ok(index);
    if (name === 'foreign') { assert.match(members.stdout, /foreign\.o/); assert.match(index.stdout, /foreign_archive_marker in foreign\.o/); }
    if (name !== 'lto') assert.match(index.stdout, /archiveValue.* in archivecontrol\.o/);
  }
  // -B is an explicit user-tool branch; a real nonzero archiver must fail the product command.
  fs.mkdirSync(output + '/fail-tools');
  fs.copyFileSync('/usr/bin/false', output + '/fail-tools/ar'); fs.chmodSync(output + '/fail-tools/ar', 0o755);
  const failed = run('archiver-failure', compiler, [...base, '-B', output + '/fail-tools', '-o=failed.a']);
  assert.notEqual(failed.status, 0); assert.match(failed.stdout + failed.stderr, /fail-tools\/ar' 'crD'/);
  assert.match(failed.stdout + failed.stderr, /command failed with exit code 1/);
  assert(!fs.existsSync(output + '/failed.a'));
  console.log('ARCHIVER_REAL_CONTROLS_OK');
} catch (e) {
  results.push({ name: 'assertion', status: 1, error: e.message });
  fs.writeFileSync(output + '/result.json', JSON.stringify(results, null, 2)); console.error(e); process.exitCode = 1;
}
