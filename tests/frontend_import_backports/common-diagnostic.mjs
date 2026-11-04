#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const [compiler, output] = process.argv.slice(2);
assert(path.isAbsolute(compiler) && path.isAbsolute(output));
fs.mkdirSync(output, {recursive: true});
const targets = [];
function check(name, body) {
  try { body(); targets.push({name, passed: true}); console.log('PASS ' + name); }
  catch (error) { targets.push({name, passed: false, error: error.message}); console.log('FAIL ' + name + ': ' + error.message); }
}
function source(name, text) {
  const file = path.join(output, name);
  fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text); return file;
}
function directory(name) { const dir = path.join(output, name); fs.mkdirSync(dir, {recursive: true}); return dir; }
function run(name, args, expected = 0) {
  const argv = [compiler, ...args, '--jobs', '8', '--diagnostic-format=noColor'];
  const r = spawnSync(argv[0], argv.slice(1), {cwd: output, encoding: 'utf8'});
  const log = (r.stdout ?? '') + (r.stderr ?? '');
  fs.writeFileSync(path.join(output, name + '.log'), log);
  fs.writeFileSync(path.join(output, name + '.json'), JSON.stringify({argv, rc: r.status, signal: r.signal, error: r.error?.message}, null, 2));
  assert.equal(r.status, expected, name + ' child rc: ' + log); return log;
}
const dep = source('dependency/dep.cj', 'package dependency\npublic func value(): Int64 { 1 }\n');
const depout = directory('depout');
run('dependency', [dep, '--output-type=staticlib', '-o', depout + '/']);
const a = source('common/a.cj', 'package commonfixture\nimport dependency.value\npublic common func left(): Int64\n');
// An alias in a desugared multi-import has its own serialized item range.
// It cannot be reconstructed by adding name lengths to the import keyword.
const b = source('common/b.cj', 'package commonfixture\n// distinct source line and indentation\n  import dependency.{\n    value as renamed\n  }\npublic common func right(): Int64\n');
const commonout = directory('commonout');
run('common-producer', [a, b, '--experimental', '--output-type=chir', '--import-path', depout, '-o', commonout + '/']);
const specific = source('specific/main.cj', 'package commonfixture\npublic specific func left(): Int64 { 1 }\npublic specific func right(): Int64 { 2 }\n');
const commonArgs = [specific, '--experimental', '--output-type=chir', '--common-part-cjo', commonout + '/commonfixture.cjo', '--common-part-chir', commonout + '/commonfixture.chir', '--import-path', depout, '-o', directory('specificout') + '/'];
run('specific-positive', commonArgs);
check('COMMON_SPECIFIC_POSITIVE', () => {});
const ordinary = source('ordinary/lib.cj', 'package ordinaryfixture\nimport std.math.*\npublic func value(): Int64 { 3 }\n');
const ordinaryout = directory('ordinaryout');
run('ordinary-producer', [ordinary, '--output-type=staticlib', '-o', ordinaryout + '/']);
const use = source('ordinary-use/main.cj', 'package ordinaryuse\nimport ordinaryfixture.value\npublic func use(): Int64 { value() }\n');
const ordinaryArgs = [use, '--experimental', '--output-type=chir', '--import-path', ordinaryout, '-o', directory('useout') + '/'];
run('ordinary-positive', ordinaryArgs);
check('ORDINARY_CJO_POSITIVE', () => {});
fs.copyFileSync(dep, path.join(output, 'dependency-original.cj'));
fs.copyFileSync(depout + '/dependency.cjo', path.join(output, 'dependency-original.cjo'));
fs.writeFileSync(dep, 'package dependency\npublic func replacement(): Int64 { 1 }\n');
run('dependency-api-change', [dep, '--output-type=staticlib', '-o', depout + '/']);
const diagnostic = run('common-missing-decl', commonArgs, 1);
check('COMMON_MISSING_DECL_DIAGNOSTIC', () => {
  assert.doesNotMatch(diagnostic, /Exception|stack trace/);
  assert.equal((diagnostic.match(/can not find.*value.*package.*dependency/g) ?? []).length, 2);
});
for (const [name, coordinate] of [['a', 'a.cj:2:1'], ['b', 'b.cj:4:5']]) {
  check('COMMON_EXACT_COORDINATE_' + name, () => assert(diagnostic.includes(coordinate), diagnostic));
}
// A parsed source still diagnoses the prefix token at column 8, not the
// serialized whole-spec fallback at column 1.
const direct = source('direct/main.cj', 'package directuse\nimport dependency.value\npublic func use(): Int64 { 1 }\n');
const directLog = run('source-missing-decl', [direct, '--experimental', '--output-type=chir', '--import-path', depout, '-o', directory('directout') + '/'], 1);
check('SOURCE_TOKEN_COORDINATE_CONTROL', () => { assert(directLog.includes('main.cj:2:8'), directLog); assert.doesNotMatch(directLog, /Exception/); });
run('ordinary-after-decl-change', ordinaryArgs);
check('ORDINARY_CJO_AFTER_DECL_CHANGE', () => {});
fs.renameSync(depout + '/dependency.cjo', depout + '/dependency.cjo.hidden');
const missingPackage = run('common-missing-package', commonArgs, 1);
check('COMMON_MISSING_PACKAGE_DIAGNOSTIC', () => { assert.match(missingPackage, /can not find package dependency/); assert.doesNotMatch(missingPackage, /Exception/); });
for (const [name, coordinate] of [['a', 'a.cj:2:1'], ['b', 'b.cj:4:5']]) {
  check('COMMON_MISSING_PACKAGE_COORDINATE_' + name, () => assert(missingPackage.includes(coordinate), missingPackage));
}
fs.writeFileSync(path.join(output, 'targets.json'), JSON.stringify(targets, null, 2));
process.exit(targets.every(t => t.passed) ? 0 : 1);
