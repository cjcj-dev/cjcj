import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {applyCompilerCjdbPatches, verifyCompilerCjdbPatches} from '../srcbuild/stages/fetch.mjs';

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

test('pinned 174db8f compiler files pass verify only after apply restores the cjdb patch bytes', () => {
  const root = copyPinFixture();
  const cjdb = path.join(root, 'third_party', 'cmake', 'BuildCJDB.cmake');
  const src = path.join(root, 'src', 'CMakeLists.txt');
  try {
    assert.throws(
      () => verifyCompilerCjdbPatches(root),
      error => error.message.includes('cmake_policy(SET CMP0114 NEW)'),
    );

    let applyError = null;
    try {
      applyCompilerCjdbPatches(root);
    } catch (error) {
      applyError = error;
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
    assert.equal(applyError, null);
    applyCompilerCjdbPatches(root);
    assert.equal(sha256(cjdb), PATCHED_SHA.buildCjdb);
    assert.equal(sha256(src), PATCHED_SHA.srcCmake);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
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
