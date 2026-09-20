import fs from 'node:fs/promises';
import path from 'node:path';
import {produceFinalCompiler, fileSha256, stdIdentity} from '../srcbuild/lib/final-compiler.mjs';
import {assertFinalStd} from '../srcbuild/lib/final-std.mjs';
import {getTarget} from '../../build/lib/targets.mjs';
import {resolveProductBinary} from '../srcbuild/lib/product-binary.mjs';
import {platformizeCjcToml} from './link_option.mjs';

// The caller's existing MSYS adapter owns shell/CRT setup. This continuation
// owns the W1 -> private target SDK -> clean/build -> named W2 handoff.
export async function buildWindowsFinalCompiler({root, cangjieHome, hostSdk, sdkRuntimeDirName,
  cjcTomlPath, cjcToml, mingwCxxLinkRsp, installedRuntimeLib, fixedLlvmManifest,
  finalCompilerOutput, finalStd, runInMsys, mingwBin = 'C:\\msys64\\mingw64\\bin'}) {
    await assertFinalStd(finalStd, getTarget('windows-x64'));
    const seed = await resolveProductBinary(path.join('target', 'release', 'bin'), 'Windows W1', {windows: true});
    const targetSdk = path.join(root, 'final-compiler-target-sdk');
    await fs.rm(targetSdk, {recursive: true, force: true});
    await fs.cp(cangjieHome, targetSdk, {recursive: true});
    const seedInstalled = path.join(targetSdk, 'bin', 'cjc.exe');
    await fs.copyFile(seed, seedInstalled);
    const parentSha256 = await fileSha256(seedInstalled);
    const stdSha256 = await stdIdentity(finalStd);
    // Match the packager's std-category replacement: never retain official std
    // files alongside the chosen cross final std, while preserving runtime/CRT.
    const modules = path.join(targetSdk, 'modules', sdkRuntimeDirName);
    for (const name of ['std', 'std.a', 'std.cjo', 'libstd.bc']) {
      await fs.rm(path.join(modules, name), {recursive: true, force: true});
    }
    for (const directory of [path.join(targetSdk, 'lib', sdkRuntimeDirName),
      path.join(targetSdk, 'runtime', 'lib', sdkRuntimeDirName), path.join(targetSdk, 'bin')]) {
      await fs.mkdir(directory, {recursive: true});
      for (const name of await fs.readdir(directory)) {
        if (name.startsWith('libcangjie-std')) await fs.rm(path.join(directory, name), {recursive: true, force: true});
      }
    }
    for (const entry of await fs.readdir(finalStd)) {
      await fs.cp(path.join(finalStd, entry), path.join(targetSdk, entry), {recursive: true, force: true});
    }
    await assertFinalStd(targetSdk, getTarget('windows-x64'));
    if (await stdIdentity(targetSdk, finalStd) !== stdSha256) throw new Error('Windows target SDK final std mismatch');
    // PE loader checks the executable directory first. Each executable keeps
    // its own runtime domain even when its child compiler uses the target SDK.
    for (const [sdkRoot, executableDir] of [[hostSdk, 'tools/bin'], [targetSdk, 'bin']]) {
      for (const sourceDir of [path.join(sdkRoot, 'runtime', 'lib', sdkRuntimeDirName),
        path.join(sdkRoot, 'third_party', 'llvm', 'lib'), mingwBin]) {
        for (const name of await fs.readdir(sourceDir)) {
          if (name.toLowerCase().endsWith('.dll')) {
            await fs.copyFile(path.join(sourceDir, name), path.join(sdkRoot, executableDir, name));
          }
        }
      }
    }
    await fs.writeFile(cjcTomlPath, platformizeCjcToml(
      cjcToml, 'win32', targetSdk, process.env.CJCJ_LLVM_LINK_RSP || '', mingwCxxLinkRsp));
    const clean = await runInMsys('cjpm clean', 'final-clean', targetSdk, hostSdk);
    if (clean.exitCode !== 0) return clean;
    const build = await runInMsys('cjc --version && cjpm build', 'final-build', targetSdk, hostSdk);
    if (build.exitCode === 0) {
      if (await fileSha256(seedInstalled) !== parentSha256 || await stdIdentity(finalStd) !== stdSha256
        || await stdIdentity(targetSdk, finalStd) !== stdSha256) {
        throw new Error('Windows W2 producer inputs changed during build');
      }
      const final = await resolveProductBinary(path.join('target', 'release', 'bin'), 'Windows W2', {windows: true});
      await produceFinalCompiler({binary: final, outdir: finalCompilerOutput, platform: 'windows-x64',
        repository: `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}.git`, commit: process.env.GITHUB_SHA,
        runId: process.env.GITHUB_RUN_ID, runAttempt: process.env.GITHUB_RUN_ATTEMPT, std: finalStd,
        lineage: {stage: 'windows-W2', parentSha256, stdSha256, compilerSha256: await fileSha256(final),
          tuple: sdkRuntimeDirName, runtimeSha256: await fileSha256(installedRuntimeLib),
          command: 'cjc --version && cjpm build',
          compilerEntry: seedInstalled, hostTools: path.join(hostSdk, 'tools', 'bin'),
          linkOptionsSha256: await fileSha256(cjcTomlPath),
          llvmManifestSha256: await fileSha256(fixedLlvmManifest)},
      });
    }
    return build;
}
