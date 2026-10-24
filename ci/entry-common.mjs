// Shared process/file operations for the zx CI entries. Commands remain argv
// arrays so workspace paths and caller arguments retain their exact boundaries.
// zx supplies $ globally, including to imported ESM modules.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
export {fs, path, assert};
// argv._ intentionally drops named options. These entries own their parsers,
// so retain the raw tail after the ESM entry (node and zx have different prefixes).
const entryIndex = process.argv.findIndex((arg, index) => index > 0 && arg.endsWith('.mjs'));
export const cliArgs = process.argv.slice(entryIndex + 1);
export const isMain = url => process.argv.slice(1).some(arg => path.resolve(arg) === fileURLToPath(url));
export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const toCommandPath = target => target.replaceAll('\\', '/');
// Normalize Windows command paths, preserving backslashes in scalar arguments
// (for example an invalid CLI option whose diagnostic must quote it verbatim).
const commandArgs = command => command.map(arg => /^[A-Za-z]:[\\/]/.test(arg) ? toCommandPath(arg) : arg);
export const zxCommand = file => ['npx', '--yes', 'zx@8', file];
export function pin(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split(/\r?\n/)
    .filter(line => /^[A-Z_]+=/.test(line)).map(line => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    }));
}
export async function run(command, {cwd = repo, env = process.env, log, input, check = true} = {}) {
  // Bash's >log 2>&1 gives both descriptors one open file description. Joining
  // independently drained pipes changes diagnostic order and stdio buffering.
  const descriptor = log ? fs.openSync(log, 'w') : undefined;
  let result;
  try {
    result = await $({cwd, env, input, nothrow: true, quiet: true,
      ...(log ? {stdio: ['pipe', descriptor, descriptor]} : {})})`${commandArgs(command)}`;
  } finally { if (descriptor !== undefined) fs.closeSync(descriptor); }
  if (!log) {
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
  }
  if (check && result.exitCode !== 0) {
    throw new CommandExit(result.exitCode);
  }
  return log ? {exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr,
    stdall: fs.readFileSync(log, 'utf8')} : result;
}
export async function capture(command, options = {}) {
  const result = await $({cwd: options.cwd ?? repo, env: options.env ?? process.env,
    input: options.input, nothrow: true, quiet: true})`${commandArgs(command)}`;
  if (options.check !== false && result.exitCode !== 0) {
    process.stderr.write(result.stderr);
    throw new CommandExit(result.exitCode);
  }
  return result;
}
// Shell >file opens/truncates before launching the command, including when the
// command fails. A descriptor also keeps binary output out of UTF-8 strings.
export async function redirect(command, output, {cwd = repo, env = process.env, input} = {}) {
  const descriptor = fs.openSync(output, 'w');
  let result;
  try {
    result = await $({cwd, env, input, nothrow: true, quiet: true,
      stdio: ['pipe', descriptor, 'pipe']})`${commandArgs(command)}`;
  } finally { fs.closeSync(descriptor); }
  process.stderr.write(result.stderr);
  if (result.exitCode !== 0) throw new CommandExit(result.exitCode);
  return result;
}
export function requireSuccess(result) {
  if (result.exitCode !== 0) throw new CommandExit(result.exitCode);
  return result;
}
export async function hash(files, output, cwd = repo) {
  fs.writeFileSync(output, (await capture(['sha256sum', ...files], {cwd})).stdout);
}
export function equalFiles(a, b) { assert.deepEqual(fs.readFileSync(a), fs.readFileSync(b)); }
export function requireArgument(index, line, label) {
  const value = cliArgs[index];
  if (!value) {
    console.error(`${process.argv[entryIndex]}: line ${line}: ${index + 1}: ${label}`);
    process.exit(1);
  }
  return value;
}
export function exit(rc) { throw new CommandExit(rc); }
// An OS signal does not unwind JavaScript finally blocks. Fault-injection
// entries must finish their synchronous restoration before leaving the process.
export function cleanupOnSignals(cleanup) {
  const handlers = new Map();
  for (const [signal, status] of [['SIGINT', 130], ['SIGTERM', 143]]) {
    const handler = () => {
      let rc = status;
      try { cleanup(); }
      catch (error) { console.error(error); rc = 1; }
      process.exit(rc);
    };
    handlers.set(signal, handler);
    process.once(signal, handler);
  }
  return () => { for (const [signal, handler] of handlers) process.removeListener(signal, handler); };
}
export async function diff(saved, current, output, cwd = repo) {
  const result = await run(['diff', '-u', saved, current], {cwd, log: output, check: false});
  assert.equal(result.exitCode, 1);
}
// Bind only entries whose Bash contract keeps the caller's working directory.
// Do not chdir the process or change the repo defaults used by AST/colour.
// Keep argv spellings intact: absolute conversion would also change diagnostics
// and checksum records. Explicit per-command cwd (e.g. tuple checks) still wins.
export function commandsAt(cwd) {
  return {
    run: (command, options = {}) => run(command, {cwd, ...options}),
    capture: (command, options = {}) => capture(command, {cwd, ...options}),
    redirect: (command, output, options = {}) => redirect(command, output, {cwd, ...options}),
    hash: (files, output, directory = cwd) => hash(files, output, directory),
    diff: (saved, current, output) => diff(saved, current, output, cwd),
  };
}
export function replace(file, old, replacement) {
  const source = fs.readFileSync(file, 'utf8');
  assert.equal(source.split(old).length, 2, `ANCHOR-MISMATCH ${file}`);
  fs.writeFileSync(file, source.replace(old, replacement));
}

class CommandExit extends Error { constructor(rc) { super(); this.rc = rc; } }
// zx imports the entry and handles rejected top-level promises itself. Catch
// intentional command exits here, after the entry's finally blocks have run;
// an uncaughtException listener cannot prevent zx from printing their stacks.
export async function entry(main) {
  try { await main(); }
  catch (error) {
    if (error instanceof CommandExit) process.exitCode = error.rc;
    else throw error;
  }
}
