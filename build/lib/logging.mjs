// Port of cangjie-build/src/cangjie_build/logging_setup.py.

import {format} from 'node:util';

const LEVELS = {DEBUG: 10, INFO: 20, WARNING: 30, ERROR: 40};
let configuredLevel = LEVELS.INFO;

export function configureLogging(level = 'INFO') {
  const normalized = String(level).toUpperCase();
  if (!(normalized in LEVELS)) throw new Error(`unknown log level: ${level}`);
  configuredLevel = LEVELS[normalized];
}

function timestamp() {
  return new Date().toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, '');
}

export function getLogger(name) {
  const emit = (level, message, ...args) => {
    if (LEVELS[level] < configuredLevel) return;
    const padded = level.padEnd(7);
    process.stderr.write(`${timestamp()} ${padded} ${name} | ${format(message, ...args)}\n`);
  };
  return {
    debug: (message, ...args) => emit('DEBUG', message, ...args),
    info: (message, ...args) => emit('INFO', message, ...args),
    warning: (message, ...args) => emit('WARNING', message, ...args),
    error: (message, ...args) => emit('ERROR', message, ...args),
  };
}

export async function stage(name, action) {
  const logger = getLogger('cangjie_build.stage');
  logger.info('==> %s: starting', name);
  const started = performance.now();
  try {
    const result = await action();
    logger.info('==> %s: done in %ss', name, ((performance.now() - started) / 1000).toFixed(1));
    return result;
  } catch (error) {
    logger.error('==> %s: FAILED after %ss', name, ((performance.now() - started) / 1000).toFixed(1));
    throw error;
  }
}
