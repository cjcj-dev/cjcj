// Port of cangjie-build/src/cangjie_build/stages/package.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {assertNoVerifierReportArtifacts} from '../../../scripts/verifier_artifact_gate.mjs';
import {packageInstall} from '../../../ci/srcbuild/lib/package-install.mjs';
import {archiveInstall, privateRoot} from '../../../ci/bootstrap/sdk-flow.mjs';
import {consumerSdk, ensureDir, requireDir, requireFile} from './common.mjs';

const logger = getLogger('cangjie_build.stages.package');

function platformLibDirName(config) {
  return config.target.runtimeLibSubdir(config.buildType);
}

function archivePath(config, baseName) {
  return path.join(config.softwareDir, `${baseName}.${config.target.spec.archiveFormat}`);
}

function sdkArchive(config) {
  return archivePath(config, `cangjie-sdk-${config.target.spec.sdkName}-${config.cangjieVersion}`);
}

function stdxArchive(config) {
  return archivePath(config, `cangjie-stdx-${config.target.spec.sdkName}-${config.cangjieVersion}.${config.stdxVersion}`);
}

async function invalidatePackageOutputs(config) {
  // A failed current attempt must not expose an earlier package as its output.
  // Validate the parent before touching only these two owned publication sets.
  await privateRoot(config.softwareDir);
  for (const archive of [sdkArchive(config), stdxArchive(config)]) {
    for (const suffix of ['', '.sha256', '.unpacked']) {
      fs.rmSync(archive + suffix, {recursive: true, force: true});
    }
  }
}

function globOrFail(directory, suffix, stageName) {
  const matches = fs.readdirSync(directory)
    .filter(name => name.endsWith(suffix))
    .sort()
    .map(name => path.join(directory, name));
  if (!matches.length) throw new BuildError(stageName, `no files match ${directory}/*${suffix}`);
  return matches;
}

function organizeSdkTree(config, destination) {
  const suffix = config.target.spec.exeSuffix;
  const toolsRoot = config.repoPath('tools');
  // CMake's installed AST library is consumed by the compiler and by the
  // original AST installation facts. Preserve it in both copied and in-place
  // SDKs; organizing public tools must not prune native installation members.

  // Native target/install owns this tree. Packaging must preserve the public
  // launchers and retained products rather than overwrite them from build dirs.
  for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead']) {
    for(const relative of ['tools/bin/'+name+suffix,'tools/bin/'+name+suffix+'.entry',
      '.target-tools/tools/bin/'+name+suffix])requireFile(path.join(destination,relative),{stage:'package.'+name});
  }
  for(const relative of ['tools/config/cangjie-format.toml','tools/config/cangjie-repo.toml',
    'tools/dtsparser/analysis.js','tools/dtsparser/DEPENDENCIES.json','tools/bin/node'+suffix]) {
    requireFile(path.join(destination,relative),{stage:'package.tool-payload'});
  }


}

function installedStdx(config) {
  if (config.stdxProfile === 'sdk-tools') throw new BuildError('package.stdx', 'complete SDK packaging requires full stdx');
  return requireDir(path.join(consumerSdk(config, config.target.primaryCompilerOutput()), 'stdx',
    config.target.stdxTargetSubdir()), {stage: 'package.stdx'});
}

async function packageMainSdk(config) {
  const compilerOutput = consumerSdk(config, config.target.primaryCompilerOutput());
  requireDir(compilerOutput, {stage: 'package.compiler_output'});

  try {
    assertNoVerifierReportArtifacts([compilerOutput]);
  } catch (error) {
    throw new BuildError('package.verifier_artifact_gate', error.message);
  }
  installedStdx(config); // Still required before copying or archiving an SDK.
  const cangjieDir=compilerOutput;
  organizeSdkTree(config,cangjieDir);
  return (await packageInstall({sdk:cangjieDir,target:config.target,version:config.cangjieVersion,
    officialSdkRoot:config.officialSdkRoot,archive:sdkArchive(config)})).archive;
}

export async function packageStdx(config) {
  const stdxDir = installedStdx(config);
  return (await archiveInstall({install:stdxDir,
    archive:stdxArchive(config),
    format:config.target.spec.archiveFormat,records:[]})).archive;
}

export async function run(config) {
  return stage('package', async () => {
    await invalidatePackageOutputs(config);
    ensureDir(config.softwareDir);
    const sdk = await packageMainSdk(config);
    const stdx = await packageStdx(config);
    logger.info('SDK   -> %s', sdk);
    logger.info('STDX  -> %s', stdx);
    return [sdk, stdx];
  });
}
