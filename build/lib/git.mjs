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
  if (tag && /^[0-9a-f]{40}$/i.test(tag)) {
    logger.info('Cloning %s @ %s into %s', url, tag, dest);
    await run(['git', 'init', dest], {stage: 'git.init'});
    await run(['git', '-C', dest, 'remote', 'add', 'origin', url], {stage: 'git.remote'});
    await run(['git', '-C', dest, 'fetch', '--depth', '1', 'origin', tag], {stage: 'git.fetch'});
    await run(['git', '-C', dest, 'checkout', '--detach', 'FETCH_HEAD'], {stage: 'git.checkout'});
    return;
  }
  const command = ['git', 'clone', '--depth', '1'];
  if (tag) command.push('--branch', tag);
  command.push(url, dest);
  logger.info('Cloning %s%s into %s', url, tag ? ` @ ${tag}` : '', dest);
  await run(command, {stage: 'git.clone'});
}
