// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {shallowClone} from '../../lib/git.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {applyTextPatch, ensureDir} from './common.mjs';

const logger = getLogger('cangjie_build.stages.fetch');
const BUILDCJDB_EDITS = [
  [
    'externalproject_get_property(cjnative BINARY_DIR)\nset(LLVM_GC_BINARY_DIR "${BINARY_DIR}")\n',
    'cmake_policy(SET CMP0114 NEW)\nexternalproject_get_property(cjnative BINARY_DIR)\nset(LLVM_GC_BINARY_DIR "${BINARY_DIR}")\n',
  ],
  [
    '    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative)\n',
    '    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative\n    STEP_TARGETS build configure)\n',
  ],
];
const SRC_CMAKE_EDITS = [[
  'if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\nendif()\n',
  'if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\n    if(TARGET lldb-build)\n        add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)\n    endif()\nendif()\n',
]];
const COMPILER_CJDB_REQUIREMENTS = [
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), [
    'cmake_policy(SET CMP0114 NEW)',
    'STEP_TARGETS build configure',
  ]],
  [path.join('src', 'CMakeLists.txt'), [
    'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  ]],
];

export function verifyCompilerCjdbPatches(repoDir) {
  for (const [relativePath, requiredTexts] of COMPILER_CJDB_REQUIREMENTS) {
    const file = path.join(repoDir, relativePath);
    const source = fs.readFileSync(file, 'utf8');
    for (const requiredText of requiredTexts) {
      if (!source.includes(requiredText)) {
        throw new BuildError('fetch.patch.verify', `required compiler patch text missing from ${file}: ${requiredText}`);
      }
    }
  }
}

export function applyCompilerCjdbPatches(repoDir) {
  applyTextPatch(path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake'), BUILDCJDB_EDITS, {
    stage: 'fetch.patch', marker: 'STEP_TARGETS build configure',
  });
  applyTextPatch(path.join(repoDir, 'src', 'CMakeLists.txt'), SRC_CMAKE_EDITS, {
    stage: 'fetch.patch', marker: 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  });
  verifyCompilerCjdbPatches(repoDir);
}

export async function run(config) {
  ensureDir(config.workspace);
  await stage('fetch', async () => {
    for (const repo of Object.values(config.repos)) {
      const target = path.join(config.workspace, repo.dirName);
      if (fs.existsSync(target)) {
        logger.info('Repo %s already at %s, skipping clone', repo.name, target);
        continue;
      }
      await shallowClone(repo.url, target, {tag: repo.tag});
    }
    applyCompilerCjdbPatches(config.repoPath('compiler'));
  });
}
