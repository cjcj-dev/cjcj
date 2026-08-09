#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {download} from '../../build/lib/archive.mjs';
import {run} from '../../build/lib/runner.mjs';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
  RELEASE_PYTHON_WINDOWS_SHA256,
  RELEASE_PYTHON_WINDOWS_URL,
} from '../../build/lib/python-bundle.mjs';

const platform = process.argv[2] || '';
const output = path.resolve(process.argv[3] || '');
if (!platform || !process.argv[3]) {
  throw new Error('usage: prepare_python_bundle.mjs <release-platform> <output-directory>');
}
const hosts = new Map([
  ['linux-x64', ['linux', 'x64']],
  ['linux-aarch64', ['linux', 'arm64']],
  ['darwin-x64', ['darwin', 'x64']],
  ['darwin-arm64', ['darwin', 'arm64']],
  ['windows-x64', ['win32', 'x64']],
]);
const expectedHost = hosts.get(platform);
if (!expectedHost) throw new Error(`unsupported release platform: ${platform}`);
if (process.platform !== expectedHost[0] || process.arch !== expectedHost[1]) {
  throw new Error(`${platform} Python must be prepared natively on ${expectedHost.join('/')}, got ${process.platform}/${process.arch}`);
}
if (output === path.parse(output).root) throw new Error('Python bundle output must not be a filesystem root');

const parent = path.dirname(output);
const work = path.join(parent, 'build-work');
const downloads = path.join(parent, 'downloads');
await fs.rm(output, {recursive: true, force: true});
await fs.rm(work, {recursive: true, force: true});
await fs.mkdir(output, {recursive: true});
await fs.mkdir(work, {recursive: true});
await fs.mkdir(downloads, {recursive: true});

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

async function verifiedDownload(url, expected, destination) {
  await download(url, destination);
  const actual = await sha256(destination);
  if (actual !== expected) {
    throw new Error(`Python source SHA-256 mismatch: expected ${expected}, got ${actual} (${url})`);
  }
  return actual;
}

async function removePythonCaches(directory) {
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory() && entry.name === '__pycache__') {
      await fs.rm(target, {recursive: true, force: true});
    } else if (entry.isDirectory()) {
      await removePythonCaches(target);
    }
  }
}

async function pruneUnixBundle() {
  const stdlib = path.join(output, 'lib', 'python3.11');
  const removed = [
    '<bundle>/include',
    '<bundle>/lib/pkgconfig',
    '<bundle>/share',
    '<bundle>/lib/python3.11/config-3.11-*',
    '<bundle>/lib/python3.11/test',
    '<bundle>/**/__pycache__',
  ];
  for (const relative of ['include', 'lib/pkgconfig', 'share', 'lib/python3.11/test']) {
    await fs.rm(path.join(output, relative), {recursive: true, force: true});
  }
  for (const entry of await fs.readdir(stdlib, {withFileTypes: true})) {
    if (entry.isDirectory() && entry.name.startsWith('config-3.11-')) {
      await fs.rm(path.join(stdlib, entry.name), {recursive: true, force: true});
    }
  }
  await removePythonCaches(output);
  return removed;
}

async function prepareWindows() {
  const archive = path.join(downloads, path.basename(RELEASE_PYTHON_WINDOWS_URL));
  await verifiedDownload(RELEASE_PYTHON_WINDOWS_URL, RELEASE_PYTHON_WINDOWS_SHA256, archive);
  await run(['tar', '-xf', archive, '-C', output], {stage: 'python.windows.extract'});
  const pth = path.join(output, 'python311._pth');
  if (!(await fs.stat(pth, {throwIfNoEntry: false}))?.isFile()) {
    throw new Error(`official embeddable package is missing ${pth}`);
  }
  await fs.writeFile(pth, [
    'python311.zip',
    '.',
    '../llvm/lib/python3.11/site-packages',
    'import site',
    '',
  ].join('\r\n'));
  await fs.writeFile(path.join(output, 'PYTHON-BUNDLE-CHANGES.txt'), [
    `Python ${RELEASE_PYTHON_VERSION} official embeddable distribution.`,
    'Changed python311._pth to add the packaged LLDB Python module directory and enable site initialization.',
    '',
  ].join('\r\n'));
  return {
    source_type: 'python.org-embeddable',
    source_url: RELEASE_PYTHON_WINDOWS_URL,
    source_sha256: RELEASE_PYTHON_WINDOWS_SHA256,
    configure_args: 'unavailable: official Windows embeddable distribution is not source-configured',
    configure_environment: 'unavailable: official Windows embeddable distribution is not source-configured',
  };
}

