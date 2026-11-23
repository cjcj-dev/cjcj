// Native producers: LLVM/AST/cjdb (one configuration) and the paired runtime + boundscheck build.
import fs from 'node:fs';
import path from 'node:path';

export function nativeConfig({template, sources, build, install, commits, jobs = 24, linkJobs = 2}) {
  const cfg = JSON.parse(fs.readFileSync(template, 'utf8'));
  Object.assign(cfg, {compiler: sources.ast, llvm: sources.llvm, runtime: sources.runtime, shimSource: sources.cjcj, build, install, jobs, linkJobs});
  Object.assign(cfg.commits, {llvm: commits.llvm, runtime: commits.runtime, shim: commits.cjcj});
  if (cfg.commits.compiler !== commits.ast) throw new Error(`NATIVE_AST_COMMIT ${cfg.commits.compiler} != ${commits.ast}`);
  return cfg;
}

export function nativeSteps({cjcj, config, runtimeEnv, zx}) {
  return [
    {label: 'native-llvm', argv: [process.execPath, path.join(cjcj, 'ci/bootstrap/native-cjdb.mjs'), config]},
    {label: 'native-runtime', argv: [zx, path.join(cjcj, 'build/sdk/producers/platform_matrix/build_runtime.mjs')], env: runtimeEnv, cwd: cjcj},
  ];
}

// Read the paired identities produced above; they must name the same LLVM, runtime and host.
export function readNativeBinding({nativeInstall, runtimeInstall, commits, hostVersion}) {
  const nf = JSON.parse(fs.readFileSync(path.join(nativeInstall, 'BUILD-INPUTS.json'), 'utf8'));
  const rf = JSON.parse(fs.readFileSync(path.join(runtimeInstall, 'NATIVE-INPUTS.json'), 'utf8'));
  const got = [nf.commits.llvm, nf.commits.runtime, nf.commits.shim, nf.commits.compiler, rf.runtime_sha, rf.paired_llvm_sha, rf.configuration.hostVersion];
  const want = [commits.llvm, commits.runtime, commits.cjcj, commits.ast, commits.runtime, commits.llvm, hostVersion];
  for (let i = 0; i < got.length; ++i) if (got[i] !== want[i]) throw new Error(`NATIVE_MIXED_GENERATION ${i}: ${got[i]} != ${want[i]}`);
  return {nf, rf};
}
