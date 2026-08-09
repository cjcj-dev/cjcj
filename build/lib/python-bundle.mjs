import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export const RELEASE_PYTHON_VERSION = '3.11.9';
export const RELEASE_PYTHON_SOURCE = 'https://github.com/python/cpython.git';
export const RELEASE_PYTHON_DIR = 'third_party/python';
export const RELEASE_PYTHON_SOURCE_URL = 'https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz';
export const RELEASE_PYTHON_SOURCE_SHA256 = 'e7de3240a8bc2b1e1ba5c81bf943f06861ff494b69fda990ce2722a504c6153d';
export const RELEASE_PYTHON_WINDOWS_URL =
  'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embeddable-amd64.zip';
export const RELEASE_PYTHON_WINDOWS_SHA256 =
  '33b448f95fecb7c6f802157dbd5e6b40a2ad9bfc8b95ca634a06ba4073ad1ac0';

// Startup imports from cjcj-llvm@bc65313a:
// ScriptInterpreterPython.cpp:424-451,3172-3192; python.swig:83-89;
// source/Interpreter/embedded_interpreter.py:1-36.
export const CJDB_PYTHON_MODULES = Object.freeze([
  'builtins', 'code', 'copy', 'keyword', 'lldb', 'lldb._lldb',
  'lldb.embedded_interpreter', 'lldb.formatters', 'lldb.formatters.cpp',
  'os', 'pydoc', 're', 'signal', 'six', 'six.moves', 'sys', 'traceback', 'uuid',
]);
export const CJDB_PYTHON_UNIX_MODULES = Object.freeze([
  'fcntl', 'readline', 'rlcompleter', 'struct', 'termios',
]);

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

function pythonEnvironment(root, platform, pythonPath = '', libraryPaths = []) {
  const env = {...process.env, PYTHONHOME: root, PYTHONPATH: pythonPath, PYTHONDONTWRITEBYTECODE: '1'};
  const libraryPath = [path.join(root, 'lib'), ...libraryPaths].join(path.delimiter);
  if (platform === 'windows-x64') {
    env.PATH = `${root};${libraryPaths.join(';')};${process.env.PATH || ''}`;
  } else if (platform.startsWith('darwin-')) {
    env.DYLD_LIBRARY_PATH = `${libraryPath}:${process.env.DYLD_LIBRARY_PATH || ''}`;
  } else {
    env.LD_LIBRARY_PATH = `${libraryPath}:${process.env.LD_LIBRARY_PATH || ''}`;
  }
  return env;
}