async function prepareUnix() {
  const archive = path.join(downloads, path.basename(RELEASE_PYTHON_SOURCE_URL));
  await verifiedDownload(RELEASE_PYTHON_SOURCE_URL, RELEASE_PYTHON_SOURCE_SHA256, archive);
  const sources = path.join(work, 'source');
  await fs.mkdir(sources);
  await run(['tar', '-xzf', archive, '-C', sources], {stage: 'python.source.extract'});
  const sourceRoot = path.join(sources, `Python-${RELEASE_PYTHON_VERSION}`);
  if (!(await fs.stat(path.join(sourceRoot, 'configure'), {throwIfNoEntry: false}))?.isFile()) {
    throw new Error(`Python source configure script is missing under ${sourceRoot}`);
  }

  const configureArgs = [`--prefix=${output}`, '--enable-shared', '--without-ensurepip'];
  const configureEnv = {};
  const recordedArgs = ['--prefix=<bundle>', '--enable-shared', '--without-ensurepip'];
  if (platform.startsWith('darwin-')) {
    configureArgs.push('--with-readline=editline');
    recordedArgs.push('--with-readline=editline');
  }

  await run([path.join(sourceRoot, 'configure'), ...configureArgs], {
    cwd: sourceRoot, envOverlay: configureEnv, stage: 'python.source.configure',
  });
  await run(['make', '-j', String(Math.max(1, Math.min(4, os.availableParallelism())))], {
    cwd: sourceRoot, stage: 'python.source.build',
  });
  await run(['make', 'install'], {cwd: sourceRoot, stage: 'python.source.install'});
  await fs.copyFile(path.join(sourceRoot, 'LICENSE'), path.join(output, 'LICENSE.txt'));
  const removed_runtime_extraneous_paths = await pruneUnixBundle();
  return {
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: recordedArgs.join(' '),
    configure_environment: Object.entries(configureEnv).map(([name, value]) => `${name}=${value}`).join(' ') || 'none',
    removed_runtime_extraneous_paths,
  };
}

const provenance = platform === 'windows-x64' ? await prepareWindows() : await prepareUnix();
const executable = platform === 'windows-x64'
  ? path.join(output, 'python.exe')
  : path.join(output, 'bin', 'python3.11');
const runtimeLibrary = platform === 'windows-x64'
  ? path.join(output, 'python311.dll')
  : path.join(output, 'lib', platform.startsWith('darwin-') ? 'libpython3.11.dylib' : 'libpython3.11.so.1.0');
const license = path.join(output, 'LICENSE.txt');
for (const file of [executable, runtimeLibrary, license]) {
  if (!(await fs.stat(file, {throwIfNoEntry: false}))?.isFile()) throw new Error(`Python bundle output is missing ${file}`);
}

const versionEnv = {...process.env, PYTHONHOME: output, PYTHONPATH: ''};
if (platform === 'windows-x64') versionEnv.PATH = `${output};${process.env.PATH || ''}`;
else if (platform.startsWith('darwin-')) versionEnv.DYLD_LIBRARY_PATH = `${path.join(output, 'lib')}:${process.env.DYLD_LIBRARY_PATH || ''}`;
else versionEnv.LD_LIBRARY_PATH = `${path.join(output, 'lib')}:${process.env.LD_LIBRARY_PATH || ''}`;
const version = await run([executable, '-s', '-c', 'import platform; print(platform.python_version())'], {
  envOverlay: versionEnv, stage: 'python.bundle.version', capture: true, logOutput: false,
});
if (version.stdout.trim() !== RELEASE_PYTHON_VERSION) {
  throw new Error(`Python bundle version mismatch: expected ${RELEASE_PYTHON_VERSION}, got ${version.stdout.trim() || '<empty>'}`);
}

const metadata = {
  schema: 1,
  platform,
  version: RELEASE_PYTHON_VERSION,
  ...provenance,
  required_modules: [...CJDB_PYTHON_MODULES],
  required_unix_modules: platform === 'windows-x64' ? [] : [...CJDB_PYTHON_UNIX_MODULES],
};
await fs.writeFile(path.join(output, 'PYTHON-BUNDLE.json'), `${JSON.stringify(metadata, null, 2)}\n`);
console.log(`PYTHON-BUNDLE-PREPARED platform=${platform} version=${RELEASE_PYTHON_VERSION} source_sha256=${provenance.source_sha256}`);
