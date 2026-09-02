// Port of cangjie-build/src/cangjie_build/toolchain/_archive.py.

import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';
import {run} from './runner.mjs';

const logger = getLogger('cangjie_build.toolchain.archive');

export async function download(url, dest) {
  net.setDefaultAutoSelectFamilyAttemptTimeout(2_000);
  if (fs.existsSync(dest)) {
    logger.info('Reusing cached download: %s', dest);
    return;
  }
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  logger.info('Downloading %s', url);
  const temporary = `${dest}.part`;
  const response = await fetch(url, {signal: AbortSignal.timeout(60_000)});
  if (!response.ok || !response.body) {
    throw new BuildError('archive', `download failed: ${url} (HTTP ${response.status})`);
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
