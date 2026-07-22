#!/usr/bin/env zx
// Cross-platform two-sample compile/run smoke, followed by a pinned-runtime
// combination smoke when the runtime stage produced a host library.

import fs from 'node:fs/promises';
import path from 'node:path';
import {printCommonVersions, stageBegin} from './common.mjs';

const {root} = stageBegin('test');
await printCommonVersions();
const exeSuffix = process.platform === 'win32' ? '.exe' : '';

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}

async function findFirst(directory, predicate) {
  let entries;
  try { entries = await fs.readdir(directory, {withFileTypes: true}); } catch { return ''; }
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isFile() && predicate(entry.name)) return target;
    if (entry.isDirectory()) {
      const found = await findFirst(target, predicate);
      if (found) return found;
    }
  }
  return '';
}

let product = '';
for (const candidate of [
  path.join('target', 'release', 'bin', `cjcj::cjc${exeSuffix}`),
  path.join('target', 'release', 'bin', `cjcj${exeSuffix}`),
  path.join('target', 'release', 'bin', `cjc${exeSuffix}`),
]) {
  if (await isFile(candidate)) { product = candidate; break; }
}
if (!product) {
  product = await findFirst('target', (name) => name === 'cjcj::cjc' || name === 'cjcj' || /^cjcj.*\.exe$/i.test(name));
}
if (!product) {
  console.error('FATAL: cjcj build product not found; cjcj stage did not reach link success');
  process.exit(2);
}

const bin = path.join(root, 'bin');
const deploy = path.join(bin, `cjcj${exeSuffix}`);
await fs.mkdir(bin, {recursive: true});
await fs.copyFile(product, deploy);
try { await fs.chmod(deploy, 0o755); } catch {}
if (process.env.CANGJIE_HOME) {
  const sourceRuntime = path.join(process.env.CANGJIE_HOME, 'runtime');
  const targetRuntime = path.join(root, 'runtime');
  try {
    await fs.access(targetRuntime);
  } catch {
    try { await fs.cp(sourceRuntime, targetRuntime, {recursive: true}); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}
await $({nothrow: true})`${deploy} --version`;

async function runOne(name, expected, env = process.env) {
  const output = path.join(root, `${name}${exeSuffix}`);
  await $({env})`${deploy} ${path.join('ci', 'smoke', `${name}.cj`)} -o ${output}`;
  const got = (await $({env, stdio: 'pipe', verbose: false})`${output}`).stdout.trimEnd();
  console.log(`${name} => [${got}]`);
  if (got !== expected) {
    console.error(`ERROR: ${name} expected [${expected}], got [${got}]`);
    return false;
  }
  return true;
}
if (!(await runOne('01_hello', 'hello from cjcj'))) process.exit(1);
if (!(await runOne('02_generics', '42 hi 7'))) process.exit(1);

const runtimeLib = await findFirst(path.join(root, 'runtime-install'), (name) =>
  ['libcangjie-runtime.so', 'libcangjie-runtime.dylib', 'libcangjie-runtime.dll', 'cangjie-runtime.dll'].includes(name.toLowerCase()),
);
if (!runtimeLib) {
  console.error('ERROR: combined runtime smoke unavailable: runtime stage produced no host library');
  process.exit(3);
}
console.log(`combined runtime smoke: ${runtimeLib}`);
const runtimeDir = path.dirname(runtimeLib);
const env = {...process.env};
if (process.platform === 'darwin') env.DYLD_LIBRARY_PATH = `${runtimeDir}:${env.DYLD_LIBRARY_PATH || ''}`;
else if (process.platform === 'win32') env.PATH = `${runtimeDir};${env.PATH || ''}`;
else env.LD_LIBRARY_PATH = `${runtimeDir}:${env.LD_LIBRARY_PATH || ''}`;
if (!(await runOne('01_hello', 'hello from cjcj', env))) process.exit(1);
