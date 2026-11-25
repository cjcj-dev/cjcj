import {putLlvmFolders, putLlvmWindowsFixes} from './fixtures/windows-llvm-source.mjs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {buildConfig} from '../lib/config.mjs';
import {getBuildTarget} from '../lib/build-target.mjs';
import {prepareLldbSwigPython3Source, prepareWindowsLlvmSource, run as fetchRun} from '../srcbuild/stages/fetch.mjs';
import {BuildError} from '../lib/errors.mjs';
import {applyTextPatch} from '../srcbuild/stages/common.mjs';

for (const [label, eol] of [['LF', '\n'], ['CRLF', '\r\n']]) {
  test('Windows LLVM folder declarations preserve the anchor and ' + label, t => {
    const root = tempTree(t), folders = putLlvmFolders(root, eol), fixes = putLlvmWindowsFixes(root, eol);
    prepareWindowsLlvmSource(root);
    for (const {file, expected} of folders) {
      assert.deepEqual(fs.readFileSync(file), Buffer.from(expected), file);
      assertNoRewrite(file, () => prepareWindowsLlvmSource(root));
    }
    for (const {file, expected} of fixes) {
      assert.deepEqual(fs.readFileSync(file), Buffer.from(expected), file);
      assertNoRewrite(file, () => prepareWindowsLlvmSource(root));
    }
  });
}

test('Windows LLVM preparation rejects a changed, ambiguous or missing folder declaration', t => {
  const root = tempTree(t);
  putLlvmWindowsFixes(root);
  for (const {file, original, expected} of putLlvmFolders(root)) {
    for (const drift of [original.replace('virtual void', 'void'), expected.replace('anchor()', 'anchor(int)'),
      original + expected]) {
      fs.writeFileSync(file, drift);
      assert.throws(() => prepareWindowsLlvmSource(root),
        error => error instanceof BuildError && error.message.includes('patch shape drift') && error.message.includes(file));
      assert.equal(fs.readFileSync(file, 'utf8'), drift);
    }
    fs.unlinkSync(file);
    assert.throws(() => prepareWindowsLlvmSource(root),
      error => error instanceof BuildError && error.message.includes('required file missing') && error.message.includes(file));
    fs.writeFileSync(file, original);
  }
});

test('Windows LLVM preparation rejects each new edit when its shape drifts, including mixed forms', t => {
  const root = tempTree(t);
  const folders = putLlvmFolders(root), fixes = putLlvmWindowsFixes(root);
  for (const {file, original} of fixes) {
    fs.unlinkSync(file);
    assert.throws(() => prepareWindowsLlvmSource(root),
      error => error instanceof BuildError && error.message.includes('required file missing') && error.message.includes(file));
    console.log(`WINDOWS_LLVM_NEW_MISSING_RED file=${file}`);
    fs.writeFileSync(file, original);
  }
  const drifted = [
    fixes[0].original.replace('#include <utility>', '#include <string>'),
    fixes[1].original.replace('{{ClBlacklist}}', '{ClBlacklist.getValue()}'),
    fixes[2].original.replace('basic_string<uint8_t>', 'string<uint8_t>'),
  ];
  for (let i = 0; i < fixes.length; i++) {
    fs.writeFileSync(fixes[i].file, drifted[i]);
    assert.throws(() => prepareWindowsLlvmSource(root),
      error => error instanceof BuildError && error.message.includes('patch shape drift') && error.message.includes(fixes[i].file));
    for (const {file, expected} of folders) assert.equal(fs.readFileSync(file, 'utf8'), expected);
    console.log(`WINDOWS_LLVM_NEW_CUT_RED file=${fixes[i].file} folders=green`);
    assert.equal(fs.readFileSync(fixes[i].file, 'utf8'), drifted[i]);
    fs.writeFileSync(fixes[i].file, fixes[i].original);
  }
  // A partially applied sancov pair is specifically rejected as mixed old/new.
  fs.writeFileSync(fixes[1].file, fixes[1].expected.replace('ClIgnorelist.getValue()', 'ClIgnorelist'));
  assert.throws(() => prepareWindowsLlvmSource(root),
    error => error instanceof BuildError && error.message.includes('patch shape drift') && error.message.includes(fixes[1].file));
  for (const {file, expected} of folders) assert.equal(fs.readFileSync(file, 'utf8'), expected);
  console.log(`WINDOWS_LLVM_NEW_MIXED_CUT_RED file=${fixes[1].file} folders=green`);
  for (const {file, expected} of folders) {
    // Folder edits are independent and still remain a valid control once the
    // new-file cut is restored.
    fs.writeFileSync(file, expected);
  }
  for (const {file, original} of fixes) fs.writeFileSync(file, original);
  prepareWindowsLlvmSource(root);
  for (const {file, expected} of folders) assert.equal(fs.readFileSync(file, 'utf8'), expected);
  for (const {file, expected} of fixes) assert.equal(fs.readFileSync(file, 'utf8'), expected);
  console.log('WINDOWS_LLVM_NEW_CUT_RECOVERED all=green');
});

