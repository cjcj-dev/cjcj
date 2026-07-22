// Shared environment, compiler invocation, and artifact helpers for serialization persistence tests.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export const repo = path.resolve(import.meta.dirname, '../..');
export const fixture = path.join(repo, 'scripts/septest');
export const reference = process.env.REF_CJC || '/root/.cjv/bin/cjc';
export const selfhost = process.env.SELF_CJC || `${repo}/target/release/bin/cjcj::cjc`;
export const home = process.env.CANGJIE_HOME || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029';
process.env.CANGJIE_HOME = home;
process.env.LD_LIBRARY_PATH = `${home}/third_party/llvm/lib:${home}/runtime/lib/linux_x86_64_cjnative:${home}/tools/lib:${process.env.LD_LIBRARY_PATH || ''}`;

export async function makeWork(prefix) { return fs.mkdtemp(path.join(os.tmpdir(), prefix)); }
export function output(result) { return result.stdout.replace(/\n+$/, ''); }
export function fail(prefix, message) { console.log(`${prefix}-FAIL ${message}`); process.exit(1); }
export async function ensureInputs(prefix, work) {
  try { await fs.access(reference, fs.constants.X_OK); } catch { fail(prefix, `missing reference cjc at ${reference}`); }
  try { await fs.access(selfhost, fs.constants.X_OK); } catch { fail(prefix, `missing selfhost cjc at ${selfhost}`); }
  try { if (!(await fs.stat(home)).isDirectory()) throw new Error(); } catch { fail(prefix, `missing CANGJIE_HOME at ${home}`); }
  await fs.mkdir(work, {recursive: true});
}
export async function invoke(compiler, args, stdoutFile, stderrFile) {
  const result = await $({nothrow: true, quiet: true})`${compiler} ${args}`;
  if (stdoutFile) await fs.writeFile(stdoutFile, result.stdout);
  if (stderrFile) await fs.writeFile(stderrFile, result.stderr);
  return result;
}
export async function run(binary, stderrFile) {
  const result = await $({nothrow: true, quiet: true})`${binary}`;
  if (stderrFile) await fs.writeFile(stderrFile, result.stderr);
  return result;
}
export async function copy(sourceRelative, destination) {
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.copyFile(path.join(fixture, sourceRelative), destination);
}
