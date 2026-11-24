#!/usr/bin/env zx
// Native tools guard. The Darwin H1 producer used to run two private modules
// (ts/src/sharedbuild/{cjcj-stage1,stage1-transform}.mjs) that never existed in
// any public tools commit. They are retired: Linux and Darwin both build H1
// through the public in-repo cjpm path (packages/cjc/cjpm.toml carries the
// ELF and Mach-O link options per target). Nothing is deployed from a tools
// checkout any more; this module only keeps the fail-closed origin guards.
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execute = promisify(execFile);
export const RETIRED_NATIVE_TOOLS_ADAPTER_FILES = Object.freeze([
  'ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']);
const pinFile = fileURLToPath(new URL('../source_pin.env', import.meta.url));
const normalize = url => String(url || '').trim().replace(/\.git$/, '').replace(/\/$/, '');
export function publicToolsRepository(text = readFileSync(pinFile, 'utf8')) {
  const url = /^TOOLS_SRC_URL=(.*)$/m.exec(text)?.[1];
  if (!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(normalize(url))) throw new Error('NATIVE_TOOLS_PUBLIC_URL');
  return normalize(url);
}
// A private tools root is never an H1 input on any host.
export function rejectPrivateTools(tools = {}) {
  if (tools?.privateRoot !== undefined) throw new Error('NATIVE_TOOLS_PRIVATE_ROOT_RETIRED');
  return tools;
}
// A tools checkout is accepted only from the public origin at an explicit commit.
export async function verifyPublicToolsCheckout(repository, commit, {publicUrl = publicToolsRepository()} = {}) {
  if (!/^[0-9a-f]{40}$/.test(commit || '')) throw new Error('NATIVE_TOOLS_COMMIT_REQUIRED');
  const origin = (await execute('git', ['-C', repository, 'remote', 'get-url', 'origin']).catch(() => ({stdout: ''}))).stdout;
  if (normalize(origin) !== normalize(publicUrl)) throw new Error('NATIVE_TOOLS_REPOSITORY_NOT_PUBLIC');
  const actual = (await execute('git', ['-C', repository, 'rev-parse', commit + '^{commit}'])).stdout.trim();
  if (actual !== commit) throw new Error('NATIVE_TOOLS_COMMIT');
  return {repository: normalize(publicUrl), commit};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await verifyPublicToolsCheckout(...process.argv.slice(2)))); }
  catch (error) { console.error(error.stack); process.exitCode = 1; }
}
