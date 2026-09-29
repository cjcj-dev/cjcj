#!/usr/bin/env node
// Shared pre-build check, including tuple/shim reuse paths.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutExactSource} from '../build/lib/git.mjs';
import {run} from '../build/lib/runner.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
function pin(file) {
  return Object.fromEntries(fs.readFileSync(path.join(repo, 'ci', file), 'utf8')
    .split(/\r?\n/).filter(line => /^[A-Z_]+=/.test(line)).map(line => line.split('=')));
}
export async function checkCodegenRuntimeLayout(sourceRoot = path.join(repo, 'target/layout-sources')) {
  const llvm = pin('llvm_pin.env');
  const runtime = pin('runtime_pin.env');
  const sources = [
    ['llvm', llvm.LLVM_URL, llvm.LLVM_SHA],
    ['runtime', runtime.RUNTIME_SRC_URL, runtime.RUNTIME_REF],
  ];
  // Reuse only commit-addressed sources. The checker reads git objects, never
  // dirty checkout contents. Tuple reuse does not bypass source validation.
  await Promise.all(sources.map(async ([name, url, sha]) => {
    const dest = path.join(sourceRoot, name);
    const present = await run(['git', '-C', dest, 'cat-file', '-e', `${sha}^{commit}`],
      {check: false, capture: true, logOutput: false});
    if (present.exitCode !== 0) await checkoutExactSource(url, dest, sha);
  }));
  await run(['bash', path.join(repo, 'ci/check-llvm-runtime-abi.sh').replaceAll('\\', '/'),
    '--llvm-repo', path.join(sourceRoot, 'llvm'), '--llvm-ref', llvm.LLVM_SHA,
    '--runtime-repo', path.join(sourceRoot, 'runtime'), '--runtime-ref', runtime.RUNTIME_REF]);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await checkCodegenRuntimeLayout(process.argv[2]);
}
