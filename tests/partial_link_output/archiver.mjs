#!/usr/bin/env zx
// Real installed-driver archive controls; inputObjs are produced by public CLI parsing.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const [compiler, output] = process.argv.slice(2);
assert(compiler && path.isAbsolute(compiler) && output && path.isAbsolute(output));
fs.mkdirSync(output);
const results = [];
const record = () => fs.writeFileSync(output + '/result.json', JSON.stringify(results, null, 2));
const run = (name, command, args, env = process.env) => {
  const r = spawnSync(command, args, { cwd: output, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  fs.writeFileSync(output + '/' + name + '.log', (r.stdout ?? '') + (r.stderr ?? ''));
  results.push({ name, command, args, status: r.status, signal: r.signal, error: r.error?.message }); record(); return r;
};
const ok = r => assert.equal(r.status, 0, r.stderr);
const check = (name, body) => {
  try { body(); results.push({ name: name + '-assertions', status: 0 }); }
  catch (e) { results.push({ name: name + '-assertions', status: 1, error: e.message }); console.error(name + ': ' + e.message); process.exitCode = 1; }
  record();
};
fs.writeFileSync(output + '/pkg.cj', 'package archivecontrol\nprivate var seed: Int64 = 40\npublic func archiveValue(): Int64 { return seed + 1 }\n');
fs.writeFileSync(output + '/foreign.c', 'int foreign_archive_marker(void) { return 73; }\n');
fs.writeFileSync(output + '/cmain.c', 'extern int foreign_archive_marker(void); int main(void) { return foreign_archive_marker() != 73; }\n');
fs.writeFileSync(output + '/main.cj', 'import archivecontrol.*\nforeign { func foreign_archive_marker(): Int32 }\nmain(): Int64 { if (archiveValue() != 41 || foreign_archive_marker() != 73) { return 1 }; println("MIXED_ARCHIVE_CONSUMER_OK"); return 0 }\n');
ok(run('foreign-object', '/usr/bin/cc', ['-c', 'foreign.c', '-o', 'foreign.o']));
const base = ['pkg.cj', '--output-type=staticlib', '-O0', '--apc=4', '-j8', '-V'];
for (const [name, extra, hasSource, hasForeign] of [
  ['default', [], true, false], ['tool-dir', ['-B', '/usr/bin'], true, false],
  ['foreign', ['foreign.o'], true, true], ['foreign-tool-dir', ['foreign.o', '-B', '/usr/bin'], true, true],
  ['object-only', ['foreign.o', '--experimental'], false, true],
]) check(name, () => {
  const args = hasSource ? base : ['--output-type=staticlib', '-j8', '-V'];
  const r = run(name, compiler, [...args, ...extra, '-o=' + name + '.a']); ok(r);
  const log = r.stdout + r.stderr;
  assert.match(log, /\/(?:llvm-)?ar' 'crD'/, 'ARCHIVER_NOT_REACHED');
  const members = run(name + '-members', '/usr/bin/ar', ['t', name + '.a']); ok(members);
  const memberNames = members.stdout.trim().split('\n');
  if (hasSource) assert(memberNames.includes('archivecontrol.o'), 'CJ_OBJECT_MISSING');
  if (hasForeign) assert(memberNames.includes('foreign.o'), 'FOREIGN_OBJECT_MISSING');
  assert.equal(memberNames.length, Number(hasSource) + Number(hasForeign), 'EXTRA_OR_DUPLICATE_ARCHIVE_MEMBER');
  if (name === 'default') assert.match(log, /\/llvm-ar' 'crD'/, 'OWN_OBJECTS_NOT_USING_BUNDLED_AR');
  else assert.match(log, /\/usr\/bin\/ar' 'crD'/, 'USER_TOOL_OR_OBJECT_NOT_USING_SYSTEM_AR');
  if (hasSource && hasForeign) {
    const links = log.split('\n').filter(l => /\/ld' '-o' /.test(l));
    assert(links.length > 0, 'PARTIAL_LINK_NOT_REACHED');
    assert(links.every(l => !l.includes("/foreign.o'")), 'FOREIGN_OBJECT_ENTERED_PACKAGE_LOCALIZATION');
  }
  const index = run(name + '-index', '/usr/bin/nm', ['--print-armap', name + '.a']); ok(index);
  if (hasSource) assert.match(index.stdout, /archiveValue.* in archivecontrol\.o/);
  if (hasForeign) {
    assert.match(index.stdout, /foreign_archive_marker in foreign\.o/);
    ok(run(name + '-c-link', '/usr/bin/cc', ['cmain.c', name + '.a', '-o', name + '-cmain']));
    ok(run(name + '-c-run', output + '/' + name + '-cmain', []));
  }
  if (hasSource) {
    ok(run(name + '-cj-link', compiler, ['main.cj', '--import-path=.', '-j8', '--link-options', path.join(output, name + '.a') + (hasForeign ? '' : ' ' + path.join(output, 'foreign.o')), '-o=' + name + '-main']));
    const result = run(name + '-cj-run', output + '/' + name + '-main', []); ok(result);
    assert.match(result.stdout, /MIXED_ARCHIVE_CONSUMER_OK/);
  }
});
check('lto', () => {
  const r = run('lto', compiler, ['pkg.cj', '--output-type=staticlib', '--lto=full', '-O0', '-j8', '-V', '-o=lto.bc']); ok(r);
  const log = r.stdout + r.stderr;
  assert.match(log, /\/opt' /, 'LTO_OPT_NOT_REACHED');
  assert(!/\/(?:llvm-)?ar' 'crD'/.test(log), 'LTO_STATICLIB_UNEXPECTED_ARCHIVER');
  assert.deepEqual([...fs.readFileSync(output + '/lto.bc').subarray(0, 4)], [0x42, 0x43, 0xc0, 0xde], 'LTO_OUTPUT_NOT_BITCODE');
  // Feed the public .bc input back through the installed compiler, then import/run its CJO consumer.
  ok(run('lto-native', compiler, ['lto.bc', 'foreign.o', '--experimental', '--output-type=staticlib', '-O0', '-j8', '-V', '-o=lto-native.a']));
  const members = run('lto-native-members', '/usr/bin/ar', ['t', 'lto-native.a']); ok(members); assert.match(members.stdout, /foreign\.o/);
  ok(run('lto-cj-link', compiler, ['main.cj', '--import-path=.', '-j8', '--link-options', output + '/lto-native.a', '-o=lto-main']));
  const consumed = run('lto-cj-run', output + '/lto-main', []); ok(consumed); assert.match(consumed.stdout, /MIXED_ARCHIVE_CONSUMER_OK/);
});
check('archiver-failure', () => {
  fs.mkdirSync(output + '/fail-tools');
  fs.copyFileSync('/usr/bin/false', output + '/fail-tools/ar'); fs.chmodSync(output + '/fail-tools/ar', 0o755);
  const failed = run('archiver-failure', compiler, [...base, '-B', output + '/fail-tools', '-o=failed.a']);
  assert.equal(failed.status, 1); assert.match(failed.stdout + failed.stderr, /fail-tools\/ar' 'crD'/);
  assert.match(failed.stdout + failed.stderr, /command failed with exit code 1/);
  assert(!fs.existsSync(output + '/failed.a'));
});
if (!process.exitCode) console.log('ARCHIVER_REAL_CONTROLS_OK');
