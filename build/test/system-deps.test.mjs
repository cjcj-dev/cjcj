import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  BREW_PACKAGES,
  CMAKE_ARCHIVE,
  CMAKE_SHA256,
  CMAKE_VERSION,
  LLVM_PYTHON_FORMULA,
  LLVM_PYTHON_VERSION,
  assertCmakeVersion,
  installCmake3,
  installDarwin,
} from '../toolchain/system-deps.mjs';

function write(file, contents = '') {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents);
  return file;
}

function brewDependencyStdout(command) {
  if (!(command[0] === 'brew' && command[1] === 'deps' && command[2] === '--formula' && command[3] === '--1')) {
    return null;
  }
  return command[4] === 'llvm@16' ? 'python@3.12\nxz\nzstd\n' : '';
}

test('Darwin dependency pins keep LLVM 16 and OpenSSL 3 without top-level Python', () => {
  assert.equal(LLVM_PYTHON_FORMULA, 'python@3.11');
  assert.equal(LLVM_PYTHON_VERSION, '3.11');
  assert.equal(CMAKE_VERSION, '3.31.10');
  assert.ok(!BREW_PACKAGES.includes('python3'));
  assert.ok(BREW_PACKAGES.includes('llvm@16'));
  assert.ok(BREW_PACKAGES.includes('openssl@3'));
});

test('CMake gate accepts supported 3.x and rejects 4.x', () => {
  assert.doesNotThrow(() => assertCmakeVersion('cmake version 3.17.0\n'));
  assert.doesNotThrow(() => assertCmakeVersion(`cmake version ${CMAKE_VERSION}\n`));
  assert.throws(() => assertCmakeVersion('cmake version 4.4.0\n'), /cmake >=3\.17 and <4 is required/);
});

