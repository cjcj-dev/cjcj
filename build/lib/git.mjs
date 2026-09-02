// Port of cangjie-build/src/cangjie_build/git.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';
import {run} from './runner.mjs';

const logger = getLogger('cangjie_build.git');

export function resolveSourceMirror(url, mappings = process.env.CJCJ_SRCBUILD_SOURCE_MIRRORS) {
  let resolved = url;
  let matched = false;
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
    if (source === url) {
      resolved = mirror;
      matched = true;
    }
  }
  if (!matched) {
    console.error(`SOURCE-MIRROR none, falling back to ${url}`);
    if (process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS === '1') {
      throw new BuildError('git', `source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1: ${url}`);
    }
  }
  return resolved;
}

export function sourceFetchArguments(url, ref, {
  depth = 1,
  noTags = false,
  filter = '',
  dryRun = false,
} = {}) {
  const command = ['-c', 'http.version=HTTP/1.1', 'fetch'];
  if (noTags) command.push('--no-tags');
  if (dryRun) command.push('--dry-run');
  if (depth) command.push('--depth', String(depth));
  if (filter) command.push('--filter', filter);
  command.push(resolveSourceMirror(url), ref);
  return command;
}

export function sourceLsRemoteArguments(url, ...refs) {
  return ['-c', 'http.version=HTTP/1.1', 'ls-remote', '--exit-code', resolveSourceMirror(url), ...refs];
}

export async function fetchSource(url, ref, {
  cwd,
  depth = 1,
  noTags = false,
  filter = '',
  stage = 'git.fetch',
  ...runOptions
} = {}) {
  if (!cwd) throw new BuildError(stage, 'fetchSource requires cwd');
  return run(['git', ...sourceFetchArguments(url, ref, {depth, noTags, filter})], {
    cwd,
    stage,
    ...runOptions,
  });
}

export async function checkoutExactSource(url, dest, ref) {
  fs.mkdirSync(dest, {recursive: true});
  if (!fs.existsSync(path.join(dest, '.git'))) {
    await run(['git', 'init', dest], {stage: 'git.init'});
    await run(['git', '-C', dest, 'remote', 'add', 'origin', url], {stage: 'git.remote'});
  } else {
    const remote = await run(['git', '-C', dest, 'remote', 'get-url', 'origin'], {
      stage: 'git.remote', check: false, capture: true, logOutput: false,
    });
    if (remote.exitCode === 0) {
      await run(['git', '-C', dest, 'remote', 'set-url', 'origin', url], {stage: 'git.remote'});
    } else {
      await run(['git', '-C', dest, 'remote', 'add', 'origin', url], {stage: 'git.remote'});
    }
  }
  await fetchSource(url, ref, {cwd: dest});
  await run(['git', '-C', dest, 'checkout', '--detach', 'FETCH_HEAD'], {stage: 'git.checkout'});
}

export async function shallowClone(url, dest, {tag} = {}) {
  if (fs.existsSync(dest)) throw new BuildError('git', `destination already exists: ${dest}`);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  const fetchUrl = resolveSourceMirror(url);
  if (tag && /^[0-9a-f]{40}$/i.test(tag)) {
    logger.info('Cloning %s @ %s into %s', url, tag, dest);
    await checkoutExactSource(url, dest, tag);
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
