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
const sha256 = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);

// A normal CJPM source-build is a real compiler producer, but it predates the
// native-stage handoff record.  Accept it only through an explicit adapter:
// validate the producer's existing command/result and installed bytes, while
// retaining the absence of historical C2 receipt fields.
async function ordinaryCjpmInput(supplied, input) {
  const required = ['install', 'bootstrapStd', 'buildResult', 'command', 'sourceRoot', 'sourceProduct'];
  if (!required.every(name => supplied?.[name])) throw new Error('C2_ORDINARY_LOCATIONS_REQUIRED');
  const install = await privateRoot(supplied.install), bootstrapStd = await privateRoot(supplied.bootstrapStd);
  const metadata = await readJson(path.join(install, 'STAGE-INPUTS.json'));
  const build = await readJson(supplied.buildResult), command = await readJson(supplied.command);
  const native = sdkPlatform(input.platform), tuple = native.tuple;
  const compilerFile = metadata.compilerFile || 'libexec/compiler/cjcj-stage1' + native.exe;
  if (path.isAbsolute(compilerFile) || compilerFile.split('/').some(part => part === '..'))
    throw new Error('C2_ORDINARY_COMPILER_PATH');
  const product = path.join(install, compilerFile);
  if (metadata.phase !== 'source-build' || metadata.platform !== input.platform
      || metadata.compilerCommit !== input.compiler.commit
      || metadata.runtimeCommit !== input.runtime.commit
      || !sha(metadata.compilerCommit) || !sha(metadata.runtimeCommit)
      || !sha256(metadata.compilerSha256)) throw new Error('C2_ORDINARY_STAGE_FACTS');
  if (build.rc !== 0 || build.signal || build.error
      || !Array.isArray(command.argv) || !command.argv.includes('build')
      || path.resolve(command.cwd || '') !== path.resolve(supplied.sourceRoot)
      || !command.argv.includes('--target-dir'))
    throw new Error('C2_ORDINARY_PRODUCER_MISMATCH');
  await fs.access(path.join(supplied.sourceRoot, 'cjpm.toml'));
  const sourceProduct = path.resolve(supplied.sourceProduct);
  const targetDirArg = command.argv.indexOf('--target-dir');
  const targetDirValue = targetDirArg >= 0 ? command.argv[targetDirArg + 1] : undefined;
  if (!targetDirValue || targetDirValue.startsWith('-')) throw new Error('C2_ORDINARY_TARGET_DIR');
  const targetDir = path.resolve(command.cwd, targetDirValue);
  const expectedSourceProduct = path.join(targetDir, 'release', 'bin', 'cjcj::cjc');
  if (sourceProduct !== expectedSourceProduct) throw new Error('C2_ORDINARY_COMPILER_OUTPUT');
  if (await fileDigest(product) !== metadata.compilerSha256
      || await fileDigest(sourceProduct) !== metadata.compilerSha256)
    throw new Error('C2_ORDINARY_PRODUCT_IDENTITY');
  const compilerSelection = metadata.selection?.targetComponents?.compiler;
  if (!compilerSelection?.repository || compilerSelection.commit !== metadata.compilerCommit
      || compilerSelection.commit !== input.compiler.commit)
    throw new Error('C2_ORDINARY_COMPILER_SOURCE');
  const selectedStd = metadata.selection?.targetComponents?.std?.install;
  if (selectedStd && await stdIdentity(bootstrapStd) !== await stdIdentity(selectedStd))
    throw new Error('C2_ORDINARY_STD_SOURCE');
  const stdSelection = metadata.selection?.targetComponents?.std;
  const expectedStdCommit = input.stdlib?.commit ?? input.selection?.targetComponents?.std?.commit
    ?? input.runtime.commit;
  if (!stdSelection?.repository || !sha(stdSelection.commit) || stdSelection.commit !== expectedStdCommit)
    throw new Error('C2_ORDINARY_STD_SOURCE');
  for (const header of ['RuntimeConfig.h','Cangjie.h','CangjieRuntimeLayout.h','RuntimeAPI.h','RTInterface.h'])
    if (!(await fs.readFile(path.join(install, 'include', header))).equals(await fs.readFile(path.join(input.runtime.install, 'include', header))))
      throw new Error('C2_ORDINARY_RUNTIME_HEADER ' + header);
  const llvm = path.join('third_party/llvm', native.llvmDirectory, native.llvmLibrary);
  if (await fileDigest(path.join(install, llvm)) !== await fileDigest(path.join(input.llvm.install, llvm)))
    throw new Error('C2_ORDINARY_LLVM_IDENTITY');
  await fs.access(path.join(install, 'share/cjcj/runtime_shim/cjselfhost_llvmshim.o'));
  await fs.access(path.join(install, 'share/cjcj/runtime_shim/cjc_runtime_config.o'));
  await fs.access(path.join(install, 'share/cjcj/cjo'));
  const stdCore = path.join(bootstrapStd, 'lib', tuple, 'libcangjie-std-core.a');
  const stdSha256 = await stdIdentity(bootstrapStd);
  return {
    mode: 'ordinary-cjpm', install, bootstrapStd, buildResult: path.resolve(supplied.buildResult),
    command: path.resolve(supplied.command), sourceRoot: path.resolve(supplied.sourceRoot),
    compilerFile,
    sourceProduct, compilerCommit: metadata.compilerCommit, llvmCommit: input.llvm.commit,
    bootstrapRuntimeCommit: metadata.runtimeCommit, compilerSha256: metadata.compilerSha256,
    compilerSource: {repository: compilerSelection.repository, commit: compilerSelection.commit,
      sourceRoot: path.resolve(supplied.sourceRoot), product: sourceProduct,
      install: product, file: compilerFile},
    stdSource: {repository: stdSelection.repository, commit: stdSelection.commit,
      install: bootstrapStd, identity: stdSha256},
    stdSha256,
    stdCoreSha256: await fileDigest(stdCore),
  };
}
export async function stage2Input(supplied, input) {
  if (supplied?.mode === 'ordinary-cjpm') return ordinaryCjpmInput(supplied, input);
  if (!supplied?.install || !supplied.bootstrapStd || !supplied.parentProduct || !supplied.buildResult)
    throw new Error('C2_REUSE_LOCATIONS_REQUIRED');
  const install = await privateRoot(supplied.install), bootstrapStd = await privateRoot(supplied.bootstrapStd);
  const native = sdkPlatform(input.platform), tuple = native.tuple;
  const compilerInputs = path.join(install, 'compiler-inputs.json');
  const facts = await readJson(compilerInputs), metadata = await readJson(path.join(install, 'STAGE-INPUTS.json'));
  const build = await readJson(supplied.buildResult);
  const compilerFile = metadata.compilerFile || 'libexec/compiler/cjcj-stage1' + native.exe;
  if (path.isAbsolute(compilerFile) || compilerFile.split('/').some(part => part === '..'))
    throw new Error('C2_REUSE_COMPILER_PATH');
  const product = path.join(install, compilerFile);
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
  for (const name of ['cjselfhost_llvmshim.o','cjc_runtime_config.o','cjc_heap_defaults.o'])
    await fs.access(path.join(install,'share/cjcj/runtime_shim',name));
  await fs.access(path.join(install,'share/cjcj/cjo'));
  // These are source/configuration facts. No new PASS or authority is minted.
  return {install, bootstrapStd, parentProduct:path.resolve(supplied.parentProduct),
    buildResult:path.resolve(supplied.buildResult), compilerInputs, compilerCommit:facts.commit,
    parentCommit:input.h1.commit, llvmCommit:input.llvm.commit, bootstrapRuntimeCommit:metadata.runtimeCommit,
    compilerSha256:facts.compilerSha256, parentSha256:facts.parentSha256,
    stdSha256:facts.stdSha256, stdCoreSha256:facts.stdCoreSha256};
}
