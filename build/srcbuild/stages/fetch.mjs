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
const BOUNDSCHECK_DEPENDS = 'DEPENDS cangjie-demangler boundscheck';

// Upstream da68cc5ae3028c724da470b703eff757402cba44. Both cjnative
// source paths copy the static archive on Windows during their patch step.
// The shared-library target alone cannot order that producer before the copy.
export function applyCompilerBoundscheckDependencies(repoDir) {
  const file = path.join(repoDir, 'third_party', 'CMakeLists.txt');
  const source = fs.readFileSync(file, 'utf8');
  const oldText = `${BOUNDSCHECK_DEPENDS})`;
  const newText = `${BOUNDSCHECK_DEPENDS} boundscheck-static)`;
  const count = text => source.split(text).length - 1;
  if (count(oldText) + count(newText) !== 2) {
    throw new BuildError('fetch.patch', `patch shape drift: expected both cjnative boundscheck dependencies in ${file}`);
  }
  if (source.includes(oldText)) fs.writeFileSync(file, source.replaceAll(oldText, newText));
}

// VERSION.txt is produced by the same normal cjnative POST_BUILD step for
// Git checkouts and selected archives. Do not require a fabricated repository.
export function applyCompilerLlvmVersion(repoDir) {
  const old = 'COMMAND git log -1 --oneline --decorate > ${CMAKE_BINARY_DIR}/${THIRD_PARTY_LLVM}/VERSION.txt';
  const replacement = 'COMMAND "${CJCJ_NATIVE_NODE}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/llvm-source-version.mjs" "${SOURCE_DIR}" "${CMAKE_BINARY_DIR}/${THIRD_PARTY_LLVM}/VERSION.txt" "${CJ_LLVM_COMMIT}"';
  applyTextPatch(path.join(repoDir, 'third_party', 'CMakeLists.txt'), [[old, replacement]], {
    stage: 'fetch.patch.llvm-version', marker: replacement,
  });
  fs.copyFileSync(fileURLToPath(new URL('../patches/llvm-source-version.mjs', import.meta.url)),
    path.join(repoDir, 'third_party', 'cmake', 'llvm-source-version.mjs'));
}

// Xml2.cmake normally builds and installs the selected source before CJDB.
// Follow that producer's shared-library chain at install time; its entity
// version need not equal the source release, and the SONAME may change.
export function applyCompilerXml2Install(repoDir) {
  const file = path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake');
  for (const [entry, soname, entity] of [
    ['libxml2.dylib', 'libxml2.16.dylib', 'libxml2.2.14.0.dylib'],
    ['libxml2.so', 'libxml2.so.16', 'libxml2.so.2.14.0'],
  ]) {
    const old = `    install(FILES\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entry}\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${soname}\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entity}\n        DESTINATION third_party/llvm/lib)`;
    const replacement = `    install(CODE "file(INSTALL DESTINATION \\\"\\\${CMAKE_INSTALL_PREFIX}/third_party/llvm/lib\\\"\n        TYPE SHARED_LIBRARY FOLLOW_SYMLINK_CHAIN\n        FILES \\\"\${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entry}\\\")")`;
    applyTextPatch(file, [[old, replacement]], {stage:'fetch.patch.xml2-install', marker:replacement});
  }
}

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
    applyCompilerBoundscheckDependencies(config.repoPath('compiler'));
    applyCompilerSchemaInstall(config.repoPath('compiler'));
    if (config.target.spec.nodePlatform === 'win32') applyCompilerWindowsPatches(config.repoPath('compiler'));
    saveSourceSelection(config);
  });
}
