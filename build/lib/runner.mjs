// Port of cangjie-build/src/cangjie_build/runner.py.

import {spawn} from 'node:child_process';
import {constants as osConstants} from 'node:os';
import {BuildError} from './errors.mjs';
import {getLogger} from './logging.mjs';

const logger = getLogger('cangjie_build.runner');

function quote(part) {
  const value = String(part);
  return /^[A-Za-z0-9_@%+=:,./-]+$/.test(value)
    ? value
    : `'${value.replaceAll("'", "'\"'\"'")}'`;
}

export function formatCommand(command) {
  return command.map(quote).join(' ');
}

function streamLines(stream, collect, logOutput = true) {
  let buffered = '';
  stream.setEncoding('utf8');
  stream.on('data', chunk => {
    collect?.(chunk);
    buffered += chunk;
    const lines = buffered.split(/\r?\n/);
    buffered = lines.pop();
    if (logOutput) for (const line of lines) logger.info('%s', line);
  });
  stream.on('end', () => {
    if (logOutput && buffered) logger.info('%s', buffered);
  });
}

export async function run(command, {
  cwd,
  envOverlay,
  stage = 'run',
  check = true,
  echo = true,
  capture = false,
  logOutput = true,
} = {}) {
  if (!Array.isArray(command) || command.length === 0) {
    throw new BuildError(stage, 'empty command');
  }
  const argv = command.map(String);
  if (echo) {
    const prefix = cwd ? `(cd ${quote(cwd)} && )` : '';
    logger.info('$ %s%s', prefix, formatCommand(argv));
  }

  // Explicit verification-only mode used to compare generated command sequences.
  if (process.env.CANGJIE_BUILD_DRY_RUN === '1') return {exitCode: 0, stdout: ''};

  let env;
  if (envOverlay) {
    env = {...process.env};
    for (const [name, value] of Object.entries(envOverlay)) {
      // A null overlay is an explicit deletion.  Spreading an overlay over
      // process.env cannot otherwise distinguish "inherit this variable" from
      // "make sure a caller-provided value is absent".
      if (value === null || value === undefined) delete env[name];
      else env[name] = String(value);
    }
  }
  const child = spawn(argv[0], argv.slice(1), {
    cwd: cwd ? String(cwd) : undefined,
    env,
    shell: false,
    stdio: ['inherit', 'pipe', 'pipe'],
  });
  let stdout = '';
  streamLines(child.stdout, capture ? chunk => { stdout += chunk; } : undefined, logOutput);
  streamLines(child.stderr);

  const result = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (exitCode, signal) => resolve({exitCode, signal}));
  }).catch(error => {
    throw new BuildError(stage, `command failed to start: ${formatCommand(argv)}: ${error.message}`);
  });

  let exitCode = result.exitCode;
  if (exitCode === null) {
    const signalNumber = osConstants.signals[result.signal] ?? 0;
    exitCode = 128 + signalNumber;
  }
  if (check && exitCode !== 0) {
    throw new BuildError(stage, `command failed: ${formatCommand(argv)}`, {exitCode});
  }
  return {exitCode, stdout};
}
