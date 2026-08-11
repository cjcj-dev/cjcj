import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {RELEASE_PYTHON_VERSION} from '../lib/python-bundle.mjs';
import * as compiler from '../srcbuild/stages/compiler.mjs';
import {mergedEnv} from '../srcbuild/stages/common.mjs';
import {
  LLVM_PYTHON_FORMULA,
  LLVM_PYTHON_VERSION,
  cjdbPythonHome,
  pythonSeries,
} from '../toolchain/system-deps.mjs';

function write(file, contents = '') {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents);
  return file;
}

// A keg fixture whose bin/python3 answers with the requested series, matching
// the two commands assertPython issues against it.
function kegFixture(root, {series, headers = true}) {
  const keg = path.join(root, `python@${series}`);
  const include = path.join(keg, 'include', `python${series}`);
  if (headers) write(path.join(include, 'Python.h'));
  const home = path.join(keg, 'libexec');
  const interpreter = path.join(home, 'bin', 'python3');
  const runCommand = async command => {
    if (command[0] === 'brew' && command[1] === '--prefix') {
      assert.equal(command[2], LLVM_PYTHON_FORMULA);
      return {exitCode: 0, stdout: `${keg}\n`};
    }
    if (command[0] === interpreter) return {exitCode: 0, stdout: `${series}\n${include}\n`};
    throw new Error(`unexpected command: ${command.join(' ')}`);
  };
  return {home, interpreter, runCommand};
}

async function captureCommands(action) {
  const previous = process.env.CANGJIE_BUILD_DRY_RUN;
  const originalWrite = process.stderr.write;
  let output = '';
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  try {
    return {result: await action(), output};
  } finally {
    process.stderr.write = originalWrite;
    if (previous === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previous;
  }
}

function compilerFixture(targetKey) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwinpy-compiler-'));
  const workspace = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler'), {recursive: true});
  return {
    root,
    config: buildConfig({
      workspace, buildRoot: path.join(root, 'buildtools'), cangjieVersion: '1.2.3', targetKey,
    }),
  };
}

test('the interpreter LLDB compiles against is the series the packages ship', () => {
  assert.equal(LLVM_PYTHON_VERSION, pythonSeries(RELEASE_PYTHON_VERSION));
  assert.equal(LLVM_PYTHON_VERSION, '3.11');
  assert.equal(LLVM_PYTHON_FORMULA, 'python@3.11');
  assert.throws(() => pythonSeries('3.11'), /unsupported Python version: 3\.11/);
  assert.throws(() => pythonSeries(''), /unsupported Python version: <empty>/);
});

test('cjdb Python home is the keg root that owns bin/python3', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwinpy-home-'));
  try {
    const keg = kegFixture(root, {series: '3.11'});
    assert.equal(await cjdbPythonHome({runCommand: keg.runCommand}), keg.home);
    // BuildCJDB.cmake appends bin/python3 to this value; the join must exist.
    assert.equal(path.join(keg.home, 'bin', 'python3'), keg.interpreter);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('cjdb Python home rejects the runner Python that broke the Darwin oracle', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwinpy-home-3140-'));
  try {
    const keg = kegFixture(root, {series: '3.14'});
    await assert.rejects(
      cjdbPythonHome({runCommand: keg.runCommand}),
      /Python 3\.11 is required, got: 3\.14/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('cjdb Python home rejects a keg without development headers', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwinpy-home-headers-'));
  try {
    const keg = kegFixture(root, {series: '3.11', headers: false});
    await assert.rejects(
      cjdbPythonHome({runCommand: keg.runCommand}),
      /Python headers are required/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('cjdb Python home fails closed when the interpreter version is unavailable or unreadable', async () => {
  const prefix = '/fixture/python@3.11';
  const interpreter = path.join(prefix, 'libexec', 'bin', 'python3');
  const unavailable = async command => {
    if (command[0] === 'brew') return {exitCode: 0, stdout: `${prefix}\n`};
    if (command[0] === interpreter) throw new Error('python version probe failed to start');
    throw new Error(`unexpected command: ${command.join(' ')}`);
  };
  await assert.rejects(
    cjdbPythonHome({runCommand: unavailable}),
    /python version probe failed to start/,
  );

  const unreadable = async command => {
    if (command[0] === 'brew') return {exitCode: 0, stdout: `${prefix}\n`};
    if (command[0] === interpreter) return {exitCode: 0, stdout: 'not-a-version\n/fixture/include\n'};
    throw new Error(`unexpected command: ${command.join(' ')}`);
  };
  await assert.rejects(
    cjdbPythonHome({runCommand: unreadable}),
    /Python >3\.7 is required, got: not-a-version/,
  );
});

test('only Darwin carries TARGET_PYTHON_PATH into build.py', async () => {
  const previous = process.env.CANGJIE_BUILD_DRY_RUN;
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  try {
    for (const targetKey of ['darwin-arm64', 'darwin-x64']) {
      const config = buildConfig({targetKey});
      const overlay = await compiler.nativeCjdbEnv(config, async () => '/keg/libexec');
      assert.deepEqual(overlay, {TARGET_PYTHON_PATH: '/keg/libexec'});
      assert.equal(mergedEnv(config, overlay).TARGET_PYTHON_PATH, '/keg/libexec');
    }
    for (const targetKey of ['linux-x64', 'linux-aarch64', 'windows-x64']) {
      const config = buildConfig({targetKey});
      const overlay = await compiler.nativeCjdbEnv(config, async () => {
        throw new Error('the non-Darwin branch must not resolve a Homebrew keg');
      });
      assert.deepEqual(overlay, {});
      assert.equal(mergedEnv(config, overlay).TARGET_PYTHON_PATH, undefined);
    }
  } finally {
    if (previous === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previous;
  }
});

test('the Darwin compiler stage resolves the pinned interpreter before building', async () => {
  const {root, config} = compilerFixture('darwin-arm64');
  try {
    const {output} = await captureCommands(() => compiler.run(config, {
      resolveCjdbPythonHome: async () => '/opt/homebrew/opt/python@3.11/libexec',
    }));
    const commands = output.split('\n').filter(line => line.includes('| $ '));
    assert.equal(commands.filter(line => line.includes('--build-cjdb')).length, 1);
    assert.equal(commands.filter(line => line.includes('build.py install')).length, 1);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('a 3.14 Python fails before the Darwin compiler stage starts', async () => {
  const {root, config} = compilerFixture('darwin-arm64');
  try {
    const keg = kegFixture(root, {series: '3.14'});
    const {output} = await captureCommands(async () => {
      await assert.rejects(compiler.run(config, {
        resolveCjdbPythonHome: () => cjdbPythonHome({runCommand: keg.runCommand}),
      }), /Python 3\.11 is required, got: 3\.14/);
    });
    const commands = output.split('\n').filter(line => line.includes('| $ '));
    assert.deepEqual(commands, []);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
