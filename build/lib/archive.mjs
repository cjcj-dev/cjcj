// Port of cangjie-build/src/cangjie_build/toolchain/_archive.py.

import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';
import {run} from './runner.mjs';

const logger = getLogger('cangjie_build.toolchain.archive');

export function resolveTarballMirror(url, mappings = process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS) {
  let resolved = url;
  let matched = false;
  const seen = new Set();
  for (const entry of (mappings ?? '').split(';').filter(Boolean)) {
    const separator = entry.indexOf('=');
    if (separator <= 0 || separator === entry.length - 1) {
      throw new BuildError('archive', `invalid CJCJ_SRCBUILD_TARBALL_MIRRORS entry: ${entry}`);
    }
    const source = entry.slice(0, separator);
    const mirror = entry.slice(separator + 1);
    if (seen.has(source)) {
      throw new BuildError('archive', `duplicate CJCJ_SRCBUILD_TARBALL_MIRRORS source: ${source}`);
    }
    seen.add(source);
    if (source === url) {
      resolved = mirror;
      matched = true;
    }
  }
  if (!matched) {
    console.error(`TARBALL-MIRROR none, falling back to ${url}`);
    if (process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS === '1') {
      throw new BuildError('archive', `tarball mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1: ${url}`);
    }
  }
  return resolved;
}

export async function download(url, dest) {
  net.setDefaultAutoSelectFamilyAttemptTimeout(2_000);
  if (fs.existsSync(dest)) {
    logger.info('Reusing cached download: %s', dest);
    return;
  }
  const resolved = resolveTarballMirror(url);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  logger.info('Downloading %s', resolved);
  if (resolved.startsWith('file://')) {
    fs.copyFileSync(fileURLToPath(resolved), dest);
    return;
  }
  const temporary = `${dest}.part`;
  const response = await fetch(resolved, {signal: AbortSignal.timeout(60_000)});
  if (!response.ok || !response.body) {
    throw new BuildError('archive', `download failed: ${resolved} (HTTP ${response.status})`);
  }
  await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(temporary));
  fs.renameSync(temporary, dest);
}

export async function extract(tarball, destDir) {
  fs.mkdirSync(destDir, {recursive: true});
  logger.info('Extracting %s into %s', path.basename(tarball), destDir);
  const listing = await run(['tar', '-tf', tarball], {
    stage: 'archive.list', capture: true, logOutput: false,
  });
  const first = listing.stdout.split(/\r?\n/, 1)[0];
  if (!first) throw new BuildError('archive', `empty tarball: ${tarball}`);
  const top = first.split('/', 1)[0];
  await run(['tar', '-xf', tarball, '-C', destDir], {stage: 'archive.extract'});
  return path.join(destDir, top);
}
