import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {applyCompilerCjdbPatches, verifyCompilerCjdbPatches} from '../srcbuild/stages/fetch.mjs';

const BUILD_CJDB = [
  'externalproject_get_property(cjnative BINARY_DIR)',
  'set(LLVM_GC_BINARY_DIR "${BINARY_DIR}")',
  'ExternalProject_Add(',
  '    lldb',
  '    USES_TERMINAL_BUILD ON',
  '    DEPENDS cjnative)',
  '',
].join('\n');
const SRC_CMAKE = [
  'if(CANGJIE_BUILD_CJDB)',
  '    add_dependencies(lldb cangjie-frontend)',
  'endif()',
  '',
].join('\n');
const REQUIREMENTS = [
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), 'cmake_policy(SET CMP0114 NEW)'],
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), 'STEP_TARGETS build configure'],
  [path.join('src', 'CMakeLists.txt'), 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)'],
];

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

test('compiler CJDB patch verification has positive and per-requirement negative controls', () => {
  const root = makeCompilerFixture();
  try {
    applyCompilerCjdbPatches(root);
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

test('an existing patch marker cannot bypass another compiler CJDB requirement', () => {
  const root = makeCompilerFixture();
  try {
    const file = path.join(root, 'third_party', 'cmake', 'BuildCJDB.cmake');
    const partial = fs.readFileSync(file, 'utf8').replace(
      '    DEPENDS cjnative)',
      '    DEPENDS cjnative\n    STEP_TARGETS build configure)',
    );
    fs.writeFileSync(file, partial);
    assert.throws(
      () => applyCompilerCjdbPatches(root),
      error => error.message.includes('cmake_policy(SET CMP0114 NEW)'),
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
