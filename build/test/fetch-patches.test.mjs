import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {buildConfig, saveSourceSelection} from '../lib/config.mjs';
import {getBuildTarget} from '../lib/build-target.mjs';
import {applyCompilerBoundscheckDependencies, applyCompilerCjdbPatches, applyCompilerLlvmVersion, applyCompilerSchemaInstall,
  applyCompilerWindowsPatches, applyCompilerXml2Install, applyNativeCjdbConfigure, prepareLldbSwigPython3Source, run as fetchRun, verifyCompilerCjdbPatches} from '../srcbuild/stages/fetch.mjs';
import {assertCompilerLibcxxEdits, libcxxEdits} from './fixtures/windows-compiler-libcxx.mjs';
import {applyTextPatch} from '../srcbuild/stages/common.mjs';

const BUILD_CJDB = [
  'cmake_policy(SET CMP0114 NEW)',
  'externalproject_get_property(cjnative BINARY_DIR)',
  'set(LLVM_GC_BINARY_DIR "${BINARY_DIR}")',
  'ExternalProject_Add(',
  '    lldb',
  '    USES_TERMINAL_BUILD ON',
  '    DEPENDS cjnative',
  '    STEP_TARGETS build configure)',
  '',
].join('\n');
const SRC_CMAKE = [
  'if(CANGJIE_BUILD_CJDB)',
  '    add_dependencies(lldb cangjie-frontend)',
  '    if(TARGET lldb-build)',
  '        add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  '    endif()',
  'endif()',
  '',
].join('\n');
const REQUIREMENTS = [
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), 'cmake_policy(SET CMP0114 NEW)'],
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), 'STEP_TARGETS build configure'],
  [path.join('src', 'CMakeLists.txt'), 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)'],
];

const PIN_FIXTURE = path.join(import.meta.dirname, 'fixtures', 'compiler-174db8f');
const SCHEMA_PIN_FIXTURE = path.join(import.meta.dirname, 'fixtures', 'compiler-41b223-schema', 'schema');
const WINDOWS_PIN_FIXTURE = path.join(import.meta.dirname, 'fixtures', 'compiler-41b223-windows');
const PATCHED_SHA = {
  buildCjdb: 'd2cb7d2cb6f236ed1ac072c817743e3164adf7a71bc481aa604b88e094a8cabc',
  srcCmake: 'b98e018704f2f8b04688c0e9385e9f655e164e407900e16554225edec017d3f4',
};

function sha256(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function copyPinFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-cjdb-pin-'));
  fs.cpSync(PIN_FIXTURE, root, {recursive: true});
  return root;
}

function makeCompilerFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-cjdb-patches-'));
  for (const [relativePath, contents] of [
    [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), BUILD_CJDB],
    [path.join('src', 'CMakeLists.txt'), SRC_CMAKE],
  ]) {
    const file = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, contents);
  }
  return root;
}

