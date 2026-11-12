#!/usr/bin/env node
// Consumers for the 1112 upstream compiler backports. Usage: run.mjs <cjcj-compiler> <sdk> <out-dir>
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [compiler, sdk, out] = process.argv.slice(2);
if (!compiler || !sdk || !out) throw Error('usage: run.mjs <compiler> <sdk> <out>');
const fixtures = import.meta.dirname;
fs.mkdirSync(out, {recursive: true});
const runtimeLib = process.env.CJCJ_PRIVATE_RUNTIME_LIB ?? sdk + '/runtime/lib/linux_x86_64_cjnative';
const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_PATH: sdk + '/modules/linux_x86_64_cjnative',
  LD_LIBRARY_PATH: [runtimeLib, ...['lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib'].map(p => sdk + '/' + p)].join(':')};
const sha = p => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const result = {compiler, compilerSHA256: sha(compiler), sdk, cases: [], assertions: [], rc: 0};
function run(label, args, cwd = out) {
  fs.mkdirSync(cwd, {recursive: true});
  const p = spawnSync(args[0], args.slice(1), {cwd, env, encoding: 'utf8', timeout: 300000});
  const text = (p.stdout ?? '') + (p.stderr ?? '');
  fs.writeFileSync(path.join(out, label + '.log'), text);
  result.cases.push({label, args, cwd, rc: p.status, signal: p.signal, error: p.error?.message});
  return {rc: p.status, text};
}
function check(name, passed) { result.assertions.push({name, passed}); if (!passed) result.rc = 1; console.log(name + ' ' + (passed ? 'PASS' : 'FAIL')); }
function chirCount(dir, needle) {
  const files = [];
  const walk = d => { for (const e of fs.readdirSync(d, {withFileTypes: true})) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (p.endsWith('.chir')) files.push(p); } };
  walk(dir);
  if (files.length === 0) return {files: 0, count: -1};
  files.sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs);
  const last = fs.readFileSync(files.at(-1), 'utf8');
  return {files: files.length, last: files.at(-1), count: last.split(needle).length - 1};
}
// !2359
{
  const elf = path.join(out, 'tuple_wildcard');
  const c = run('tuple_wildcard.compile', [compiler, path.join(fixtures, 'tuple_wildcard.cj'), '--diagnostic-format=noColor', '-o', elf]);
  check('tuple_wildcard.compile', c.rc === 0 && !/exhaustive/i.test(c.text));
  if (c.rc === 0) { const r = run('tuple_wildcard.run', [elf]); check('tuple_wildcard.runtime', r.rc === 0 && r.text.includes('TUPLE_WILDCARD_OK')); }
}
// !2344: same source, the O2 final CHIR keeps fewer getOrThrow calls than O0, and both run correctly.
{
  const counts = {};
  for (const level of ['O0', 'O2']) {
    const dir = path.join(out, 'getorthrow-' + level);
    const elf = path.join(dir, 'getorthrow');
    const c = run('getorthrow.' + level + '.compile', [compiler, path.join(fixtures, 'getorthrow.cj'), '-' + level, '--dump-chir', '--diagnostic-format=noColor', '-o', elf], dir);
    check('getorthrow.' + level + '.compile', c.rc === 0);
    if (c.rc !== 0) continue;
    const r = run('getorthrow.' + level + '.run', [elf], dir);
    check('getorthrow.' + level + '.runtime', r.rc === 0 && r.text.includes('GET_OR_THROW_OK'));
    counts[level] = chirCount(dir, 'getOrThrow');
  }
  result.getOrThrowCounts = counts;
  check('getorthrow.chir-dump-present', (counts.O0?.count ?? -1) > 0 && (counts.O2?.count ?? -1) >= 0);
  check('getorthrow.o2-eliminates', (counts.O2?.count ?? 1e9) < (counts.O0?.count ?? -1));
}
fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(result, null, 2));
process.exit(result.rc);
