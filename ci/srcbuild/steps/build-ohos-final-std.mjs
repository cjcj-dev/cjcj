#!/usr/bin/env zx
import {crossBuildJobs} from '../lib/cross-build-jobs.mjs';
// Shape: build-windows-final-std.mjs; official cangjie_build/docs/linux_cross_ohos.md:203-228.
// #1196 supplies runtime/build.py --ohos-public-sdk for both architectures.
import fs from 'node:fs/promises';
import {CROSS_STD_BUILDS} from '../../../build/lib/targets.mjs';
import path from 'node:path';
import {assertBootstrapCompiler} from '../lib/bootstrap-handoff.mjs';
import {installedStageOutput} from '../lib/installed-stage-output.mjs';
import {verifyStdBuildInputs} from '../../bootstrap/stdlib-build.mjs';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
import {cleanSdkEnvironment} from '../../bootstrap/sdk-platform.mjs';
import {checkPair, checkAst, copyHost, astFile, installOhosStage3} from '../lib/ohos-split-sdk.mjs';
import {buildOhosRuntime} from '../lib/ohos-runtime.mjs';

$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
if (process.platform !== 'linux' || process.arch !== 'x64') {
  throw new Error('OHOS producer requires the linux-x64 source cell');
}
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be a filesystem root');
const version = required('CJCJ_STAGE3_CANGJIE_VERSION');
const expectedRef = required('CJCJ_NATIVE_RUNTIME_REF');
const probe = probeRequirement('ohos-sdk');
if (!probe.present) throw new Error(probe.detail);
const ohos = path.resolve(probe.detail.slice(probe.detail.indexOf('=') + 1));
const native = path.join(ohos, 'native');
const toolchain = path.join(native, 'llvm');
const parentSdk = path.join(path.resolve(required('CJCJ_BOOTSTRAP_WORK')), 'sdk-stage2');
const originalCompiler = await installedStageOutput(parentSdk, 'stage2');
const repository = path.join(workspace, 'cangjie_runtime');
const runtime = path.join(repository, 'runtime');
const stdlib = path.join(repository, 'stdlib');
const runtimeRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
// Each matrix job restores its own stage3 handoff; no architecture shares a build tree.
const build = CROSS_STD_BUILDS.find(row => row.family === 'ohos' && row.tuple === required('CROSS_STD_TUPLE'));
if (!build) throw new Error('unsupported OHOS cross std tuple');
const {arch, tuple} = build;
const finalStd = path.join(workspace, 'software', build.artifact);
const splitRef = process.env.CJCJ_OHOS_RUNTIME_REF;
const split = splitRef !== undefined;
let parent3, archive;
if (split) {
  checkPair(originalCompiler.lineage, expectedRef, splitRef, runtimeRef, tuple);
  parent3 = await fs.realpath(required('CJCJ_OHOS_PARENT_STAGE3'));
  checkPair((await installedStageOutput(parent3, 'stage3')).lineage, expectedRef, splitRef, runtimeRef, tuple);
  archive = await fs.realpath(required('CJCJ_OHOS_AST_ARCHIVE'));
  await checkAst(archive);
  await $`git -C ${repository} diff --quiet HEAD`;
} else if (runtimeRef !== expectedRef || runtimeRef !== originalCompiler.lineage.runtimeCommit) {
  throw new Error(`runtime source mismatch: expected host=${originalCompiler.lineage.runtimeCommit} requested=${expectedRef} actual target=${runtimeRef}`);
}
const sdk = split ? await fs.mkdtemp(path.join(workspace, '.ohos-stage2-')) : parentSdk;
try {
  if (split) await copyHost(parentSdk, sdk);
  const env = split ? cleanSdkEnvironment(sdk, 'linux_x86_64') : process.env;
  const stageEnv = {...env, CANGJIE_HOME: sdk, CANGJIE_VERSION: version,
    PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin'), path.join(toolchain, 'bin'), env.PATH].join(path.delimiter)};
  const assertCompiler = async () => {
    const command = (await $({env: stageEnv, stdio: 'pipe'})`command -v cjc`).stdout.trim();
    await assertBootstrapCompiler({sdk, command, producer: originalCompiler.product, producerSha256: originalCompiler.lineage.compilerSha256});
  };
  await assertCompiler();
  const runtimeInstall = await buildOhosRuntime({workspace, native, arch, version, runtimeRef, localExport:split, env: stageEnv});
  await assertCompiler();
  await verifyStdBuildInputs(sdk);
  const extraLibs = [];
  if (split) {
    for (const dir of ['lib','runtime/lib']) {
      await fs.cp(path.join(runtimeInstall, dir, tuple), path.join(sdk, dir, tuple), {recursive:true});
    }
    await fs.copyFile(archive, path.join(sdk, astFile));
    const resource = (await $({stdio:'pipe'})`${path.join(toolchain,'bin/clang')} -print-resource-dir`).stdout.trim();
    for (const lib of [path.join(resource,'lib/aarch64-linux-ohos'), path.join(toolchain,'lib/aarch64-linux-ohos')])
      extraLibs.push('--target-lib=' + lib);
  }
  await fs.rm(finalStd, {recursive: true, force: true});
  await $({cwd: stdlib, env: stageEnv})`python3 build.py clean`;
  if (split) {
    await fs.mkdir(path.join(sdk, 'modules'), {recursive:true});
    await fs.symlink(path.join(stdlib, 'build/build-libs-aarch64-linux-ohos/modules', tuple), path.join(sdk, 'modules', tuple), 'dir');
  }
  await $({cwd: stdlib, env: stageEnv})`python3 build.py build -t release -j ${crossBuildJobs(stageEnv, 'std')} --target ${`ohos-${arch}`} --target-lib=${path.join(runtime, 'output')} --target-lib=${path.join(runtimeInstall, 'runtime', 'lib', tuple)} --target-lib=${path.join(runtimeInstall, 'lib', tuple)} ${extraLibs} --target-toolchain ${path.join(toolchain, 'bin')} --target-sysroot ${path.join(native, 'sysroot')}`;
  await $({cwd: stdlib, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
  await assertCompiler();
  if (split) await fs.copyFile(path.join(sdk, astFile), path.join(finalStd, astFile));
  await writeStdProvenance({sourceDir: stdlib, ...(split && {sourceRoot:repository, sourceRevision:runtimeRef}), installPrefix: finalStd,
    compiler: originalCompiler.product, note: `OHOS ${arch} final std; runtime ${runtimeRef}`});
  // Keep runtime separate from std so package consumers cannot confuse their provenance.
  const runtimeArtifact = path.join(finalStd, 'cross-runtime');
  await fs.cp(runtimeInstall, runtimeArtifact, {recursive: true});

  if (split) {
    for (const rel of [`modules/${tuple}/std/std.ast.cjo`, `lib/${tuple}/libcangjie-std-ast.a`, `runtime/lib/${tuple}/libcangjie-std-ast.so`])
      await fs.access(path.join(finalStd, rel));
  }
  for (const relative of [`runtime/lib/${tuple}/libcangjie-std-core.so`, `lib/${tuple}/libcangjie-std-core.a`, `modules/${tuple}/std/std.core.cjo`]) {
    await fs.access(path.join(finalStd, relative));
  }
  await $`file ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'runtime', 'lib', tuple, 'libcangjie-std-core.so')}`;
  await $`sha256sum ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'lib', tuple, 'libcangjie-std-core.a')}`;
  console.log(`OHOS_FINAL_STD_BUILT tuple=${tuple} runtime_ref=${runtimeRef} artifact=${finalStd}`);
  if (split) await installOhosStage3({parent:parent3, software:path.dirname(finalStd), finalStd, stage2:originalCompiler.lineage});
} finally {
  if (split) await fs.rm(sdk, {recursive:true, force:true});
}
