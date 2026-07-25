// Port of cangjie-build/src/cangjie_build/toolchain/sccache.py.

import fs from 'node:fs';
import path from 'node:path';
import {getLogger} from '../lib/logging.mjs';

const logger = getLogger('cangjie_build.toolchain.sccache');
const LAUNCHER_VARS = ['CMAKE_C_COMPILER_LAUNCHER', 'CMAKE_CXX_COMPILER_LAUNCHER'];

function findExecutable(name) {
  const extensions = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';')
    : [''];
  for (const directory of (process.env.PATH || '').split(path.delimiter)) {
    if (!directory) continue;
    for (const extension of extensions) {
      const candidate = path.join(directory, `${name}${extension}`);
      try {
        fs.accessSync(candidate, fs.constants.X_OK);
        return candidate;
      } catch {}
    }
  }
  return null;
}

export function describeBackends(env = process.env) {
  if (env.SCCACHE_MULTILEVEL_CHAIN) return `multi-level [${env.SCCACHE_MULTILEVEL_CHAIN}]`;
  if (['1', 'true', 'yes'].includes((env.SCCACHE_GHA_ENABLED || '').toLowerCase())) return 'github-actions';
  if (env.SCCACHE_AZURE_CONNECTION_STRING) return `azblob[${env.SCCACHE_AZURE_BLOB_CONTAINER || '?'}]`;
  if (env.SCCACHE_BUCKET) return `s3[${env.SCCACHE_BUCKET}]`;
  if (env.SCCACHE_GCS_BUCKET) return `gcs[${env.SCCACHE_GCS_BUCKET}]`;
  if (env.SCCACHE_REDIS || env.SCCACHE_REDIS_ENDPOINT) return 'redis';
  if (env.SCCACHE_MEMCACHED || env.SCCACHE_MEMCACHED_ENDPOINT) return 'memcached';
  if (env.SCCACHE_WEBDAV_ENDPOINT) return 'webdav';
  if (env.SCCACHE_DIR) return 'disk';
  return 'default (disk)';
}

export function maybeEnable() {
  const sccachePath = findExecutable('sccache');
  if (!sccachePath) {
    logger.debug('sccache not found on PATH; skipping launcher injection');
    return false;
  }
  let enabled = false;
  for (const variable of LAUNCHER_VARS) {
    if (process.env[variable]) {
      logger.debug('%s already set to %s; leaving as-is', variable, process.env[variable]);
      continue;
    }
    process.env[variable] = 'sccache';
    enabled = true;
  }
  if (enabled) {
    logger.info('sccache enabled via CMAKE_*_COMPILER_LAUNCHER (%s, backend: %s)', sccachePath, describeBackends());
  }
  return enabled;
}
