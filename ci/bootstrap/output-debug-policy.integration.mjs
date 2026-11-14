#!/usr/bin/env zx
// Linux output debug policy through the public cjc entry of an installed SDK whose standard
// library carries DWARF: final executables and shared libraries keep DWARF only when the
// invocation has -g; static archives stay reusable for later -g links; the installed std
// inputs are never modified. Usage: output-debug-policy.integration.mjs --cjc <sdk>/bin/cjc --work <new dir>
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {parseArgs} from 'node:util';

const {values} = parseArgs({options: {cjc: {type: 'string'}, work: {type: 'string'}, symbolizer: {type: 'string'}}});
assert.ok(values.cjc && values.work, 'usage: --cjc <sdk>/bin/cjc --work <new dir>');
const cjc = path.resolve(values.cjc), work = path.resolve(values.work);
const home = process.env.CANGJIE_HOME || path.dirname(path.dirname(cjc));
const tuple = 'linux_x86_64_cjnative';
fs.mkdirSync(work, {recursive: false});
const run = (argv, options = {}) => {
  const r = spawnSync(argv[0], argv.slice(1), {encoding: 'utf8', maxBuffer: 1 << 28, ...options});
  if (r.error) throw r.error;
  return {argv, rc: r.status, signal: r.signal, stdout: r.stdout, stderr: r.stderr};
};
const ok = (argv, options) => {
  const r = run(argv, options);
  assert.equal(r.rc, 0, `${argv.join(' ')}\n${r.stdout.slice(-2000)}${r.stderr.slice(-4000)}`);
  return r;
};
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sections = file => ok(['readelf', '-S', '-W', file]).stdout.split('\n')
  .map(line => line.match(/^\s*\[\s*\d+\]\s+(\S+)/)?.[1]).filter(Boolean);
const debugSections = file => sections(file).filter(name => name.startsWith('.debug'));
const find = names => names.map(name => [path.join(home, 'lib', tuple, name), path.join(home, 'runtime/lib', tuple, name)])
  .flat().find(file => fs.existsSync(file)) ?? assert.fail('missing std input ' + names.join('|'));
const symbolizer = values.symbolizer || [path.join(home, 'third_party/llvm/bin/llvm-symbolizer')].find(f => fs.existsSync(f)) || 'llvm-symbolizer';
const report = {cjc, home, checks: []};
const check = (name, fn) => { fn(); report.checks.push(name); console.log('PASS ' + name); };

// The installed std inputs carry DWARF and must stay byte-identical across all consumers.
const stdInputs = [find(['libcangjie-std-collection.a']), find(['libcangjie-std-collection.so'])];
const before = Object.fromEntries(stdInputs.map(file => [file, sha256(file)]));
check('std inputs carry DWARF', () => {
  for (const file of stdInputs) {
    const debug = new Set(debugSections(file));
    assert.ok(debug.has('.debug_info') && debug.has('.debug_line'), file + ' has no DWARF: ' + [...debug]);
  }
});

const src = path.join(work, 'src');
fs.mkdirSync(src);
fs.writeFileSync(path.join(src, 'main.cj'), [
  'import std.collection.HashMap', '',
  'func appCount(n: Int64): Int64 {',
  '    let m = HashMap<Int64, Int64>()',
  '    for (i in 0..n) { m.add(i % 97, i) }',
  '    return m.size',
  '}', '',
  'main(): Int64 {',
  '    println("count=${appCount(1000)}")',
  '    return 0',
  '}', ''].join('\n'));
fs.writeFileSync(path.join(src, 'lib.cj'), [
  'package demo', 'import std.collection.HashMap', '',
  'public func demoCount(n: Int64): Int64 {',
  '    let m = HashMap<Int64, Int64>()',
  '    for (i in 0..n) { m.add(i % 13, i) }',
  '    return m.size',
  '}', ''].join('\n'));

