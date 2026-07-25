// Port of cangjie-build/src/cangjie_build/git.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';
import {run} from './runner.mjs';

const logger = getLogger('cangjie_build.git');

export async function shallowClone(url, dest, {tag} = {}) {
  if (fs.existsSync(dest)) throw new BuildError('git', `destination already exists: ${dest}`);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  const command = ['git', 'clone', '--depth', '1'];
  if (tag) command.push('--branch', tag);
  command.push(url, dest);
  logger.info('Cloning %s%s into %s', url, tag ? ` @ ${tag}` : '', dest);
  await run(command, {stage: 'git.clone'});
}