test('Windows fetch preserves selected native compilers and normal runtime installation on canonical source', async () => {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'windows-canonical-fetch-'));
  const compiler = path.join(workspace, 'cangjie_compiler');
  try {
    fs.cpSync(WINDOWS_PIN_FIXTURE, compiler, {recursive: true});
    fs.cpSync(SCHEMA_PIN_FIXTURE, path.join(compiler, 'schema'), {recursive: true});
    const schema = path.join(compiler, 'schema/CMakeLists.txt');
    fs.writeFileSync(schema, withEol(fs.readFileSync(schema, 'utf8'), '\r\n'));
    const xml2 = path.join(compiler, 'third_party/cmake/Xml2.cmake');
    fs.writeFileSync(xml2, withEol(fs.readFileSync(xml2, 'utf8'), '\r\n'));
    fs.writeFileSync(path.join(compiler, '.gitattributes'), 'third_party/CMakeLists.txt text eol=lf\nthird_party/cmake/Xml2.cmake text eol=crlf\n');
    const repoOverrides = {};
    for (const name of ['compiler', 'runtime', 'tools', 'stdx', 'llvm']) {
      const root = path.join(workspace, name === 'llvm' ? 'cangjie_compiler/third_party/llvm-project'
        : name === 'tools' ? 'cjcj-tools' : 'cangjie_' + name);
      fs.mkdirSync(root, {recursive: true});
      const git = (...args) => {
        const r = spawnSync('git', ['-C', root, ...args], {encoding: 'utf8'});
        assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
      };
      git('init', '-q'); git('add', '.');
      git('-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-qm', 'finite canonical CMake fixture');
      repoOverrides[name] = {url: root, tag: git('rev-parse', 'HEAD')};
    }
    const config = {...buildConfig({workspace, buildRoot: workspace + '/tools', targetKey: 'windows-x64', repoOverrides}),
      target: getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64'})};
    const boundsFile = path.join(compiler, 'third_party/CMakeLists.txt');
    const canonicalBounds = fs.readFileSync(boundsFile);
    applyCompilerBoundscheckDependencies(compiler);
    assert.deepEqual(fs.readFileSync(boundsFile), canonicalBounds, 'canonical 41b already has both static bounds dependencies');
    await fetchRun(config);
    assertCompilerLibcxxEdits(compiler);
    assert.match(fs.readFileSync(path.join(compiler, 'demangler/Demangler.h'), 'utf8'),
      /#include <vector>\r?\n#ifndef BUILD_LIB_CANGJIE_DEMANGLE/, 'Windows fetch must expose vector in the library build');
    assert.match(fs.readFileSync(xml2, 'utf8'), /-DCMAKE_CXX_COMPILER=\$\{CMAKE_CXX_COMPILER\}\r\n/);
    assert.match(fs.readFileSync(boundsFile, 'utf8'), /\/InstallWindowsToolchain\.cmake"\)\n/);
    assert.match(fs.readFileSync(schema, 'utf8'), /FLATC_LIBAST_OUTPUTS\}\)\r\ninstall\(FILES/, 'Windows fetch must preserve CRLF around the new install rule');
    assert.equal(fs.readFileSync(boundsFile,'utf8').split('DEPENDS cangjie-demangler boundscheck boundscheck-static)').length-1,2);
    const cmake = (args) => {
      const r = spawnSync('cmake', args, {cwd: workspace, encoding: 'utf8'});
      assert.equal(r.status, 0, r.stdout + r.stderr); return r;
    };
    const script = (name, setup) => {
      const file = workspace + '/' + name + '.cmake', result = workspace + '/' + name + '.txt';
      fs.writeFileSync(file, `${setup}\ninclude("${compiler}/cmake/mingw_x86_64_toolchain.cmake")\nfile(WRITE "${result}" "\${CMAKE_C_COMPILER}\n\${CMAKE_CXX_COMPILER}\n\${LLVM_BUILD_C_COMPILER}\n\${LLVM_BUILD_CXX_COMPILER}")\n`);
      cmake(['-P', file]); return fs.readFileSync(result, 'utf8').split('\n');
    };
    assert.deepEqual(script('default-alias-control', ''), ['x86_64-w64-mingw32-gcc', 'x86_64-w64-mingw32-g++', 'x86_64-w64-mingw32-gcc', 'x86_64-w64-mingw32-g++']);
    console.log('WINDOWS_DEFAULT_ALIAS_CONTROL_REACHED');
    const cc = '/selected compiler/clang.exe', cxx = '/selected compiler/clang++.exe';
    const selected = script('selected', `set(CMAKE_C_COMPILER "${cc}")\nset(CMAKE_CXX_COMPILER "${cxx}")`);
    console.log('WINDOWS_FETCH_COMPILER_TARGET_REACHED ' + JSON.stringify(selected));
    assert.deepEqual(selected, [cc, cxx, cc, cxx]);
    const source = workspace + '/consumer', build = workspace + '/consumer-build', install = workspace + '/installed';
    fs.mkdirSync(source); const dll = source + '/transport.dll';
    fs.writeFileSync(dll, 'finite transport bytes; not a Windows executable');
    fs.writeFileSync(source + '/CMakeLists.txt', `cmake_minimum_required(VERSION 3.20)\nproject(WindowsRuntimeTransport NONE)\nset(WIN32 TRUE)\nset(CANGJIE_TOOLCHAIN_RUNTIME_FILES "${dll}")\ninclude("${compiler}/cmake/modules/InstallWindowsToolchain.cmake")\n`);
    cmake(['-S', source, '-B', build, '-DCMAKE_INSTALL_PREFIX=' + install]); cmake(['--install', build]);
    const manifest = fs.readFileSync(build + '/install_manifest.txt', 'utf8').split('\n');
    for (const directory of ['bin', 'third_party/llvm/bin', 'third_party/flatbuffers/bin']) {
      const file = install + '/' + directory + '/transport.dll';
      assert.ok(manifest.includes(file)); assert.equal(sha256(file), sha256(dll));
    }
    await fetchRun(config);
    assert.deepEqual(script('selected-reentry', `set(CMAKE_C_COMPILER "${cc}")\nset(CMAKE_CXX_COMPILER "${cxx}")`), selected);
  } finally { fs.rmSync(workspace, {recursive: true, force: true}); }
});

