#!/usr/bin/env zx
// Shared ten-payload publisher for GHA and the kkk2 depot.
import {fileURLToPath} from 'node:url';
import path from 'node:path';

export async function publishFixedTupleToDepot(depotRoot, env = process.env) {
  depotRoot ||= env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot';
  const {LLVM_SHA = '', CANGJIE_COMPILER_SHA = '', REPO_ROOT = '', CJCJ_FIXED_LLVM_DIR = ''} = env;
  const depot = `${depotRoot}/${LLVM_SHA}/${CANGJIE_COMPILER_SHA}`;
  const tuple = `${depot}/fixed-llc`;
  if (!LLVM_SHA || !CANGJIE_COMPILER_SHA) return 1;
  const command = async (args, options = {}) => {
    const result = await $({quiet: true, nothrow: true, env, ...options})`${args}`;
    process.stderr.write(result.stderr);
    return result;
  };
  const recipe = await command(['git', '-C', REPO_ROOT, 'rev-parse', 'HEAD']);
  if (recipe.exitCode !== 0) return 1;
  const recipeSha = recipe.stdout.replace(/\n+$/, '');
  if ((await command(['mkdir', '-p', tuple, `${depot}/bin`, `${depot}/lib`])).exitCode !== 0) return 1;
  for (const payload of ['llc.gz', 'opt.gz', 'ld.lld.gz', 'cjselfhost_llvmshim.o', 'llvm-tools.manifest']) {
    if ((await command(['cp', '--', `${CJCJ_FIXED_LLVM_DIR}/${payload}`, `${tuple}/${payload}`])).exitCode !== 0) return 1;
  }
  for (const payload of ['llc', 'opt', 'ld.lld']) {
    const result = await $({quiet: true, nothrow: true, env})`gzip -dc ${`${tuple}/${payload}.gz`} > ${`${depot}/bin/${payload}`}`;
    process.stderr.write(result.stderr);
    if (result.exitCode !== 0) return 1;
    if ((await command(['chmod', '+x', `${depot}/bin/${payload}`])).exitCode !== 0) return 1;
  }
  const manifest = `PLATFORM=linux_x86_64\nLLVM_SHA=${LLVM_SHA}\nCANGJIE_COMPILER_SHA=${CANGJIE_COMPILER_SHA}\nRECIPE_CJCJ_SHA=${recipeSha}\nDEPOT_ROLE=byte-identical mirror\n`;
  const written = await $({quiet: true, nothrow: true, env})`printf '%s' ${manifest} > ${`${depot}/MANIFEST`}`;
  process.stderr.write(written.stderr);
  if (written.exitCode !== 0) return 1;
  if ((await command(['cp', '--', `${depot}/MANIFEST`, `${depot}/lib/STATIC_LLVM.txt`])).exitCode !== 0) return 1;
  const files = ['./MANIFEST', './bin/llc', './bin/opt', './bin/ld.lld', './lib/STATIC_LLVM.txt',
    './fixed-llc/llc.gz', './fixed-llc/opt.gz', './fixed-llc/ld.lld.gz',
    './fixed-llc/cjselfhost_llvmshim.o', './fixed-llc/llvm-tools.manifest'];
  const sums = await $({quiet: true, nothrow: true, env, cwd: depot})`sha256sum -- ${files} > SHA256SUMS`;
  process.stderr.write(sums.stderr);
  if (sums.exitCode !== 0) return 1;
  console.log(`published fixed LLVM tuple to depot ${depot}`);
  return 0;
}
const entryIndex = process.argv.findIndex((arg, i) => i > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
if (entryIndex !== -1) process.exitCode = await publishFixedTupleToDepot(process.argv[entryIndex + 1]);
