#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const entryIndex = process.argv.findIndex((arg, i) => i > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
const cliArgs = process.argv.slice(entryIndex + 1);
function pin(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split(/\r?\n/)
    .filter(line => /^[A-Z_]+=/.test(line)).map(line => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    }));
}
async function capture(command, {check = true} = {}) {
  const result = await $({cwd: repo, nothrow: true, quiet: true})`${command}`;
  // Shell command substitutions forward stderr even when successful.
  process.stderr.write(result.stderr);
  if (check && result.exitCode !== 0) process.exit(result.exitCode);
  return result;
}
async function run(command) {
  const result = await capture(command, {check: false});
  process.stdout.write(result.stdout);
  if (result.exitCode !== 0) process.exit(result.exitCode);
}
function reject(message) { console.error(`LLVM_RUNTIME_INPUT_ERROR: ${message}`); process.exit(1); }
const env = process.env;
let privateInput = false, runtimeUrl, runtimeSha;
switch (env.CJCJ_LLVM_RUNTIME_MODE || '') {
  case '': {
    if ('CJCJ_LLVM_RUNTIME_URL' in env || 'CJCJ_LLVM_RUNTIME_SHA' in env) reject('private URL/SHA require CJCJ_LLVM_RUNTIME_MODE=private');
    const selection = pin(path.join(repo, 'ci/runtime_pin.env'));
    runtimeUrl = selection.RUNTIME_SRC_URL; runtimeSha = selection.RUNTIME_REF;
    break;
  }
  case 'private':
    privateInput = true;
    if ('RUNTIME_REF' in env || 'RUNTIME_SRC_URL' in env) reject('do not mix private inputs with RUNTIME_REF/RUNTIME_SRC_URL');
    if (env.CJCJ_LLVM_RUNTIME_URL !== 'https://github.com/cjcj-dev/cangjie-runtime.git') reject('private runtime requires the approved cjcj-dev HTTPS URL');
    if (!/^[0-9a-f]{40}$/.test(env.CJCJ_LLVM_RUNTIME_SHA || '')) reject('private runtime requires a complete lowercase 40-digit SHA');
    runtimeUrl = env.CJCJ_LLVM_RUNTIME_URL; runtimeSha = env.CJCJ_LLVM_RUNTIME_SHA;
    break;
  default: reject('CJCJ_LLVM_RUNTIME_MODE must be unset or private');
}
const args = cliArgs.slice();
let operation = 'fetch';
if (args[0] === '--check-input') { operation = 'check'; args.shift(); }
else if (args[0] === '--verify-checkout') { operation = 'verify'; args.shift(); }
if (args.length !== 1 || !args[0]) reject('expected one paired runtime destination');
const dest = path.resolve(args[0]);
async function verifyClean() {
  const top = await capture(['git', '-C', dest, 'rev-parse', '--show-toplevel'], {check: false});
  if (top.exitCode !== 0) reject('private runtime destination is not a Git worktree');
  if (fs.realpathSync(dest) !== fs.realpathSync(top.stdout.trim())) reject('private runtime destination must be the Git worktree root');
  const status = await capture(['git', '-C', dest, 'status', '--porcelain', '--untracked-files=all'], {check: false});
  if (status.exitCode !== 0) reject('cannot inspect private runtime checkout');
  if (status.stdout.trim()) reject('private runtime checkout is dirty');
}
if (privateInput && fs.existsSync(dest)) await verifyClean();
if (operation === 'check') process.exit(0);
if (operation === 'verify') {
  if (privateInput) {
    await verifyClean();
    if ((await capture(['git', '-C', dest, 'rev-parse', 'HEAD'])).stdout.trim() !== runtimeSha) reject('private runtime checkout HEAD differs from requested SHA');
    console.log(`LLVM_RUNTIME_IDENTITY mode=private sha=${runtimeSha} source=${fs.realpathSync(dest)}`);
  }
  process.exit(0);
}
// Existing transport policy is shared with the shell tuple producers (G2).
// Keep that helper's exact diagnostics and fetch argv until its own migration.
await run(['git', 'init', dest]);
await run(['bash', '-c', 'set -euo pipefail; source "$1"; srcbuild_git_fetch "$2" "$3" "$4"', 'fetch-runtime', path.join(repo, 'build/lib/srcbuild_git.sh'), dest, runtimeUrl, runtimeSha]);
await run(['git', '-C', dest, 'checkout', '--detach', 'FETCH_HEAD']);
if ((await capture(['git', '-C', dest, 'rev-parse', 'HEAD'])).stdout.trim() !== runtimeSha) process.exit(1);
if (privateInput) {
  await verifyClean();
  console.log(`LLVM_RUNTIME_IDENTITY mode=private sha=${runtimeSha} source=${fs.realpathSync(dest)}`);
}