test('CMake installer verifies the official archive and exposes its exact binary', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-cmake-'));
  const githubPath = path.join(root, 'github-path');
  const previous = {
    path: process.env.PATH,
    githubActions: process.env.GITHUB_ACTIONS,
    githubPath: process.env.GITHUB_PATH,
  };
  try {
    process.env.GITHUB_ACTIONS = 'true';
    process.env.GITHUB_PATH = githubPath;
    const cmake = await installCmake3(root, {
      downloadArchive: async (url, archive) => {
        assert.match(url, /Kitware\/CMake\/releases\/download\/v3\.31\.10/);
        write(archive, 'archive fixture');
      },
      hashFile: async file => {
        assert.equal(file, path.join(root, CMAKE_ARCHIVE));
        return CMAKE_SHA256;
      },
      extractArchive: async () => {
        const executable = path.join(
          root, `cmake-${CMAKE_VERSION}-macos-universal`, 'CMake.app', 'Contents', 'bin', 'cmake',
        );
        write(executable, '#!/bin/sh\n');
        fs.chmodSync(executable, 0o755);
      },
    });
    const bin = path.dirname(cmake);
    assert.equal(process.env.PATH.split(path.delimiter)[0], bin);
    assert.equal(fs.readFileSync(githubPath, 'utf8'), `${bin}\n`);
  } finally {
    if (previous.path === undefined) delete process.env.PATH;
    else process.env.PATH = previous.path;
    if (previous.githubActions === undefined) delete process.env.GITHUB_ACTIONS;
    else process.env.GITHUB_ACTIONS = previous.githubActions;
    if (previous.githubPath === undefined) delete process.env.GITHUB_PATH;
    else process.env.GITHUB_PATH = previous.githubPath;
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('CMake installer fails closed on a mismatched archive digest', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-cmake-hash-'));
  try {
    await assert.rejects(installCmake3(root, {
      downloadArchive: async (_url, archive) => write(archive, 'bad archive'),
      hashFile: async () => '0'.repeat(64),
    }), /CMake archive SHA-256 mismatch/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('Darwin install exposes the supported LLVM Python keg without linking it', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-deps-'));
  const keg = path.join(root, 'python@3.11');
  const kegInclude = path.join(keg, 'include', 'python3.11');
  const commands = [];
  const exposedPaths = [];
  let batchExit = null;
  write(path.join(kegInclude, 'Python.h'));
  try {
    const runCommand = async (command, options = {}) => {
      commands.push(command);
      const dependencyStdout = brewDependencyStdout(command);
      if (dependencyStdout !== null) return {exitCode: 0, stdout: dependencyStdout};
      if (command[0] === 'brew' && command[1] === 'install' && command[2] === '--skip-link') {
        assert.equal(options.check, undefined);
        assert.equal(command.length, 4);
        return {exitCode: 0, stdout: ''};
      }
      if (command[0] === 'brew' && command[1] === '--prefix') return {exitCode: 0, stdout: `${keg}\n`};
      if (command[0] === path.join(keg, 'libexec', 'bin', 'python3')) {
        return {exitCode: 0, stdout: `3.11\n${kegInclude}\n`};
      }
      if (command[0] === 'brew' && command[1] === 'install') {
        const skippedDependency = commands.some(item =>
          item[0] === 'brew' && item[1] === 'install' && item[2] === '--skip-link' && item[3] === 'python@3.12');
        batchExit = skippedDependency ? 0 : 1;
        return {exitCode: batchExit, stdout: ''};
      }
      if (command[0] === 'python3') {
        assert.deepEqual(exposedPaths, [path.join(keg, 'libexec', 'bin')]);
        return {exitCode: 0, stdout: `3.11\n${kegInclude}\n`};
      }
      if (command[0].endsWith('/llvm-config')) return {exitCode: 0, stdout: '16.0.6\n'};
      if (command[0].endsWith('/openssl')) return {exitCode: 0, stdout: 'OpenSSL 3.6.3 21 Jan 2026\n'};
      if (command[0] === 'xcrun') return {exitCode: 0, stdout: '/SDK\n'};
      if (command[0] === '/fixture/cmake') return {exitCode: 0, stdout: `cmake version ${CMAKE_VERSION}\n`};
      throw new Error(`unexpected command: ${command.join(' ')}`);
    };
    await installDarwin({
      buildRoot: root,
      target: {spec: {llvmBinDir: '/fixture/llvm', opensslLibDir: '/fixture/openssl/lib'}},
    }, {
      runCommand,
      cmakeInstaller: async () => '/fixture/cmake',
      findExecutable: () => '/fixture/brew',
      exposePath: directory => exposedPaths.push(directory),
    });

    console.log(`TARGET_ASSERTION_RAN unlinked-python-dep batchExit=${batchExit}`);
    assert.equal(batchExit, 0, 'batch brew install must exit 0 only after --skip-link python@3.12');
    const brewInstalls = commands.filter(command => command[0] === 'brew' && command[1] === 'install');
    assert.deepEqual(brewInstalls, [
      ['brew', 'install', '--skip-link', LLVM_PYTHON_FORMULA],
      ['brew', 'install', '--skip-link', 'python@3.12'],
      ['brew', 'install', ...BREW_PACKAGES],
    ]);
    assert.deepEqual(
      commands.filter(command => command[0] === 'brew' && command[1] === 'deps'),
      BREW_PACKAGES.map(name => ['brew', 'deps', '--formula', '--1', name]),
    );
    const indexOf = predicate => commands.findIndex(predicate);
    const skipSelected = indexOf(command =>
      command[0] === 'brew' && command[1] === 'install' && command[2] === '--skip-link' && command[3] === LLVM_PYTHON_FORMULA);
    const firstDep = indexOf(command => command[0] === 'brew' && command[1] === 'deps');
    const lastDep = commands.findLastIndex(command => command[0] === 'brew' && command[1] === 'deps');
    const skipDependency = indexOf(command =>
      command[0] === 'brew' && command[1] === 'install' && command[2] === '--skip-link' && command[3] === 'python@3.12');
    const batch = indexOf(command => command[0] === 'brew' && command[1] === 'install' && command[2] !== '--skip-link');
    assert.ok(skipSelected !== -1 && firstDep > skipSelected && lastDep < skipDependency && skipDependency < batch);
    assert.deepEqual(exposedPaths, [path.join(keg, 'libexec', 'bin')]);
    assert.ok(!commands.flat().includes('--overwrite'));
    assert.ok(!commands.some(command =>
      command[0] === 'brew' && command[1] === 'install' && (command.includes('xz') || command.includes('zstd'))));
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('Darwin install rejects a newer host Python when the pinned shim is not selected', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-python-selection-'));
  const keg = path.join(root, 'python@3.11');
  const kegInclude = path.join(keg, 'include', 'python3.11');
  const hostInclude = path.join(root, 'host-python-include');
  write(path.join(kegInclude, 'Python.h'));
  write(path.join(hostInclude, 'Python.h'));
  try {
    const runCommand = async command => {
      const dependencyStdout = brewDependencyStdout(command);
      if (dependencyStdout !== null) return {exitCode: 0, stdout: dependencyStdout};
      if (command[0] === 'brew' && command[1] === 'install') return {exitCode: 0, stdout: ''};
      if (command[0] === 'brew' && command[1] === '--prefix') return {exitCode: 0, stdout: `${keg}\n`};
      if (command[0] === path.join(keg, 'libexec', 'bin', 'python3')) {
        return {exitCode: 0, stdout: `3.11\n${kegInclude}\n`};
      }
      if (command[0] === 'python3') return {exitCode: 0, stdout: `3.14\n${hostInclude}\n`};
      throw new Error(`unexpected command: ${command.join(' ')}`);
    };
    await assert.rejects(installDarwin({
      buildRoot: root,
      target: {spec: {llvmBinDir: '/fixture/llvm', opensslLibDir: '/fixture/openssl/lib'}},
    }, {
      runCommand,
      findExecutable: () => '/fixture/brew',
      exposePath: () => {},
    }), /Python 3\.11 is required, got: 3\.14/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('Darwin install rejects an unlinked LLVM Python keg without headers', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-python-headers-'));
  const keg = path.join(root, 'python@3.11');
  try {
    const runCommand = async command => {
      if (command[0] === 'brew' && command[1] === 'install') return {exitCode: 0, stdout: ''};
      if (command[0] === 'brew' && command[1] === '--prefix') return {exitCode: 0, stdout: `${keg}\n`};
      if (command[0] === path.join(keg, 'libexec', 'bin', 'python3')) {
        return {exitCode: 0, stdout: `3.11\n${path.join(keg, 'missing-include')}\n`};
      }
      throw new Error(`unexpected command: ${command.join(' ')}`);
    };
    await assert.rejects(installDarwin({
      buildRoot: root,
      target: {spec: {llvmBinDir: '/fixture/llvm', opensslLibDir: '/fixture/openssl/lib'}},
    }, {
      runCommand,
      findExecutable: () => '/fixture/brew',
      exposePath: () => {},
    }), /Python headers are required/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
