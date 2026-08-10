// Port of cangjie-build/src/cangjie_build/stages/package.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {copyInto, copytree, ensureDir, requireDir, requireFile} from './common.mjs';

const logger = getLogger('cangjie_build.stages.package');

function platformLibDirName(config) {
  return config.target.runtimeLibSubdir(config.buildType);
}

async function makeArchive(config, sourceDir, baseName) {
  const format = config.target.spec.archiveFormat;
  fs.mkdirSync(config.softwareDir, {recursive: true});
  const archive = path.join(config.softwareDir, `${baseName}.${format}`);
  fs.rmSync(archive, {force: true});
  logger.info('Creating %s archive %s', format, archive);
  if (format === 'tar.gz') {
    await runCommand([
      config.target.spec.tarCommand, '--format=gnu', '-czf', archive,
      '-C', path.dirname(sourceDir), path.basename(sourceDir),
    ], {
      stage: 'package.archive',
    });
  } else if (format === 'zip') {
    await runCommand(['zip', '-r', archive, path.basename(sourceDir)], {
      cwd: path.dirname(sourceDir), stage: 'package.archive',
    });
  } else {
    throw new BuildError('package.archive', `unsupported archive format: ${format}`);
  }
  return archive;
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
  const astSupport = path.join(destination, 'lib', platformLibDirName(config), 'libcangjie-ast-support.a');
  if (fs.statSync(astSupport, {throwIfNoEntry: false})?.isFile()) {
    fs.unlinkSync(astSupport);
    logger.info('Removed %s', astSupport);
  }

  const toolsBin = ensureDir(path.join(destination, 'tools', 'bin'));
  const toolsConfig = ensureDir(path.join(destination, 'tools', 'config'));
  const cjpm = requireFile(path.join(toolsRoot, 'cjpm', 'dist', `cjpm${suffix}`), {stage: 'package.cjpm'});
  copyInto(cjpm, toolsBin, {stage: 'package.cjpm'});

  const cjfmt = requireFile(path.join(toolsRoot, 'cjfmt', 'build', 'build', 'bin', `cjfmt${suffix}`), {
    stage: 'package.cjfmt',
  });
  copyInto(cjfmt, toolsBin, {stage: 'package.cjfmt'});
  for (const toml of globOrFail(path.join(toolsRoot, 'cjfmt', 'config'), '.toml', 'package.cjfmt.config')) {
    copyInto(toml, toolsConfig, {stage: 'package.cjfmt.config'});
  }

  const hleSource = requireFile(path.join(toolsRoot, 'hyperlangExtension', 'target', 'bin', `main${suffix}`), {
    stage: 'package.hle',
  });
  fs.cpSync(hleSource, path.join(toolsBin, `hle${suffix}`), {preserveTimestamps: true});

  const dtsparserSource = requireDir(path.join(toolsRoot, 'hyperlangExtension', 'src', 'dtsparser'), {
    stage: 'package.dtsparser',
  });
  const dtsparserDestination = path.join(destination, 'tools', 'dtsparser');
  copytree(dtsparserSource, dtsparserDestination, {stage: 'package.dtsparser'});
  for (const name of fs.readdirSync(dtsparserDestination)) {
    const candidate = path.join(dtsparserDestination, name);
    if (name.endsWith('.cj') && fs.statSync(candidate).isFile()) fs.unlinkSync(candidate);
  }

  const lsp = requireFile(path.join(toolsRoot, 'cangjie-language-server', 'output', 'bin', `LSPServer${suffix}`), {
    stage: 'package.lsp',
  });
  copyInto(lsp, toolsBin, {stage: 'package.lsp'});

  // Both are built native-only, so on the Windows cross build the SDK keeps the
  // base toolchain's copies rather than failing on a product we never produced.
  if (!config.target.spec.crossCompile) {
    const cjcov = requireFile(path.join(toolsRoot, 'cjcov', 'dist', `cjcov${suffix}`), {stage: 'package.cjcov'});
    copyInto(cjcov, toolsBin, {stage: 'package.cjcov'});

    // cjtrace-recover installs through CMake, which places programs under bin/.
    const cjtrace = requireFile(
      path.join(toolsRoot, 'cjtrace-recover', 'dist', 'bin', `cjtrace-recover${suffix}`),
      {stage: 'package.cjtrace-recover'},
    );
    copyInto(cjtrace, toolsBin, {stage: 'package.cjtrace-recover'});
  }
}

async function packageMainSdk(config) {
  const compilerOutput = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());
  requireDir(compilerOutput, {stage: 'package.compiler_output'});
  const cangjieDir = path.join(ensureDir(config.softwareDir), 'cangjie');
  fs.rmSync(cangjieDir, {recursive: true, force: true});
  fs.cpSync(compilerOutput, cangjieDir, {recursive: true, dereference: false, preserveTimestamps: true});
  organizeSdkTree(config, cangjieDir);
  return makeArchive(config, cangjieDir, `cangjie-sdk-${config.target.spec.sdkName}-${config.cangjieVersion}`);
}

async function packageStdx(config) {
  const stdxDir = path.join(config.repoPath('stdx'), 'target', config.target.stdxTargetSubdir());
  requireDir(stdxDir, {stage: 'package.stdx'});
  const staged = path.join(ensureDir(config.softwareDir), path.basename(stdxDir));
  fs.rmSync(staged, {recursive: true, force: true});
  fs.cpSync(stdxDir, staged, {recursive: true, dereference: false, preserveTimestamps: true});
  return makeArchive(
    config,
    staged,
    `cangjie-stdx-${config.target.spec.sdkName}-${config.cangjieVersion}.${config.stdxVersion}`,
  );
}

export async function run(config) {
  return stage('package', async () => {
    ensureDir(config.softwareDir);
    const sdk = await packageMainSdk(config);
    const stdx = await packageStdx(config);
    logger.info('SDK   -> %s', sdk);
    logger.info('STDX  -> %s', stdx);
    return [sdk, stdx];
  });
}
