#!/usr/bin/env zx
// Shared ten-payload publisher for GHA and the kkk2 depot.
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {tuplePlatforms} from './release/tuple_platform.mjs';

export async function publishFixedTupleToDepot(depotRoot, env = process.env) {
  depotRoot ||= env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot';
  const {LLVM_SHA = '', CANGJIE_COMPILER_SHA = '', REPO_ROOT = '', CJCJ_FIXED_LLVM_DIR = ''} = env;
  const platforms = fs.readFileSync(path.join(CJCJ_FIXED_LLVM_DIR, 'llvm-tools.manifest'), 'utf8')
    .split('\n').filter(line => line.startsWith('PLATFORM=')).map(line => line.slice(9));
  const platform = platforms[0];
  if (platforms.length !== 1 || !tuplePlatforms.includes(platform)) throw new Error('BOOTSTRAP_TUPLE_PLATFORM_UNSUPPORTED');
  const linker = platform.startsWith('darwin_') ? 'ld64.lld' : 'ld.lld';
  const depot = `${depotRoot}/${LLVM_SHA}/${CANGJIE_COMPILER_SHA}`;
  const tuple = `${depot}/fixed-llc`;
  if (!LLVM_SHA || !CANGJIE_COMPILER_SHA) return 1;
  const command = async (args, {capture = false} = {}) => {
    const result = await $({quiet: true, nothrow: true, env})`${args}`;
    process.stderr.write(result.stderr);
    if (!capture) process.stdout.write(result.stdout);
    return result;
  };
  const recipe = await command(['git', '-C', REPO_ROOT, 'rev-parse', 'HEAD'], {capture: true});
  if (recipe.exitCode !== 0) return 1;
  const recipeSha = recipe.stdout.replace(/\n+$/, '');
  if ((await command(['mkdir', '-p', tuple, `${depot}/bin`, `${depot}/lib`])).exitCode !== 0) return 1;
  for (const payload of ['llc.gz', 'opt.gz', `${linker}.gz`, 'cjselfhost_llvmshim.o', 'llvm-tools.manifest']) {
    if ((await command(['cp', '--', `${CJCJ_FIXED_LLVM_DIR}/${payload}`, `${tuple}/${payload}`])).exitCode !== 0) return 1;
  }
  for (const payload of ['llc', 'opt', linker]) {
    const result = await $({quiet: true, nothrow: true, env})`gzip -dc ${`${tuple}/${payload}.gz`} > ${`${depot}/bin/${payload}`}`;
    process.stderr.write(result.stderr);
    if (result.exitCode !== 0) return 1;
    if ((await command(['chmod', '+x', `${depot}/bin/${payload}`])).exitCode !== 0) return 1;
  }
  const written = await $({quiet: true, nothrow: true, env})`{
    printf 'PLATFORM=%s\n' ${platform}
    printf 'LLVM_SHA=%s\n' ${LLVM_SHA}
    printf 'CANGJIE_COMPILER_SHA=%s\n' ${CANGJIE_COMPILER_SHA}
    printf 'RECIPE_CJCJ_SHA=%s\n' ${recipeSha}
    printf 'RUNTIME_REF=%s\n' ${env.CJCJ_NATIVE_RUNTIME_REF || ''}
    printf 'DEPOT_ROLE=byte-identical mirror\n'
  } > ${`${depot}/MANIFEST`} || exit 1`;
  process.stderr.write(written.stderr);
  if (written.exitCode !== 0) return 1;
  if ((await command(['cp', '--', `${depot}/MANIFEST`, `${depot}/lib/STATIC_LLVM.txt`])).exitCode !== 0) return 1;
  const files = ['./MANIFEST', './bin/llc', './bin/opt', `./bin/${linker}`, './lib/STATIC_LLVM.txt',
    './fixed-llc/llc.gz', './fixed-llc/opt.gz', `./fixed-llc/${linker}.gz`,
    './fixed-llc/cjselfhost_llvmshim.o', './fixed-llc/llvm-tools.manifest'];
  if (platform.startsWith('darwin_')) {
    fs.writeFileSync(path.join(depot, 'SHA256SUMS'), files.map(file =>
      `${createHash('sha256').update(fs.readFileSync(path.join(depot, file))).digest('hex')}  ${file}\n`).join(''));
    return (await command(['echo', `published fixed LLVM tuple to depot ${depot}`])).exitCode;
  }
  const sums = await $({quiet: true, nothrow: true, env})`cd ${depot} && sha256sum -- ${files} > SHA256SUMS`;
  process.stderr.write(sums.stderr);
  if (sums.exitCode !== 0) return 1;
  // Preserve the shell builtin's output and final function status, including
  // stdout failures. This status also reaches callers running with set -e.
  return (await command(['echo', `published fixed LLVM tuple to depot ${depot}`])).exitCode;
}
const entryIndex = process.argv.findIndex((arg, i) => i > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
if (entryIndex !== -1) process.exitCode = await publishFixedTupleToDepot(process.argv[entryIndex + 1]);
