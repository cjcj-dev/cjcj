// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
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

function applyCompilerCjdbPatches(repoDir) {
  applyTextPatch(path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake'), BUILDCJDB_EDITS, {
    stage: 'fetch.patch', marker: 'STEP_TARGETS build configure',
  });
  applyTextPatch(path.join(repoDir, 'src', 'CMakeLists.txt'), SRC_CMAKE_EDITS, {
    stage: 'fetch.patch', marker: 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  });
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
