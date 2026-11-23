#!/usr/bin/env zx
// Deploy the two Unix (Darwin H1) adapter modules from the public, versioned
// tools repository named by ci/source_pin.env TOOLS_SRC_URL, at an explicit
// 40-hex commit. TOOLS_REF stays the product tools pin and is not rewritten here.
// No private repository is consulted: a checkout whose origin is not the public
// tools URL, or a commit that lacks either module, fails closed.
import fs from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileDigest, atomicJson, privateRoot} from './sdk-flow.mjs';
const execute = promisify(execFile);
export const NATIVE_TOOLS_ADAPTER_FILES = Object.freeze([
  'ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']);
const pinFile = fileURLToPath(new URL('../source_pin.env', import.meta.url));
const normalize = url => String(url || '').trim().replace(/\.git$/, '').replace(/\/$/, '');
export function publicToolsRepository(text = readFileSync(pinFile, 'utf8')) {
  const url = /^TOOLS_SRC_URL=(.*)$/m.exec(text)?.[1];
  if (!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(normalize(url))) throw new Error('NATIVE_TOOLS_PUBLIC_URL');
  return normalize(url);
}
export async function deployNativeTools(repository, commit, destination, {publicUrl = publicToolsRepository()} = {}) {
  if (!/^[0-9a-f]{40}$/.test(commit || '')) throw new Error('NATIVE_TOOLS_COMMIT_REQUIRED');
  const origin = (await execute('git', ['-C', repository, 'remote', 'get-url', 'origin']).catch(() => ({stdout: ''}))).stdout;
  if (normalize(origin) !== normalize(publicUrl)) throw new Error('NATIVE_TOOLS_REPOSITORY_NOT_PUBLIC');
  const actual = (await execute('git', ['-C', repository, 'rev-parse', commit + '^{commit}'])).stdout.trim();
  if (actual !== commit) throw new Error('NATIVE_TOOLS_COMMIT');
  for (const rel of NATIVE_TOOLS_ADAPTER_FILES) {
    try { await execute('git', ['-C', repository, 'cat-file', '-e', `${commit}:${rel}`]); }
    catch { throw new Error(`NATIVE_TOOLS_ADAPTER_MISSING ${rel}@${commit}`); }
  }
  destination = await privateRoot(destination);
  await fs.mkdir(destination); // Never overlay another tool input.
  const files = {};
  for (const rel of NATIVE_TOOLS_ADAPTER_FILES) {
    const file = path.join(destination, rel);
    const {stdout} = await execute('git', ['-C', repository, 'show', commit + ':' + rel], {encoding: 'buffer', maxBuffer: 1 << 28});
    await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, stdout);
    files[rel] = await fileDigest(file);
  }
  await atomicJson(path.join(destination, 'BUILD-INPUTS.json'), {repository: normalize(publicUrl), commit, files});
  return {destination, commit, files};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await deployNativeTools(...process.argv.slice(2)))); }
  catch (error) { console.error(error.stack); process.exitCode = 1; }
}
