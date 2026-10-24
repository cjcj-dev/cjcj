#!/usr/bin/env node
// Shared pre-build check, including tuple/shim reuse paths.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutExactSource} from '../build/lib/git.mjs';
import {run} from '../build/lib/runner.mjs';
import {resolveRuntimeSource} from './runtime-pin.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
function pin(file) {
  return Object.fromEntries(fs.readFileSync(path.join(repo, 'ci', file), 'utf8')
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line)).map(line => line.split('=')));
}
export async function checkCodegenRuntimeLayout(sourceRoot = path.join(repo, 'target/layout-sources'), runtimePin = process.env.CJCJ_BOOTSTRAP_RUNTIME_PIN, llvmSha) {
  const llvm = pin('llvm_pin.env');
  llvmSha ??= process.env.CJCJ_SRCBUILD_LLVM_REF || llvm.LLVM_SHA;
  if (!/^[0-9a-f]{40}$/.test(llvmSha)) throw new Error('LLVM source must be an explicit 40-digit SHA');
  const runtime = await resolveRuntimeSource(process.env, runtimePin);
  const sources = [
    ['llvm', llvm.LLVM_URL, llvmSha],
    ['runtime', runtime.sourceUrl, runtime.runtimeRef],
  ];
  // Reuse only commit-addressed sources. The checker reads git objects, never
  // dirty checkout contents. Tuple reuse does not bypass source validation.
  const repositories = {};
  await Promise.all(sources.map(async ([name, url, sha]) => {
    const supplied = process.env[`CJCJ_SRCBUILD_${name.toUpperCase()}_SOURCE`];
    const dest = supplied || path.join(sourceRoot, name);
    repositories[name] = dest;
    const present = await run(['git', '-C', dest, 'cat-file', '-e', `${sha}^{commit}`],
      {check: false, capture: true, logOutput: false});
    if (present.exitCode !== 0) {
      if (supplied) throw new Error(`supplied ${name} source does not contain ${sha}: ${dest}`);
      await checkoutExactSource(url, dest, sha);
    }
  }));
  await run(['npx', '--yes', 'zx@8', path.join(repo, 'ci/check-llvm-runtime-abi.mjs').replaceAll('\\', '/'),
    '--llvm-repo', repositories.llvm, '--llvm-ref', llvmSha,
    '--runtime-repo', repositories.runtime, '--runtime-ref', runtime.runtimeRef]);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await checkCodegenRuntimeLayout(process.argv[2], process.argv[3], process.argv[4]);
}