export function verifyPythonImports(executable, root, platform, pythonPath = '', libraryPaths = []) {
  const modules = [...CJDB_PYTHON_MODULES];
  if (platform !== 'windows-x64') modules.push(...CJDB_PYTHON_UNIX_MODULES);
  const imported = [];
  for (const name of modules) {
    const script = [
      'import importlib',
      `name = ${JSON.stringify(name)}`,
      'importlib.import_module(name)',
      'print("CJDB-PYTHON-IMPORT=" + name)',
    ].join('\n');
    const result = spawnSync(executable, ['-s', '-c', script], {
      encoding: 'utf8',
      env: pythonEnvironment(root, platform, pythonPath, libraryPaths),
    });
    if (result.status !== 0) {
      throw new Error(`cjdb Python import failed for ${name} (${executable}):\n${result.stdout}\n${result.stderr || result.error?.message || `exit ${result.status}`}`);
    }
    const markers = result.stdout.split(/\r?\n/).filter(line => line.startsWith('CJDB-PYTHON-IMPORT='))
      .map(line => line.slice('CJDB-PYTHON-IMPORT='.length));
    if (markers.length !== 1 || markers[0] !== name) {
      throw new Error(`cjdb Python import audit was incomplete for ${name}: got ${markers.join(',') || '<empty>'}`);
    }
    imported.push(name);
  }
  return imported;
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

async function readMetadata(root, platform) {
  const file = path.join(root, 'PYTHON-BUNDLE.json');
  if (!await isFile(file)) throw new Error(`Python bundle provenance is missing: ${file}`);
  let metadata;
  try { metadata = JSON.parse(await fs.readFile(file, 'utf8')); } catch (error) {
    throw new Error(`invalid Python bundle provenance ${file}: ${error.message}`);
  }
  const windows = platform === 'windows-x64';
  const expected = {
    source_type: windows ? 'python.org-embeddable' : 'python.org-source-native',
    source_url: windows ? RELEASE_PYTHON_WINDOWS_URL : RELEASE_PYTHON_SOURCE_URL,
    source_sha256: windows ? RELEASE_PYTHON_WINDOWS_SHA256 : RELEASE_PYTHON_SOURCE_SHA256,
  };
  for (const [name, value] of Object.entries({
    platform: metadata.platform,
    version: metadata.version,
    source_type: metadata.source_type,
    source_url: metadata.source_url,
    source_sha256: metadata.source_sha256,
    configure_args: metadata.configure_args,
    configure_environment: metadata.configure_environment,
  })) {
    if (typeof value !== 'string' || value.length === 0) throw new Error(`Python bundle metadata ${name} is empty`);
  }
  if (metadata.schema !== 1 || metadata.platform !== platform || metadata.version !== RELEASE_PYTHON_VERSION) {
    throw new Error(`Python bundle metadata identity mismatch: ${JSON.stringify(metadata)}`);
  }
  for (const [name, value] of Object.entries(expected)) {
    if (metadata[name] !== value) {
      throw new Error(`Python bundle metadata ${name} mismatch: expected ${value}, got ${metadata[name]}`);
    }
  }
  const required = JSON.stringify(CJDB_PYTHON_MODULES);
  const requiredUnix = JSON.stringify(windows ? [] : CJDB_PYTHON_UNIX_MODULES);
  if (JSON.stringify(metadata.required_modules) !== required ||
      JSON.stringify(metadata.required_unix_modules) !== requiredUnix) {
    throw new Error(`Python bundle required_modules do not match the cjdb source inventory: ${file}`);
  }
  if (!windows && (metadata.configure_args.startsWith('unavailable:') ||
      metadata.configure_environment.startsWith('unavailable:'))) {
    throw new Error(`source-built Python must record configure inputs: ${file}`);
  }
  return {file, metadata};
}

function nativeCommand(command, args) {
  const result = spawnSync(command, args, {encoding: 'utf8'});
  if (result.status !== 0) {
    throw new Error(`${command} failed (${result.status}): ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout;
}

async function relocateDarwinPython(stage, pythonRoot) {
  const pythonLibrary = path.join(pythonRoot, 'lib', 'libpython3.11.dylib');
  nativeCommand('install_name_tool', ['-id', '@rpath/libpython3.11.dylib', pythonLibrary]);
  const llvmLib = path.join(stage, 'third_party', 'llvm', 'lib');
  const candidates = [path.join(stage, 'third_party', 'llvm', 'bin', 'lldb')];
  for (const name of await fs.readdir(llvmLib)) {
    if (name.startsWith('liblldb') && name.endsWith('.dylib')) candidates.push(path.join(llvmLib, name));
  }
  let patched = 0;
  for (const candidate of candidates) {
    if (!await isFile(candidate)) continue;
    const dependencies = nativeCommand('otool', ['-L', candidate]).split(/\r?\n/).slice(1)
      .map(line => line.trim().split(/\s+\(/)[0]).filter(Boolean);
    for (const dependency of dependencies) {
      const base = path.basename(dependency);
      if (!dependency.includes('3.11') ||
          !(base === 'Python' || base === 'Python3' || /^libpython3\.11.*\.dylib$/.test(base))) continue;
      const relative = path.relative(path.dirname(candidate), pythonLibrary).split(path.sep).join('/');
      const replacement = `@loader_path/${relative}`;
      if (dependency !== replacement) nativeCommand('install_name_tool', ['-change', dependency, replacement, candidate]);
      patched += 1;
    }
  }
  if (patched === 0) throw new Error('Darwin cjdb/LLDB carries no Python 3.11 dependency to relocate');
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
      'set "PYTHONDONTWRITEBYTECODE=1"',
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
    'export PYTHONDONTWRITEBYTECODE=1',
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
  await readMetadata(sourceRoot, platform);
  exactVersion(bundleLayout(sourceRoot, platform).executable, sourceRoot, platform);

  const destination = path.join(stage, RELEASE_PYTHON_DIR);
  await fs.rm(destination, {recursive: true, force: true});
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.cp(sourceRoot, destination, {recursive: true, dereference: false, preserveTimestamps: true});
  const installed = await requireLayout(destination, platform);
  const provenance = await readMetadata(destination, platform);
  if (platform.startsWith('darwin-')) await relocateDarwinPython(stage, destination);
  exactVersion(installed.executable, destination, platform);
  verifyPythonImports(
    installed.executable,
    destination,
    platform,
    path.join(stage, 'third_party', 'llvm', 'lib', 'python3.11', 'site-packages'),
    [
      path.join(stage, 'third_party', 'llvm', 'lib'),
      path.join(stage, 'tools', 'lib'),
      path.join(stage, 'runtime', 'lib', runtimeDir),
    ],
  );
  const launcher = await writeLauncher(stage, platform, runtimeDir);
  return {
    artifact: installed.executable,
    launcher,
    license: installed.license,
    metadata: provenance.metadata,
    metadataArtifact: provenance.file,
    version: RELEASE_PYTHON_VERSION,
  };
}