test('compiler fork patch verification has positive and per-requirement negative controls', () => {
  const root = makeCompilerFixture();
  try {
    assert.doesNotThrow(() => verifyCompilerCjdbPatches(root));

    for (const [relativePath, requiredText] of REQUIREMENTS) {
      const file = path.join(root, relativePath);
      const patched = fs.readFileSync(file, 'utf8');
      fs.writeFileSync(file, patched.replace(requiredText, ''));
      assert.throws(
        () => verifyCompilerCjdbPatches(root),
        error => error.message.includes(requiredText),
        `missing requirement was accepted: ${requiredText}`,
      );
      fs.writeFileSync(file, patched);
    }
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('pinned 174db8f compiler files pass verify only after fetch run restores the cjdb patch bytes', async () => {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-cjdb-fetch-'));
  try {
    const compilerDir = path.join(workspace, 'cangjie_compiler');
    fs.cpSync(PIN_FIXTURE, compilerDir, {recursive: true});
    fs.cpSync(SCHEMA_PIN_FIXTURE, path.join(compilerDir, 'schema'), {recursive: true});
    for (const dirName of ['cangjie_runtime', 'cjcj-tools', 'cangjie_stdx']) {
      fs.mkdirSync(path.join(workspace, dirName));
    }
    // The fetch entry now checks real repositories before patching. Preserve
    // the fixed 174db file bytes, but identify these small fixture Git objects
    // honestly rather than claiming they are the complete pinned compiler.
    const repoOverrides={};
    for(const name of ['compiler','runtime','tools','stdx','llvm']) {
      const root=path.join(workspace,name==='llvm'?'cangjie_compiler/third_party/llvm-project':name==='tools'?'cjcj-tools':'cangjie_'+name);
      fs.mkdirSync(root,{recursive:true});
      const git=(...args)=>{const r=spawnSync('git',['-C',root,...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
      git('init','-q');git('add','.');
      git('-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','--allow-empty','-qm','finite fetch fixture');
      repoOverrides[name]={url:root,tag:git('rev-parse','HEAD')};
    }
    const config = buildConfig({workspace,buildRoot:path.join(workspace,'buildtools'),
      cangjieVersion:'0.0.1',repoOverrides});
    const cjdb = path.join(config.repoPath('compiler'), 'third_party', 'cmake', 'BuildCJDB.cmake');
    const src = path.join(config.repoPath('compiler'), 'src', 'CMakeLists.txt');
    assert.throws(
      () => verifyCompilerCjdbPatches(config.repoPath('compiler')),
      error => error.message.includes('cmake_policy(SET CMP0114 NEW)'),
    );

    let fetchError = null;
    try {
      await fetchRun(config);
    } catch (error) {
      fetchError = error;
    }

    const cjdbText = fs.readFileSync(cjdb, 'utf8');
    const srcText = fs.readFileSync(src, 'utf8');
    assert.ok(cjdbText.includes('STEP_TARGETS build configure'));
    assert.ok(srcText.includes('add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)'));
    const hasPolicy = cjdbText.includes('cmake_policy(SET CMP0114 NEW)');
    console.log(`TARGET_ASSERT_RAN needle=cmake_policy(SET CMP0114 NEW) observed=${hasPolicy}`);
    assert.equal(hasPolicy, true, 'TARGET cmake_policy(SET CMP0114 NEW) missing after applyCompilerCjdbPatches');
    const cjdbSha = sha256(cjdb);
    const srcSha = sha256(src);
    console.log(`TARGET_ASSERT_RAN cjdb_sha=${cjdbSha} src_sha=${srcSha}`);
    assert.equal(cjdbSha, PATCHED_SHA.buildCjdb);
    assert.equal(srcSha, PATCHED_SHA.srcCmake);
    assert.equal(fetchError, null);
    await fetchRun(config);
    assert.equal(sha256(cjdb), PATCHED_SHA.buildCjdb);
    assert.equal(sha256(src), PATCHED_SHA.srcCmake);
  } finally {
    fs.rmSync(workspace, {recursive: true, force: true});
  }
});

test('apply throws patch shape drift when DEPENDS cjnative shape moves', () => {
  const root = copyPinFixture();
  const cjdb = path.join(root, 'third_party', 'cmake', 'BuildCJDB.cmake');
  try {
    const original = fs.readFileSync(cjdb, 'utf8');
    const drifted = original.replace('DEPENDS cjnative)', 'DEPENDS cjnative_drifted)');
    assert.notEqual(drifted, original);
    fs.writeFileSync(cjdb, drifted);
    console.log('TARGET_ASSERT_RAN needle=patch shape drift');
    assert.throws(
      () => applyCompilerCjdbPatches(root),
      error => error.message.includes('patch shape drift') && error.message.includes('DEPENDS cjnative)'),
      'TARGET patch shape drift was not raised for a moved DEPENDS cjnative)',
    );
    assert.equal(fs.readFileSync(cjdb, 'utf8'), drifted);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

// Exercise the public source selector and existing-source path, not just the
// patch helper. build compiler deliberately bypasses fetch on reentry.
for (const entry of ['fetch', 'build']) test(`public ${entry} restores both static boundscheck producer edges`, () => {
  const evidence=process.env.RELEASE_EVIDENCE_TEST_ROOT;
  if(evidence)fs.mkdirSync(evidence,{recursive:true});
  const workspace = fs.mkdtempSync(path.join(evidence||os.tmpdir(), 'boundscheck-cli-'));
  const commands=[];
  try {
    const compiler = path.join(workspace, 'cangjie_compiler');
    fs.cpSync(PIN_FIXTURE, compiler, {recursive:true});
    fs.cpSync(SCHEMA_PIN_FIXTURE, path.join(compiler, 'schema'), {recursive:true});
    // Deliberately stop at the first actual build.py call: this gate grants
    // source preparation only, never a compiler build or installation.
    fs.writeFileSync(path.join(compiler,'build.py'),"raise SystemExit('BOUNDSCHECK_FINITE_BUILD_BOUNDARY')\n");
    const options=[],repoOverrides={};
    for (const name of ['compiler','runtime','tools','stdx','llvm']) {
      const root=path.join(workspace,name==='llvm'?'cangjie_compiler/third_party/llvm-project':name==='tools'?'cjcj-tools':'cangjie_'+name);
      fs.mkdirSync(root,{recursive:true});
      const git=(...args)=>{const r=spawnSync('git',['-C',root,...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
      git('init','-q');git('add','.');
      git('-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','--allow-empty','-qm','fixed boundscheck fixture');
      const tag=git('rev-parse','HEAD');repoOverrides[name]={url:root,tag};
      options.push('--repo-url',name+'='+root,'--repo-tag',name+'='+tag);
    }
    saveSourceSelection(buildConfig({workspace,buildRoot:workspace+'/buildtools',targetKey:'linux-x64',repoOverrides}));
    const file=path.join(compiler,'third_party/CMakeLists.txt');
    const original=fs.readFileSync(file,'utf8');
    const before='DEPENDS cangjie-demangler boundscheck)';
    const after='DEPENDS cangjie-demangler boundscheck boundscheck-static)';
    assert.equal(original.split(before).length-1,2);
    const expected=original.replaceAll(before,after);
    const cli=new URL('../cli.mjs',import.meta.url).pathname;
    const invoke=()=>{
      const env={...process.env};delete env.CANGJIE_BUILD_DRY_RUN;
      const args=entry==='fetch'?['fetch',...options]:['build','compiler'];
      const argv=[cli,'--workspace',workspace,'--build-root',workspace+'/buildtools','--target','linux-x64','--official-sdk-root',workspace,...args];
      const r=spawnSync(process.execPath,argv,{env,encoding:'utf8'});
      commands.push({argv:[process.execPath,...argv],rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
      fs.writeFileSync(path.join(workspace,'commands.json'),JSON.stringify(commands,null,2));
      assert.equal(r.status,entry==='build'?1:0,r.stdout+r.stderr);
      if(entry==='build')assert.match(r.stderr,/BOUNDSCHECK_FINITE_BUILD_BOUNDARY/);
    };
    invoke();
    console.log('BOUNDSCHECK_PUBLIC_TARGET_REACHED '+entry+' first');
    assert.equal(fs.readFileSync(file,'utf8'),expected);
    invoke();
    assert.equal(fs.readFileSync(file,'utf8'),expected,'warm entry must preserve both edges');
    fs.writeFileSync(file,expected.replace(after,before));
    invoke();
    console.log('BOUNDSCHECK_PUBLIC_TARGET_REACHED '+entry+' partial-restore');
    assert.equal(fs.readFileSync(file,'utf8'),expected);
    if(entry==='fetch')verifyCompilerCjdbPatches(compiler);
  } finally {if(!evidence)fs.rmSync(workspace,{recursive:true,force:true});}
});

test('boundscheck preparation refuses shape drift without rewriting canonical input', () => {
  const root=copyPinFixture();
  try {
    const file=path.join(root,'third_party/CMakeLists.txt');
    const source=fs.readFileSync(file,'utf8').replace('DEPENDS cangjie-demangler boundscheck)','DEPENDS changed-producer)');
    fs.writeFileSync(file,source);
    assert.throws(()=>applyCompilerBoundscheckDependencies(root),/patch shape drift/);
    assert.equal(fs.readFileSync(file,'utf8'),source);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
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

test('native compiler preparation preserves CRLF across configure and install edits', t => {
  const root = tempTree(t);
  const files = ['third_party/cmake/BuildCJDB.cmake', 'src/CMakeLists.txt', 'third_party/CMakeLists.txt', 'schema/CMakeLists.txt'];
  for (const rel of files) {
    const source = rel.startsWith('schema/') ? path.join(SCHEMA_PIN_FIXTURE, 'CMakeLists.txt') : path.join(PIN_FIXTURE, rel);
    fs.mkdirSync(path.dirname(path.join(root, rel)), {recursive: true});
    fs.writeFileSync(path.join(root, rel), withEol(fs.readFileSync(source, 'utf8'), '\r\n'));
  }
  const prepare = () => {
    applyCompilerCjdbPatches(root);
    applyNativeCjdbConfigure(root);
    applyCompilerBoundscheckDependencies(root);
    applyCompilerSchemaInstall(root);
    applyCompilerLlvmVersion(root);
    applyCompilerXml2Install(root);
  };
  prepare();
  verifyCompilerCjdbPatches(root);
  const contents = () => files.map(rel => fs.readFileSync(path.join(root, rel), 'utf8'));
  const first = contents();
  assert.ok(first.every(text => text === withEol(text, '\r\n')));
  assert.match(first[0], /string\(APPEND LLDB_CMAKE_CXX_FLAGS[^\n]+\r\nif\(NOT/);
  assert.match(first[0], /CMAKE_ARGS \$\{LLDB_CMAKE_ARGS\} \$\{CJCJ_LLDB_ARGS\}/);
  assert.equal(first[0].match(/FOLLOW_SYMLINK_CHAIN/g).length, 2);
  assert.equal(first[2].match(/DEPENDS cangjie-demangler boundscheck boundscheck-static\)/g).length, 2);
  assert.ok(first[2].includes('llvm-source-version.mjs'));
  assert.ok(first[3].includes('install(FILES ${FLATC_OUTPUTS} DESTINATION include/flatbuffers)'));
  prepare();
  assert.deepEqual(contents(), first);
});

for (const [target, eol] of [['LF', '\n'], ['CRLF', '\r\n']]) {
  test(`Windows compiler libc++: ${target} edits, reentry, missing files and drift`, t => {
    const root = tempTree(t);
    fs.cpSync(WINDOWS_PIN_FIXTURE, root, {recursive: true});
    const apply = () => applyCompilerWindowsPatches(root);
    const files = libcxxEdits.map(([relative]) => path.join(root, relative));
    for (const file of files) fs.writeFileSync(file, withEol(fs.readFileSync(file, 'utf8'), eol));
    apply();
    assertCompilerLibcxxEdits(root, eol);
    for (const file of files) {
      assertNoRewrite(file, apply);
      const patched = fs.readFileSync(file);
      fs.unlinkSync(file);
      assert.throws(apply, {name: 'BuildError', message: '[fetch.patch.windows] required file missing: ' + file});
      fs.writeFileSync(file, 'unrecognized source' + eol);
      assert.throws(apply, err => err.name === 'BuildError' && err.message.includes('patch shape drift:') && err.message.endsWith(file));
      assert.equal(fs.readFileSync(file, 'utf8'), 'unrecognized source' + eol);
      fs.writeFileSync(file, patched);
    }
  });

  test(`Windows demangler: pinned include guard, ${target} and reentry`, t => {
    const root = tempTree(t);
    fs.cpSync(WINDOWS_PIN_FIXTURE, root, {recursive: true});
    const file = path.join(root, 'demangler/Demangler.h');
    const original = withEol(fs.readFileSync(file, 'utf8'), eol);
    const guard = '#ifndef BUILD_LIB_CANGJIE_DEMANGLE' + eol, vector = '#include <vector>' + eol;
    assert.ok(original.includes(guard + vector), 'fixture must reproduce the guarded vector include');
    fs.writeFileSync(file, original);
    const apply = () => applyCompilerWindowsPatches(root);
    apply();
    assert.equal(fs.readFileSync(file, 'utf8'), original.replace(guard + vector, vector + guard));
    assertNoRewrite(file, apply);

    const drift = original.replace(guard, '#ifndef OTHER_BUILD' + eol);
    fs.writeFileSync(file, drift);
    assert.throws(apply, /patch shape drift:.*Demangler\.h/);
    assert.equal(fs.readFileSync(file, 'utf8'), drift);
  });

  for (const [patchStyle, patchEol] of [['LF', '\n'], ['CRLF', '\r\n']]) {
    test(`Windows Git patch: ${target} compiler, ${patchStyle} patch, forward and reentry`, t => {
      const root = tempTree(t), patch = path.join(root, 'input.patch');
      fs.cpSync(WINDOWS_PIN_FIXTURE, root, {recursive: true});
      const files = ['cmake/mingw_x86_64_toolchain.cmake', 'third_party/CMakeLists.txt', 'third_party/cmake/Xml2.cmake'];
      for (const rel of files) {
        const file = path.join(root, rel);
        fs.writeFileSync(file, withEol(fs.readFileSync(file, 'utf8'), eol));
      }
      const bundled = new URL('../srcbuild/patches/compiler-windows-native.patch', import.meta.url);
      fs.writeFileSync(patch, withEol(fs.readFileSync(bundled, 'utf8'), patchEol));
      const apply = () => applyCompilerWindowsPatches(root, patch);
      apply();
      const installed = path.join(root, 'cmake/modules/InstallWindowsToolchain.cmake');
      const module = fs.readFileSync(installed, 'utf8');
      assert.ok(module.includes('install(FILES'));
      assert.equal(module, withEol(module, '\n'), 'new file defaults to LF');
      for (const rel of files) {
        const text = fs.readFileSync(path.resolve(root, rel), 'utf8');
        assert.equal(text, withEol(text, eol), rel);
      }
      assertNoRewrite(installed, apply);
      fs.writeFileSync(installed, fs.readFileSync(installed, 'utf8').replace('install(FILES', 'changed(FILES'));
      assert.throws(apply, /compiler Windows patch shape drift/);
    });
  }
}

for (const nested of [false, true]) {
  test('Windows Git patch: ' + (nested ? 'nested plain copy' : 'standalone copy') + ' with per-file EOL', t => {
    const parent = tempTree(t), root = path.join(parent, 'compiler');
    if (nested) {
      const init = spawnSync('git', ['init', '-q', parent], {encoding: 'utf8'});
      assert.equal(init.status, 0, init.stderr);
    }
    fs.cpSync(WINDOWS_PIN_FIXTURE, root, {recursive: true});
    const toolchain = path.join(root, 'cmake/mingw_x86_64_toolchain.cmake');
    const thirdParty = path.join(root, 'third_party/CMakeLists.txt');
    const xml = path.join(root, 'third_party/cmake/Xml2.cmake');
    const installed = path.join(root, 'cmake/modules/InstallWindowsToolchain.cmake');
    const apply = () => applyCompilerWindowsPatches(root);
    for (const [file, eol] of [[toolchain, '\r\n'], [thirdParty, '\n'], [xml, '\r\n']]) {
      fs.writeFileSync(file, withEol(fs.readFileSync(file, 'utf8'), eol));
    }
    const originals = [toolchain, thirdParty, xml].map(file => fs.readFileSync(file, 'utf8'));
    const drift = originals[2].replace('-DCUSTOM_WARNING_SETTINGS=-Wno-error', '-DCUSTOM_WARNING_SETTINGS=drift');
    assert.notEqual(drift, originals[2]);
    fs.writeFileSync(xml, drift);
    assert.throws(apply, /compiler Windows patch shape drift/, 'drift in the last section must reject the whole patch');
    assert.deepEqual([toolchain, thirdParty, xml].map(file => fs.readFileSync(file, 'utf8')), [...originals.slice(0, 2), drift]);
    assert.equal(fs.existsSync(installed), false);
    fs.writeFileSync(xml, originals[2]);

    assert.doesNotThrow(apply, 'all four sections must apply together');
    for (const [file, marker, eol] of [
      [toolchain, 'if(NOT CMAKE_C_COMPILER)', '\r\n'], [thirdParty, '/InstallWindowsToolchain.cmake")', '\n'],
      [xml, '-DCMAKE_CXX_COMPILER=', '\r\n'], [installed, 'install(FILES', '\n'],
    ]) {
      const text = fs.readFileSync(file, 'utf8');
      assert.ok(text.includes(marker), file);
      assert.equal(text, withEol(text, eol), file);
      assertNoRewrite(file, apply);
    }
    fs.writeFileSync(installed, 'incomplete\n');
    assert.throws(apply, /compiler Windows patch shape drift/, 'reverse check must reject a partial installation');
  });
}

// Read the actual patched toolchain before compiler IDs exist, as on first configure.
test('Windows CMake linker and archive tool selection', async t => {
  const root = tempTree(t), compiler = path.join(root, 'compiler');
  fs.cpSync(WINDOWS_PIN_FIXTURE, compiler, {recursive: true});
  applyCompilerWindowsPatches(compiler);
  const sibling = path.join(root, 'selected toolchain', 'bin'), ambient = path.join(root, 'ambient');
  for (const dir of [sibling, ambient]) {
    fs.mkdirSync(dir, {recursive: true});
    for (const name of ['llvm-ar.exe', 'llvm-ranlib.exe', ...(dir === ambient ? ['lld.exe', 'llvm-ar', 'llvm-ranlib'] : [])])
      fs.writeFileSync(path.join(dir, name), '', {mode: 0o755});
  }
  const slash = file => file.replaceAll('\\', '/');
  const toolchain = slash(path.join(compiler, 'cmake/mingw_x86_64_toolchain.cmake'));
  const script = path.join(root, 'read.cmake');
  fs.writeFileSync(script, [
    'cmake_minimum_required(VERSION 3.20)', 'set(CMAKE_EXECUTABLE_SUFFIX ".exe")',
    'include([[' + toolchain + ']])',
    'file(WRITE result.txt "${CMAKE_C_FLAGS}\\n${CMAKE_CXX_FLAGS}\\n${CMAKE_AR}\\n${CMAKE_RANLIB}")',
  ].join('\n'));
  function read(cc, extra = []) {
    const argv = ['-DCMAKE_PROGRAM_PATH=' + ambient, ...(cc ? ['-DCMAKE_C_COMPILER=' + cc] : []), ...extra, '-P', script];
    const r = spawnSync('cmake', argv, {cwd: root, encoding: 'utf8'});
    assert.equal(r.status, 0, r.stderr);
    const result = fs.readFileSync(path.join(root, 'result.txt'), 'utf8').split('\n');
    console.log('WINDOWS_CMAKE_SELECTION ' + JSON.stringify({cc, extra, result}));
    return result;
  }
  for (const name of ['clang.exe', 'clang', 'clang++', 'clang++.exe', 'CLANG.EXE', 'x86_64-w64-mingw32-clang.exe', 'x86_64-w64-mingw32-clang++.exe']) {
    await t.test(name, () => {
      const cc = slash(path.join(sibling, name));
      for (const spelling of [cc, cc.replaceAll('/', '\\')]) {
        const [c, cxx, ar, ranlib] = read(spelling);
        for (const flags of [c, cxx]) {
          assert.match(flags, /-fuse-ld=lld/);
          assert.doesNotMatch(flags, /-B.*toolchain\//);
        }
        assert.equal(ar, slash(path.join(sibling, 'llvm-ar.exe')));
        assert.equal(ranlib, slash(path.join(sibling, 'llvm-ranlib.exe')));
      }
    });
  }
  await t.test('GCC defaults and explicit drivers keep their linker directory', () => {
    for (const cc of ['', 'x86_64-w64-mingw32-gcc', 'gcc', 'g++']) {
      const [c, cxx] = read(cc);
      for (const flags of [c, cxx]) assert.ok(flags.includes('-B' + slash(root) + '/toolchain/'), flags);
    }
  });
  await t.test('explicit overrides and per-tool fallback', () => {
    const cc = path.join(sibling, 'clang.exe'), overrides = ['llvm-ar.exe', 'llvm-ranlib.exe'].map(n => slash(path.join(ambient, n)));
    assert.deepEqual(read(cc, ['-DCMAKE_AR=' + overrides[0], '-DCMAKE_RANLIB=' + overrides[1]]).slice(2), overrides);
    fs.unlinkSync(path.join(sibling, 'llvm-ar.exe'));
    const [,, ar, ranlib] = read(cc);
    assert.equal(slash(path.dirname(ar)), slash(ambient));
    assert.equal(ranlib, slash(path.join(sibling, 'llvm-ranlib.exe')));
  });
});

for (const [style, eol] of [['LF', '\n'], ['CRLF', '\r\n']]) {
  test('Windows base-patched compiler upgrade: ' + style, t => {
    const root = tempTree(t);
    fs.cpSync(WINDOWS_PIN_FIXTURE, root, {recursive: true});
    const base = fs.readFileSync(new URL('../srcbuild/patches/compiler-windows-native.patch', import.meta.url), 'utf8');
    // Reproduce the previous producer's per-file EOL with LF for the new module.
    const input = withEol(base, '\n').split(/^(?=diff --git )/m).map(section => {
      if (section.includes('new file mode')) return section;
      const file = path.join(root, /^diff --git a\/(.+) b\//.exec(section)[1]);
      fs.writeFileSync(file, withEol(fs.readFileSync(file, 'utf8'), eol));
      return withEol(section, eol);
    }).join('');
    const old = spawnSync('git', ['-c', 'core.autocrlf=false', '-c', 'core.whitespace=cr-at-eol', 'apply', '-'],
      {cwd: root, input, encoding: 'utf8', env: {...process.env, GIT_CEILING_DIRECTORIES: path.dirname(root)}});
    assert.equal(old.status, 0, old.stderr);
    const file = path.join(root, 'cmake/mingw_x86_64_toolchain.cmake');
    const before = fs.readFileSync(file, 'utf8');
    assert.ok(before.includes('if(NOT CMAKE_C_COMPILER)'));
    applyCompilerWindowsPatches(root);
    const after = fs.readFileSync(file, 'utf8');
    assert.notEqual(after, before, 'cached base patch still needs the Clang change');
    assert.equal(after, withEol(after, eol));
    assertNoRewrite(file, () => applyCompilerWindowsPatches(root));
  });
}
