import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {verifyCompilerCjdbPatches} from '../srcbuild/stages/fetch.mjs';

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
