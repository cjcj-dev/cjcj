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
  const result = await $({cwd, env, input, nothrow: true, quiet: true})`${commandArgs(command)}`;
  if (log) fs.writeFileSync(log, result.stdall);
  else {
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
  }
  if (check && result.exitCode !== 0) {
    throw new CommandExit(result.exitCode);
  }
  return result;
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
export async function diff(saved, current, output) {
  const result = await run(['diff', '-u', saved, current], {log: output, check: false});
  assert.equal(result.exitCode, 1);
}
export function replace(file, old, replacement) {
  const source = fs.readFileSync(file, 'utf8');
  assert.equal(source.split(old).length, 2, `ANCHOR-MISMATCH ${file}`);
  fs.writeFileSync(file, source.replace(old, replacement));
}

class CommandExit extends Error { constructor(rc) { super(); this.rc = rc; } }
process.on('uncaughtException', error => {
  if (error instanceof CommandExit) process.exitCode = error.rc;
  else { console.error(error); process.exitCode = 1; }
});
