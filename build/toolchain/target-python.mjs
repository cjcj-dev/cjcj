// Port of cangjie-build/src/cangjie_build/toolchain/target_python.py.

import fs from 'node:fs';
import path from 'node:path';
import {download} from '../lib/archive.mjs';
import {BuildError} from '../lib/errors.mjs';
import {getLogger, stage} from '../lib/logging.mjs';
import {run} from '../lib/runner.mjs';

const logger = getLogger('cangjie_build.toolchain.target_python');
const NUGET_VERSIONS = new Map([['3.11', '3.11.9'], ['3.12', '3.12.10']]);
const EXTRA_RUNTIME_DLLS = ['python3.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'];
export const INSTALL_DIR_NAME = 'target-python';

async function hostPyver() {
  const result = await run(['python3', '-c', 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")'], {
    stage: 'target-python.host-version', capture: true, logOutput: false,
  });
  const version = result.stdout.trim();
  if (!/^\d+\.\d+$/.test(version)) throw new BuildError('target-python', `invalid host Python version: ${version}`);
  return version;
}

async function fullVersion() {
  const hostVersion = await hostPyver();
  const version = NUGET_VERSIONS.get(hostVersion);
  if (!version) {
    throw new BuildError('target-python', `unsupported host Python ${hostVersion}; add a NuGet version pin in toolchain/target-python.mjs`);
  }
  return {hostVersion, version};
}

export async function installPath(buildRoot) {
  const {version} = await fullVersion();
  return path.join(buildRoot, INSTALL_DIR_NAME, version, 'bundle');
}

function runtimeDllName(hostVersion) {
  return `python${hostVersion.replace('.', '')}.dll`;
}

function runtimeDlls(bundle, hostVersion) {
  const output = [path.join(bundle, runtimeDllName(hostVersion))];
  for (const name of EXTRA_RUNTIME_DLLS) {
    const candidate = path.join(bundle, name);
    if (fs.statSync(candidate, {throwIfNoEntry: false})?.isFile()) output.push(candidate);
  }
  return output;
}

function copyEntry(source, target) {
  fs.cpSync(source, target, {recursive: true, preserveTimestamps: true});
}

export async function install(buildRoot) {
  const {hostVersion, version} = await fullVersion();
  const bundle = path.join(buildRoot, INSTALL_DIR_NAME, version, 'bundle');
  const marker = path.join(bundle, '.ready');
  if (fs.existsSync(marker)) {
    logger.info('Target Python already staged at %s; skipping', bundle);
    return bundle;
  }

  const cacheRoot = path.join(buildRoot, INSTALL_DIR_NAME, version);
  await stage('target-python', async () => {
    fs.mkdirSync(cacheRoot, {recursive: true});
    const nupkg = path.join(cacheRoot, `python.${version}.nupkg`);
    await download(`https://api.nuget.org/v3-flatcontainer/python/${version}/python.${version}.nupkg`, nupkg);

    const raw = path.join(cacheRoot, 'raw');
    fs.rmSync(raw, {recursive: true, force: true});
    fs.mkdirSync(raw);
    await run(['unzip', '-q', nupkg, 'tools/*', '-d', raw], {stage: 'target-python.extract'});
    const tools = path.join(raw, 'tools');
    if (!fs.statSync(tools, {throwIfNoEntry: false})?.isDirectory()) {
      throw new BuildError('target-python', `nupkg missing tools/: ${nupkg}`);
    }

    fs.rmSync(bundle, {recursive: true, force: true});
    fs.mkdirSync(bundle, {recursive: true});
    const dllName = runtimeDllName(hostVersion);
    const sourceDll = path.join(tools, dllName);
    if (!fs.statSync(sourceDll, {throwIfNoEntry: false})?.isFile()) {
      throw new BuildError('target-python', `missing ${dllName} in nupkg tools/`);
    }
    copyEntry(sourceDll, path.join(bundle, dllName));
    for (const name of EXTRA_RUNTIME_DLLS) {
      const source = path.join(tools, name);
      if (fs.statSync(source, {throwIfNoEntry: false})?.isFile()) copyEntry(source, path.join(bundle, name));
    }

    const sourceInclude = path.join(tools, 'include');
    if (!fs.statSync(sourceInclude, {throwIfNoEntry: false})?.isDirectory()) {
      throw new BuildError('target-python', 'missing include/ in nupkg tools/');
    }
    const pythonInclude = path.join(bundle, 'include', `python${hostVersion}`);
    fs.mkdirSync(pythonInclude, {recursive: true});
    for (const entry of fs.readdirSync(sourceInclude)) {
      copyEntry(path.join(sourceInclude, entry), path.join(pythonInclude, entry));
    }
    fs.rmSync(raw, {recursive: true});
    fs.closeSync(fs.openSync(marker, 'w'));
    logger.info('Target Python %s staged at %s', version, bundle);
  });
  return bundle;
}

export async function installRuntimeDlls(bundle, destDir) {
  const hostVersion = await hostPyver();
  fs.mkdirSync(destDir, {recursive: true});
  for (const source of runtimeDlls(bundle, hostVersion)) {
    if (!fs.statSync(source, {throwIfNoEntry: false})?.isFile()) {
      throw new BuildError('target-python', `runtime DLL missing: ${source}`);
    }
    copyEntry(source, path.join(destDir, path.basename(source)));
    logger.info('Installed %s -> %s', path.basename(source), destDir);
  }
}