test('Windows fetch keeps the compiler checkout clean and prepares only the nested LLVM checkout', async t => {
  const workspace = tempTree(t), compiler = path.join(workspace, 'cangjie_compiler');
  fs.mkdirSync(path.join(compiler, 'schema'), {recursive: true});
  fs.writeFileSync(path.join(compiler, 'schema/CMakeLists.txt'), '# pinned schema\n');
  fs.writeFileSync(path.join(compiler, '.gitignore'), '/third_party/llvm-project/\n');
  const llvm = path.join(compiler, 'third_party/llvm-project');
  const files = [...putLlvmFolders(llvm), ...putLlvmWindowsFixes(llvm)];
  function git(dir, ...args) {
    const r = spawnSync('git', ['-C', dir, ...args], {encoding: 'utf8'});
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim();
  }
  const repoOverrides = {};
  for (const [name, dir] of Object.entries({compiler, llvm, tools: path.join(workspace, 'cjcj-tools'),
    stdx: path.join(workspace, 'cangjie_stdx'), runtime: path.join(workspace, 'cangjie_runtime')})) {
    fs.mkdirSync(dir, {recursive: true});
    git(dir, 'init', '-q');
    git(dir, 'add', '.');
    git(dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-qm', 'fixture');
    repoOverrides[name] = {url: dir, tag: git(dir, 'rev-parse', 'HEAD')};
  }
  const config = {...buildConfig({workspace, buildRoot: workspace, targetKey: 'windows-x64', repoOverrides}),
    target: getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64'})};
  for (let pass = 0; pass < 2; pass++) {
    await fetchRun(config);
    assert.equal(git(compiler, 'status', '--porcelain'), '');
    for (const {file, expected} of files) assert.equal(fs.readFileSync(file, 'utf8'), expected, file);
  }
});

function tempTree(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-eol-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  return root;
}
const withEol = (text, eol) => text.replace(/\r?\n/g, eol);

function assertNoRewrite(file, repeat) {
  const before = fs.readFileSync(file);
  fs.utimesSync(file, 1000000000, 1000000000);
  const timestamp = fs.statSync(file).mtimeMs;
  repeat();
  assert.deepEqual(fs.readFileSync(file), before);
  assert.equal(fs.statSync(file).mtimeMs, timestamp, 'marker must skip the write');
}

test('applyTextPatch preserves CRLF and skips an already applied multiline marker', t => {
  const file = path.join(tempTree(t), 'input');
  fs.writeFileSync(file, 'before\r\nfirst\r\nsecond\r\nafter');
  const apply = () => applyTextPatch(file, [['first\nsecond', 'one\r\ntwo']], {stage: 'example', marker: 'one\ntwo'});
  apply();
  assert.equal(fs.readFileSync(file, 'utf8'), 'before\r\none\r\ntwo\r\nafter');
  assertNoRewrite(file, apply);

  fs.writeFileSync(file, 'first\nsecond\n');
  const fromCrlf = () => applyTextPatch(file, [['first\r\nsecond', 'one\r\ntwo']], {marker: 'one\r\ntwo'});
  fromCrlf();
  assert.equal(fs.readFileSync(file, 'utf8'), 'one\ntwo\n');
  assertNoRewrite(file, fromCrlf);
});

for (const [name, oldText, before, after] of [
  ['LF span', 'first\nsecond', 'before\r\nfirst\nsecond\nafter\n', 'before\r\none\ntwo\nafter\n'],
  ['CRLF span', 'first\nsecond', 'before\nfirst\r\nsecond\r\nafter\n', 'before\none\r\ntwo\r\nafter\n'],
  ['single line with mostly LF', 'first', 'before\r\nfirst\nsecond\nafter\n', 'before\r\none\ntwo\nsecond\nafter\n'],
]) {
  test('applyTextPatch preserves untouched bytes: ' + name, t => {
    const file = path.join(tempTree(t), 'input');
    fs.writeFileSync(file, before);
    const apply = () => applyTextPatch(file, [[oldText, 'one\ntwo']], {marker: 'one\ntwo'});
    apply();
    assert.deepEqual(fs.readFileSync(file), Buffer.from(after));
    assertNoRewrite(file, apply);
  });
}

test('applyTextPatch splices UTF-8 edits without decoding surrounding bytes', t => {
  const file = path.join(tempTree(t), 'input');
  const prefix = Buffer.from([0xff, 0x0a]);
  fs.writeFileSync(file, Buffer.concat([prefix, Buffer.from('été[0]\r\nfin\n')]));
  applyTextPatch(file, [['été[0]\nfin', 'à $&\nfin']]);
  assert.deepEqual(fs.readFileSync(file), Buffer.concat([prefix, Buffer.from('à $&\r\nfin\n')]));
});

test('applyTextPatch rejects CRLF source drift without writing a partial edit', t => {
  const file = path.join(tempTree(t), 'input');
  fs.writeFileSync(file, 'first\r\nchanged\r\n');
  const missing = 'second\nthird';
  assert.throws(() => applyTextPatch(file, [['first', 'done'], [missing, 'last']], {stage: 'drift'}),
    {name: 'BuildError', message: '[drift] patch shape drift: ' + JSON.stringify(missing) + ' not found in ' + file});
  assert.equal(fs.readFileSync(file, 'utf8'), 'first\r\nchanged\r\n');
});

test('LLDB preparation patches synthetic CRLF SWIG typemaps exactly once', t => {
  const root = tempTree(t), file = path.join(root, 'lldb/bindings/python/python-typemaps.swig');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  const sizeCheck = '  if (!PyInt_Check($input)) {\n  $2 = PyInt_AsLong($input);\n  if ($2 <= 0) {';
  const fixture = [
    sizeCheck, '// second size argument', sizeCheck,
    '  if (PyInt_Check($input)) {', '    $2 = PyInt_AsLong($input);', '  } else if (PyLong_Check($input)) {',
    '    PyObject *item = PyInt_FromLong($1[j]);',
    'bool SetNumberFromPyObject(T &number, PyObject *obj) {',
    '  if (PyInt_Check(obj))', '    number = static_cast<T>(PyInt_AsLong(obj));',
    '  else if (PyLong_Check(obj))', '    number = PyLongAsT<T>(obj);', '',
  ].join('\n');
  assert.equal(fixture.match(/\bPyInt_/g).length, 9);
  fs.writeFileSync(file, withEol(fixture, '\r\n'));
  prepareLldbSwigPython3Source(root);
  const text = fs.readFileSync(file, 'utf8');
  assert.doesNotMatch(text, /\bPy(Int|String|File)_/);
  assert.match(text, /PyLong_Check\(obj\)\)\r\n    number = PyLongAsT<T>/);
  assert.equal(text, withEol(text, '\r\n'));
  assertNoRewrite(file, () => prepareLldbSwigPython3Source(root));
});
