import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export const RELEASE_PYTHON_VERSION = '3.11.9';
export const RELEASE_PYTHON_SOURCE = 'https://github.com/python/cpython.git';
export const RELEASE_PYTHON_DIR = 'third_party/python';

async function isFile(file) {
  try { return (await fs.stat(file)).isFile(); } catch { return false; }
}

async function isDirectory(directory) {
  try { return (await fs.stat(directory)).isDirectory(); } catch { return false; }
}

function bundleLayout(root, platform) {
  if (platform === 'windows-x64') {
    return {
      executable: path.join(root, 'python.exe'),
      runtime: path.join(root, 'python311.dll'),
      stdlib: path.join(root, 'python311.zip'),
    };
  }
  const library = platform.startsWith('darwin-') ? 'libpython3.11.dylib' : 'libpython3.11.so.1.0';
  return {
    executable: path.join(root, 'bin', 'python3.11'),
    runtime: path.join(root, 'lib', library),
    stdlib: path.join(root, 'lib', 'python3.11', 'os.py'),
  };
}

function pythonEnvironment(root, platform) {
  const env = {...process.env, PYTHONHOME: root, PYTHONPATH: ''};
  if (platform === 'windows-x64') {
    env.PATH = `${root};${process.env.PATH || ''}`;
  } else if (platform.startsWith('darwin-')) {
    env.DYLD_LIBRARY_PATH = `${path.join(root, 'lib')}:${process.env.DYLD_LIBRARY_PATH || ''}`;
  } else {
    env.LD_LIBRARY_PATH = `${path.join(root, 'lib')}:${process.env.LD_LIBRARY_PATH || ''}`;
  }
  return env;
}

function exactVersion(executable, root, platform) {
  const result = spawnSync(executable, ['-s', '-c',
    'import platform,sys; print(platform.python_version()); print(sys.prefix)'], {
    encoding: 'utf8',
    env: pythonEnvironment(root, platform),
  });
  if (result.status !== 0) {
    throw new Error(`bundled Python failed (${executable}): ${result.stderr || result.error?.message || `exit ${result.status}`}`);
  }
  const [version, prefix] = result.stdout.trim().split(/\r?\n/);
  if (version !== RELEASE_PYTHON_VERSION) {
    throw new Error(`bundled Python must be ${RELEASE_PYTHON_VERSION}, got ${version || '<empty>'}`);
  }
  if (path.resolve(prefix || '') !== path.resolve(root)) {
    throw new Error(`bundled Python escaped PYTHONHOME: expected ${root}, got ${prefix || '<empty>'}`);
  }
  return version;
}

async function requireLayout(root, platform) {
  const layout = bundleLayout(root, platform);
  for (const [name, file] of Object.entries(layout)) {
    if (!await isFile(file)) throw new Error(`Python bundle ${name} is missing: ${file}`);
  }
  const license = path.join(root, 'LICENSE.txt');
  if (!await isFile(license)) throw new Error(`Python bundle PSF license is missing: ${license}`);
  return {...layout, license};
}

async function writeLauncher(stage, platform, runtimeDir) {
  const toolsBin = path.join(stage, 'tools', 'bin');
  await fs.mkdir(toolsBin, {recursive: true});
  for (const name of ['cjdb', 'cjdb.exe', 'cjdb.cmd']) {
    await fs.rm(path.join(toolsBin, name), {force: true});
  }
  if (platform === 'windows-x64') {
    const launcher = path.join(toolsBin, 'cjdb.cmd');
    await fs.writeFile(launcher, [
      '@echo off',
      'setlocal',
      'for %%I in ("%~dp0\\..\\..") do set "CJCJ_SDK_ROOT=%%~fI"',
      'set "PYTHONHOME=%CJCJ_SDK_ROOT%\\third_party\\python"',
      'set "PYTHONPATH=%CJCJ_SDK_ROOT%\\third_party\\llvm\\lib\\python3.11\\site-packages"',
      `set "PATH=%PYTHONHOME%;%CJCJ_SDK_ROOT%\\third_party\\llvm\\bin;%CJCJ_SDK_ROOT%\\third_party\\llvm\\lib;%CJCJ_SDK_ROOT%\\tools\\lib;%CJCJ_SDK_ROOT%\\runtime\\lib\\${runtimeDir};%PATH%"`,
      '"%CJCJ_SDK_ROOT%\\third_party\\llvm\\bin\\lldb.exe" %*',
      'exit /b %ERRORLEVEL%',
      '',
    ].join('\r\n'));
    return launcher;
  }
  const launcher = path.join(toolsBin, 'cjdb');
  const dynamicVariable = platform.startsWith('darwin-') ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH';
  await fs.writeFile(launcher, [
    '#!/bin/sh',
    'set -eu',
    'script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)',
    'sdk_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)',
    'python_home="$sdk_root/third_party/python"',
    'export PYTHONHOME="$python_home"',
    'export PYTHONPATH="$sdk_root/third_party/llvm/lib/python3.11/site-packages"',
    `export ${dynamicVariable}="$python_home/lib:$sdk_root/third_party/llvm/lib:$sdk_root/tools/lib:$sdk_root/runtime/lib/${runtimeDir}\${${dynamicVariable}:+:\$${dynamicVariable}}"`,
    'exec "$sdk_root/third_party/llvm/bin/lldb" "$@"',
    '',
  ].join('\n'));
  await fs.chmod(launcher, 0o755);
  return launcher;
}

export async function installPythonBundle({source, stage, platform, runtimeDir}) {
  if (!source || !await isDirectory(source)) {
    throw new Error(`Python ${RELEASE_PYTHON_VERSION} bundle directory is missing: ${source || '<empty>'}`);
  }
  const sourceRoot = await fs.realpath(source);
  await requireLayout(sourceRoot, platform);
  exactVersion(bundleLayout(sourceRoot, platform).executable, sourceRoot, platform);

  const destination = path.join(stage, RELEASE_PYTHON_DIR);
  await fs.rm(destination, {recursive: true, force: true});
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.cp(sourceRoot, destination, {recursive: true, dereference: true, preserveTimestamps: true});
  const installed = await requireLayout(destination, platform);
  exactVersion(installed.executable, destination, platform);
  const launcher = await writeLauncher(stage, platform, runtimeDir);
  return {artifact: installed.executable, launcher, license: installed.license, version: RELEASE_PYTHON_VERSION};
}
