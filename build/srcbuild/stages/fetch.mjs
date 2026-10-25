// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {saveSourceSelection} from '../../lib/config.mjs';
import {BuildError} from '../../lib/errors.mjs';
import {shallowClone, assertSourceIdentity} from '../../lib/git.mjs';
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

// The installed public compiler headers include several generated schemas.
// Install the complete output set owned by the existing flatc target, including
// libs-only builds; never synthesize headers or copy them after CMake install.
export function applyCompilerSchemaInstall(repoDir) {
  const target = 'add_custom_target(CangjieFlatbuffersHeaders DEPENDS ${FLATC_OUTPUTS} ${FLATC_LIBAST_OUTPUTS})';
  const install = 'install(FILES ${FLATC_OUTPUTS} DESTINATION include/flatbuffers)';
  applyTextPatch(path.join(repoDir, 'schema', 'CMakeLists.txt'), [[target, target + '\n' + install]], {
    stage: 'fetch.patch.schema-install', marker: install,
  });
}

// Keep the reviewed 53da076 native Windows compiler/install changes when
// consuming canonical sources. Canonical Flatbuffer.cmake already forwards
// selected compilers and separates host flatc; preserve its newer recipe.
export function applyCompilerWindowsPatches(repoDir) {
  const patch = fileURLToPath(new URL('../patches/compiler-windows-native.patch', import.meta.url));
  const apply = (...args) => spawnSync('git', ['apply', ...args, patch], {
    cwd: repoDir, encoding: 'utf8',
  });
  const check = apply('--check');
  if (check.status !== 0) {
    const restored = apply('--reverse', '--check');
    if (restored.status === 0) return;
    throw new BuildError('fetch.patch.windows', `compiler Windows patch shape drift: ${check.stderr || check.error?.message}`);
  }
  const result = apply();
  if (result.status !== 0) {
    throw new BuildError('fetch.patch.windows', result.stderr || result.error?.message || `git apply exited ${result.status}`);
  }
}

export async function run(config) {
  ensureDir(config.workspace);
  await stage('fetch', async () => {
    for (const repo of Object.values(config.repos)) {
      const target = path.join(config.workspace, repo.dirName);
      if (fs.existsSync(target)) {
        logger.info('Checking existing repo %s at %s', repo.name, target);
      } else {
        await shallowClone(repo.url, target, {tag: repo.tag});
      }
      await assertSourceIdentity(repo, target);
    }
    applyCompilerCjdbPatches(config.repoPath('compiler'));
    applyCompilerSchemaInstall(config.repoPath('compiler'));
    if (config.target.spec.nodePlatform === 'win32') applyCompilerWindowsPatches(config.repoPath('compiler'));
    saveSourceSelection(config);
  });
}
