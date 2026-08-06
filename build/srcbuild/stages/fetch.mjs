// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {shallowClone} from '../../lib/git.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {ensureDir} from './common.mjs';

const logger = getLogger('cangjie_build.stages.fetch');
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
    verifyCompilerCjdbPatches(config.repoPath('compiler'));
  });
}
