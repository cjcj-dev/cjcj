#!/usr/bin/env zx
// Cross-platform two-sample compile/run smoke, followed by a pinned-runtime
// combination smoke when the runtime stage produced a host library.

import fs from 'node:fs/promises';
import path from 'node:path';
import {printCommonVersions, stageBegin, toCommandPath} from './common.mjs';

const {root} = stageBegin('test');
await printCommonVersions();
const exeSuffix = process.platform === 'win32' ? '.exe' : '';

if (process.platform === 'darwin' && !process.env.SDKROOT) {
  // The cjcj Darwin driver consumes SDKROOT for -syslibroot; without it every
  // smoke link probes / and misses libSystem.tbd (rounds 19-20). Set it before
  // the FIRST runOne — the two-sample smoke, not just the combined one.
  process.env.SDKROOT = (await $({stdio: 'pipe', verbose: false})`xcrun --sdk macosx --show-sdk-path`).stdout.trim();
  console.log(`smoke SDKROOT=${process.env.SDKROOT}`);
}

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
const productNames = process.platform === 'win32' ? ['cjcj.exe'] : ['cjcj::cjc', 'cjcj', 'cjc'];
for (const name of productNames) {
  const candidate = path.join('target', 'release', 'bin', name);
  if (await isFile(candidate)) { product = candidate; break; }
}
if (!product) {
  product = await findFirst('target', (name) => productNames.includes(name));
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
if (process.platform === 'win32') {
  // Same-directory DLL resolution always wins on Windows (see the tuple llc
  // staging in build_cjcj.mjs); stage the runtime and MinGW DLLs next to the
  // deployed compiler so a PATH miss cannot produce a silent loader 127.
  const dllSources = [path.join(process.env.CANGJIE_HOME || '', 'runtime', 'lib', 'windows_x86_64_cjnative')];
  for (const dir of ['C:\\mingw64\\bin', 'C:\\msys64\\mingw64\\bin']) dllSources.push(dir);
  const wanted = ['libcangjie-runtime.dll', 'cangjie-runtime.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll', 'libgcc_s_seh-1.dll'];
  for (const name of wanted) {
    for (const dir of dllSources) {
      const source = path.join(dir, name);
      if (await isFile(source)) {
        await fs.copyFile(source, path.join(bin, name));
        console.log(`staged ${name} from ${dir}`);
        break;
      }
    }
  }
  const imports = await $({nothrow: true, stdio: 'pipe'})`objdump -p ${toCommandPath(deploy)}`;
  const importNames = [...imports.stdout.matchAll(/DLL Name: (\S+)/g)].map((m) => m[1]);
  console.log(`import table: ${importNames.join(' ') || '(objdump unavailable)'}`);
  for (const name of importNames) {
    const local = await isFile(path.join(bin, name));
    const located = local ? 'staged' : (await $({nothrow: true, stdio: 'pipe'})`where ${name}`).stdout.split(/\r?\n/).find(Boolean) || 'MISSING';
    console.log(`import ${name}: ${located}`);
  }
}
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
await $({nothrow: true})`${toCommandPath(deploy)} --version`;

async function runOne(name, expected, env = process.env) {
  const output = path.join(root, `${name}${exeSuffix}`);
  await $({env})`${toCommandPath(deploy)} ${toCommandPath(path.join('ci', 'smoke', `${name}.cj`))} -o ${toCommandPath(output)}`;
  const got = (await $({env, stdio: 'pipe', verbose: false})`${toCommandPath(output)}`).stdout.trimEnd();
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
