#!/usr/bin/env zx
// Real scan/CJO/link regression; use a compiler and its matching installed SDK.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [compiler, workArg, targetLd] = process.argv.slice(2);
assert.ok(compiler && path.isAbsolute(compiler) && workArg && targetLd,
  'usage: zx ci/test-std-dependency-closure.mjs ABS_COMPILER NEW_WORK TARGET_LD; set paired compiler environment');
const work = path.resolve(workArg);
assert.ok(!fs.existsSync(work), 'use new evidence, preserving first failures');
fs.mkdirSync(work, {recursive: true});
const records = [];
function run(name, argv, env = process.env) {
  const started = new Date().toISOString();
  const out = fs.openSync(path.join(work, name + '.stdout'), 'wx');
  const err = fs.openSync(path.join(work, name + '.stderr'), 'wx');
  const p = spawnSync(argv[0], argv.slice(1), {cwd: work, env,
    stdio: ['ignore', out, err], timeout: 300000});
  fs.closeSync(out); fs.closeSync(err);
  records.push({name, argv, cwd: work, started, ended: new Date().toISOString(),
    pid: p.pid, rc: p.status, signal: p.signal, error: p.error?.message ?? null});
  fs.writeFileSync(path.join(work, 'commands.json'), JSON.stringify(records, null, 2) + '\n');
  assert.equal(p.error, undefined, name); assert.equal(p.signal, null, name); assert.equal(p.status, 0, name);
  return fs.readFileSync(path.join(work, name + '.stdout'), 'utf8');
}
function descriptor(text) {
  const value = JSON.parse(text);
  const found = [];
  function visit(v) {
    if (!v || typeof v !== 'object') return;
    if (v.package === 'stddepfixture' && Array.isArray(v['std-dependencies'])) found.push(v);
    else for (const child of Object.values(v)) visit(child);
  }
  visit(value);
  assert.equal(found.length, 1, 'one real package descriptor');
  return found[0];
}
function checkDependencies(info, directPrivateImport) {
  const graph = Object.assign({}, ...info['std-dependencies']);
  assert.ok(Object.hasOwn(graph, 'std.ast'), 'retain the real std.ast library');
  assert.ok(Object.hasOwn(graph, 'std.core'), 'retain transitive std dependencies');
  assert.ok(!Object.hasOwn(graph, 'flatbuffers'), 'private support is not a std library node');
  for (const edges of Object.values(graph)) assert.ok(!edges.includes('flatbuffers'), 'no private support std edge');
  if (directPrivateImport) {
    assert.equal(info.dependencies.find(d => d.package === 'flatbuffers')?.isStd, false,
      'an explicit non-std import must still be reported by the scanner');
  } else {
    assert.ok(!info.dependencies.some(d => d.package === 'flatbuffers'),
      'the public std.ast consumer has no direct private support import');
  }
}
const sourceDir = path.join(work, 'source');
fs.mkdirSync(sourceDir);
const source = path.join(sourceDir, 'main.cj');
// Private flatbuffers is available to dependency scanning, but its symbols are
// hidden inside std.ast.so. A public executable must import std.ast, not its
// private support package. Keep that scanner classification control separate.
const scanDir = path.join(work, 'direct-import');
fs.mkdirSync(scanDir);
fs.writeFileSync(path.join(scanDir, 'main.cj'),
  'package stddepfixture\nimport std.ast.*\nimport flatbuffers.*\nmain() {}\n');
fs.writeFileSync(source, `package stddepfixture
import std.ast.*
main(): Int64 {
    let token = Token(TokenKind.IDENTIFIER, "closure")
    let bytes = token.toBytes()
    if (token.value != "closure" || bytes.size <= 7) { return 2 }
    let parsed = parseExpr(Tokens([Token(TokenKind.INTEGER_LITERAL, "42")]))
    let tokens = parsed.toTokens()
    if (tokens.size != 1 || tokens[0].value != "42") { return 3 }
    println("STD_AST_PRIVATE_SUPPORT_LINKED")
    return 0
}
`);
checkDependencies(descriptor(run('source-scan', [compiler, '-p', scanDir, '--scan-dependency'])), true);
const exe = path.join(work, 'stddepfixture');
const map = path.join(work, 'link.map');
run('compile', [compiler, source, '-O0', '--link-options', '-Map=' + map, '-o', exe]);
const cjo = path.join(work, 'stddepfixture.cjo');
assert.ok(fs.existsSync(cjo), 'normal compiler exports the package CJO');
checkDependencies(descriptor(run('cjo-scan', [compiler, cjo, '--scan-dependency'])), false);
const linkMap = fs.readFileSync(map, 'utf8');
assert.match(linkMap, /libcangjie-std-ast\.so/,
  'normal Linux std.ast selection is shared, including its private support');
const targetLib = targetLd.split(path.delimiter).find(dir => fs.existsSync(path.join(dir, 'libcangjie-std-ast.so')));
assert.ok(targetLib, 'the matching target std.ast is installed');
const table = run('std-ast-dynamic', ['readelf', '-d', path.join(targetLib, 'libcangjie-std-ast.so')]);
assert.ok(!table.split('\n').some(line => line.includes('NEEDED') && line.includes('flatbuffers')),
  'private flatbuffers is embedded, not an unresolved separate DSO dependency');
assert.ok(!linkMap.includes('libcangjie-std-flatbuffers'), 'no invented link library');
assert.match(run('target', [exe], {...process.env, LD_LIBRARY_PATH: targetLd, LD_DEBUG: 'files'}),
  /STD_AST_PRIVATE_SUPPORT_LINKED/);
const loader = fs.readFileSync(path.join(work, 'target.stderr'), 'utf8');
assert.ok(loader.includes('calling init: ' + path.join(targetLib, 'libcangjie-std-ast.so')),
  'actual target loads the selected installed std.ast');
console.log('STD_DEPENDENCY_CLOSURE source/cjo/direct-nonstd/std-ast-flatbuffers/target PASS');
