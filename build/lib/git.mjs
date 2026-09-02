// Port of cangjie-build/src/cangjie_build/git.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';
import {run} from './runner.mjs';

const logger = getLogger('cangjie_build.git');

export function resolveSourceMirror(url, mappings = process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS) {
  let resolved = url;
  const seen = new Set();
  for (const entry of (mappings ?? '').split(';').filter(Boolean)) {
    const separator = entry.indexOf('=');
    if (separator <= 0 || separator === entry.length - 1) {
      throw new BuildError('git', `invalid CJCJ_SRCBUILD_SOURCE_MIRRORS entry: ${entry}`);
    }
    const source = entry.slice(0, separator);
    const mirror = entry.slice(separator + 1);
    if (seen.has(source)) {
      throw new BuildError('git', `duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source: ${source}`);
    }
    seen.add(source);
    if (source === url) resolved = mirror;
  }
  return resolved;
}

export async function shallowClone(url, dest, {tag} = {}) {
  if (fs.existsSync(dest)) throw new BuildError('git', `destination already exists: ${dest}`);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  const fetchUrl = resolveSourceMirror(url);
  if (tag && /^[0-9a-f]{40}$/i.test(tag)) {
    logger.info('Cloning %s @ %s into %s', url, tag, dest);
    await run(['git', 'init', dest], {stage: 'git.init'});
    await run(['git', '-C', dest, 'remote', 'add', 'origin', url], {stage: 'git.remote'});
    await run(['git', '-C', dest, '-c', 'http.version=HTTP/1.1',
      'fetch', '--depth', '1', fetchUrl, tag], {stage: 'git.fetch'});
    await run(['git', '-C', dest, 'checkout', '--detach', 'FETCH_HEAD'], {stage: 'git.checkout'});
    return;
  }
  const command = ['git', '-c', 'http.version=HTTP/1.1', 'clone', '--depth', '1'];
  if (tag) command.push('--branch', tag);
  command.push(fetchUrl, dest);
  logger.info('Cloning %s%s into %s', url, tag ? ` @ ${tag}` : '', dest);
  await run(command, {stage: 'git.clone'});
  if (fetchUrl !== url) {
    await run(['git', '-C', dest, 'remote', 'set-url', 'origin', url], {stage: 'git.remote'});
  }
}
