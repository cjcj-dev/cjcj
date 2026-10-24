// Preserve the tuple scripts' caller cwd and one merged, live tee stream.
// The small shell primitive owns only descriptor setup, never tuple decisions.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {commandsAt, exit, toCommandPath} from '../entry-common.mjs';
export const {capture, redirect} = commandsAt(process.cwd());
export async function run(command) {
  const args = command.map(arg => /^[A-Za-z]:[\\/]/.test(arg) ? toCommandPath(arg) : arg);
  // Children inherit the one merged descriptor installed by logged(); do not
  // buffer stdout and stderr separately and reorder them after completion.
  const result = await $({cwd: process.cwd(), nothrow: true, quiet: true, stdio: 'inherit'})`${args}`;
  if (result.exitCode !== 0) exit(result.exitCode);
  return result;
}
export function required(name, line, label = '') {
  const value = process.env[name];
  if (!value) {
    console.error(`${process.argv.find(x => x.endsWith('.mjs'))}: line ${line}: ${name}: ${label || 'parameter null or not set'}`);
    exit(1);
  }
  return value;
}
export async function logged(url, log, main) {
  const identity = fileURLToPath(url);
  if (process.env.CJCJ_TUPLE_LOG_CHILD === `${process.ppid}:${identity}`) {
    delete process.env.CJCJ_TUPLE_LOG_CHILD;
    return main();
  }
  const child = spawn('bash', ['-c', 'log=$1; shift; exec > >(tee "$log") 2>&1; exec "$@"',
    'tuple-log', log, process.execPath, ...process.execArgv, ...process.argv.slice(1)], {
    cwd: process.cwd(), stdio: 'inherit',
    env: {...process.env, CJCJ_TUPLE_LOG_CHILD: `${process.pid}:${identity}`},
  });
  const handlers = ['SIGINT', 'SIGTERM', 'SIGHUP'].map(signal => {
    const handler = () => child.kill(signal);
    process.on(signal, handler); return [signal, handler];
  });
  try {
    const result = await new Promise((resolve, reject) => {
      child.once('error', reject); child.once('exit', (code, signal) => resolve({code, signal}));
    });
    if (result.signal) {
      for (const [signal, handler] of handlers) process.removeListener(signal, handler);
      process.kill(process.pid, result.signal);
      return;
    }
    if (result.code) exit(result.code);
  } finally { for (const [signal, handler] of handlers) process.removeListener(signal, handler); }
}
