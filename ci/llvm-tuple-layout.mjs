#!/usr/bin/env zx
// Shared ten-payload publisher for GHA and the kkk2 depot.
import {fs, path, repo, pin, capture, cliArgs, isMain} from './script-common.mjs';
import {gunzipSync} from 'node:zlib';
export async function publishFixedTupleToDepot(depotRoot = process.env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot', env = process.env) {
  const {LLVM_SHA, CANGJIE_COMPILER_SHA, CJCJ_FIXED_LLVM_DIR, REPO_ROOT = repo} = env;
  if (!LLVM_SHA || !CANGJIE_COMPILER_SHA) throw new Error('missing tuple identities');
  const recipeSha = (await capture(['git', '-C', path.resolve(REPO_ROOT), 'rev-parse', 'HEAD'])).stdout.trim();
  const depot = path.join(depotRoot, LLVM_SHA, CANGJIE_COMPILER_SHA);
  const tuple = path.join(depot, 'fixed-llc');
  for (const dir of [tuple, path.join(depot, 'bin'), path.join(depot, 'lib')]) fs.mkdirSync(dir, {recursive: true});
  for (const payload of ['llc.gz', 'opt.gz', 'ld.lld.gz', 'cjselfhost_llvmshim.o', 'llvm-tools.manifest'])
    fs.copyFileSync(path.join(CJCJ_FIXED_LLVM_DIR, payload), path.join(tuple, payload));
  for (const payload of ['llc', 'opt', 'ld.lld']) {
    const output = path.join(depot, 'bin', payload);
    // Redirect without text decoding: executables must remain byte-identical.
    fs.writeFileSync(output, gunzipSync(fs.readFileSync(path.join(tuple, `${payload}.gz`))));
    fs.chmodSync(output, 0o755);
  }
  fs.writeFileSync(path.join(depot, 'MANIFEST'), `PLATFORM=linux_x86_64\nLLVM_SHA=${LLVM_SHA}\nCANGJIE_COMPILER_SHA=${CANGJIE_COMPILER_SHA}\nRECIPE_CJCJ_SHA=${recipeSha}\nDEPOT_ROLE=byte-identical mirror\n`);
  fs.copyFileSync(path.join(depot, 'MANIFEST'), path.join(depot, 'lib/STATIC_LLVM.txt'));
  const files = ['./MANIFEST', './bin/llc', './bin/opt', './bin/ld.lld', './lib/STATIC_LLVM.txt',
    './fixed-llc/llc.gz', './fixed-llc/opt.gz', './fixed-llc/ld.lld.gz', './fixed-llc/cjselfhost_llvmshim.o', './fixed-llc/llvm-tools.manifest'];
  fs.writeFileSync(path.join(depot, 'SHA256SUMS'), (await capture(['sha256sum', '--', ...files], {cwd: depot})).stdout);
  console.log(`published fixed LLVM tuple to depot ${depot}`);
  return depot;
}
if (isMain(import.meta.url)) {
  try { await publishFixedTupleToDepot(cliArgs[0], {...pin(path.join(repo, 'ci/llvm_pin.env')), ...process.env}); }
  catch (error) { console.error(error.message); process.exitCode ||= 1; }
}
