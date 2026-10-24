#!/usr/bin/env zx
// An existing C2 is an input product, not a successful bootstrap run. Its
// original failed installed gate remains evidence; the new installation is gated.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readJson, fileDigest, privateRoot} from './sdk-flow.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {stdIdentity} from '../srcbuild/lib/final-compiler.mjs';
const execute = promisify(execFile);
const sha = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);
export async function stage2Input(supplied, input) {
  if (!supplied?.install || !supplied.bootstrapStd || !supplied.parentProduct || !supplied.buildResult)
    throw new Error('C2_REUSE_LOCATIONS_REQUIRED');
  const install = await privateRoot(supplied.install), bootstrapStd = await privateRoot(supplied.bootstrapStd);
  const native = sdkPlatform(input.platform), tuple = native.tuple;
  const compilerInputs = path.join(install, 'compiler-inputs.json');
  const facts = await readJson(compilerInputs), metadata = await readJson(path.join(install, 'STAGE-INPUTS.json'));
  const build = await readJson(supplied.buildResult);
  const product = path.join(install, 'libexec/compiler/cjcj-stage1' + native.exe);
  const parent = await readJson(path.join(path.dirname(supplied.parentProduct),'build-inputs.json'));
  if(parent.source!==input.h1.commit || parent.sha256!==facts.parentSha256)throw new Error('C2_REUSE_H1_SOURCE');
  if (!sha(facts.commit) || metadata.compilerCommit !== facts.commit || metadata.phase !== 'stage2'
      || metadata.platform !== input.platform || metadata.compilerRole !== 'r-host-compiler'
      || !sha(metadata.runtimeCommit) || !facts.sourceProduct || !facts.sourceBuildResult
      || path.resolve(facts.sourceBuildResult) !== path.resolve(supplied.buildResult)
      || build.rc !== 0 || build.signal || build.cut || build.error || !build.cwd || !build.argv?.includes('build')
      || path.relative(build.cwd, facts.sourceProduct).split(path.sep).slice(0,3).join('/') !== 'target/release/bin')
    throw new Error('C2_REUSE_PRODUCER_MISMATCH');
  const git = async (repo, object) => (await execute('git', ['-C', repo, 'rev-parse', '--verify', object])).stdout.trim();
  if (await git(input.compiler.repository, facts.commit + '^{commit}') !== facts.commit)
    throw new Error('C2_REUSE_COMPILER_SOURCE');
  const macro = async commit => (await execute('git', ['-C', input.compiler.repository, 'show', commit + ':packages/macro/src/InvokeUtil.cj'])).stdout;
  if (await macro(facts.commit) !== await macro(input.compiler.commit))throw new Error('C2_REUSE_MACRO_SOURCE');
  // Reusing bootstrap std requires identical std sources, not just ELF symbols.
  if (await git(input.runtime.repository, metadata.runtimeCommit + ':stdlib')
      !== await git(input.runtime.repository, input.runtime.commit + ':stdlib'))throw new Error('C2_REUSE_STD_SOURCE');
  for (const header of ['RuntimeConfig.h','Cangjie.h','CangjieRuntimeLayout.h','RuntimeAPI.h','RTInterface.h'])
    if (!(await fs.readFile(path.join(install,'include',header))).equals(await fs.readFile(path.join(input.runtime.install,'include',header))))
      throw new Error('C2_REUSE_RUNTIME_HEADER ' + header);
  if (await fileDigest(product) !== facts.compilerSha256 || metadata.compilerSha256 !== facts.compilerSha256
      || await fileDigest(facts.sourceProduct) !== facts.compilerSha256
      || await fileDigest(supplied.parentProduct) !== facts.parentSha256
      || await stdIdentity(bootstrapStd) !== facts.stdSha256
      || await fileDigest(path.join(bootstrapStd,'lib',tuple,'libcangjie-std-core.a')) !== facts.stdCoreSha256
      || await fileDigest(path.join(install,'lib',tuple,'libcangjie-std-core.a')) !== facts.stdCoreSha256)
    throw new Error('C2_REUSE_PRODUCT_IDENTITY');
  const llvm = path.join('third_party/llvm',native.llvmDirectory,native.llvmLibrary);
  if (await fileDigest(path.join(install,llvm)) !== await fileDigest(path.join(input.llvm.install,llvm)))
    throw new Error('C2_REUSE_LLVM_IDENTITY');
  for (const name of ['cjselfhost_llvmshim.o','cjc_runtime_config.o'])
    await fs.access(path.join(install,'share/cjcj/runtime_shim',name));
  await fs.access(path.join(install,'share/cjcj/cjo'));
  // These are source/configuration facts. No new PASS or authority is minted.
  return {install, bootstrapStd, parentProduct:path.resolve(supplied.parentProduct),
    buildResult:path.resolve(supplied.buildResult), compilerInputs, compilerCommit:facts.commit,
    parentCommit:input.h1.commit, llvmCommit:input.llvm.commit, bootstrapRuntimeCommit:metadata.runtimeCommit,
    compilerSha256:facts.compilerSha256, parentSha256:facts.parentSha256,
    stdSha256:facts.stdSha256, stdCoreSha256:facts.stdCoreSha256};
}