const build = (name, args) => {
  const dir = path.join(work, name);
  fs.mkdirSync(dir);
  ok([cjc, ...args, '-o', path.join(dir, args.includes('--output-type=dylib') ? 'libdemo.so'
    : args.includes('--output-type=staticlib') ? 'libdemo.a' : 'app')], {cwd: dir});
  return dir;
};
const runApp = dir => {
  const r = ok([path.join(dir, 'app')], {cwd: dir, env: {...process.env, LD_LIBRARY_PATH: path.join(home, 'runtime/lib', tuple)}});
  assert.equal(r.stdout.trim(), 'count=97');
};
const symbolAddress = (file, pattern) => {
  const rows = ok(['nm', '--defined-only', file]).stdout.split('\n')
    .map(line => line.match(/^([0-9a-f]+)\s+[tTwW]\s+(.*)$/)).filter(Boolean);
  const row = rows.find(([, , name]) => pattern.test(name)) ?? assert.fail(`no symbol ${pattern} in ${file}`);
  return '0x' + row[1];
};
const lineOf = (file, address) => ok([symbolizer, '--obj=' + file, address]).stdout.split('\n')[1] || '';
const main = path.join(src, 'main.cj'), lib = path.join(src, 'lib.cj');

// Independent -g controls first: an implementation that drops DWARF unconditionally fails here.
const staticG = build('static-g', ['-g', '--static-std', '-O2', main]);
const dynG = build('dyn-g', ['-g', '--dy-std', '-O2', main]);
const dylibG = build('dylib-g', ['-g', '--output-type=dylib', '-O2', lib]);
const archiveG = build('archive-g', ['-g', '--output-type=staticlib', '-O2', lib]);
check('-g executable keeps application and std DWARF', () => {
  const app = path.join(staticG, 'app');
  assert.ok(debugSections(app).includes('.debug_info') && debugSections(app).includes('.debug_line'));
  runApp(staticG);
  assert.match(lineOf(app, symbolAddress(app, /appCount/)), /main\.cj:\d+/);
  // println is non-generic std.core code, so its line can only come from the std archive's DWARF.
  assert.match(lineOf(app, symbolAddress(app, /println/)), /core\/[^:]*\.cj:[1-9]\d*/);
});
check('-g dynamic-std executable keeps DWARF and runs', () => {
  assert.ok(debugSections(path.join(dynG, 'app')).includes('.debug_info'));
  runApp(dynG);
});
check('-g shared library keeps DWARF', () => {
  const so = path.join(dylibG, 'libdemo.so');
  assert.ok(debugSections(so).includes('.debug_info'));
  assert.match(lineOf(so, symbolAddress(so, /demoCount/)), /lib\.cj:\d+/);
});
check('-g static archive stays a DWARF-bearing reusable input', () => {
  assert.ok(debugSections(path.join(archiveG, 'libdemo.a')).includes('.debug_info'));
});

// Same invocations without -g: no DWARF reaches final outputs, from the application or std.
const staticN = build('static-nog', ['--static-std', '-O2', main]);
const dynN = build('dyn-nog', ['--dy-std', '-O2', main]);
const dylibN = build('dylib-nog', ['--output-type=dylib', '-O2', lib]);
check('executable without -g has no DWARF, keeps symbols and unwind, and runs', () => {
  for (const dir of [staticN, dynN]) {
    const app = path.join(dir, 'app'), names = sections(app);
    assert.deepEqual(debugSections(app), [], app + ' still carries DWARF');
    for (const kept of ['.symtab', '.eh_frame', '.dynsym', '.text']) assert.ok(names.includes(kept), app + ' lost ' + kept);
    assert.ok(names.some(name => name.startsWith('.cjmetadata')), app + ' lost Cangjie metadata');
    symbolAddress(app, /appCount/);
    runApp(dir);
  }
});
check('shared library without -g has no DWARF and keeps its exports', () => {
  const so = path.join(dylibN, 'libdemo.so');
  assert.deepEqual(debugSections(so), [], so + ' still carries DWARF');
  assert.match(ok(['nm', '-D', '--defined-only', so]).stdout, /demoCount/);
});
check('std inputs unchanged by every consumer', () => {
  for (const file of stdInputs) assert.equal(sha256(file), before[file], file + ' changed');
});
fs.writeFileSync(path.join(work, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log('OUTPUT_DEBUG_POLICY_PASS ' + report.checks.length);
