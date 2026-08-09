import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {formatCommand, run as runCommand} from '../lib/runner.mjs';
import * as compiler from '../srcbuild/stages/compiler.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import * as runtime from '../srcbuild/stages/runtime.mjs';
import * as stdlib from '../srcbuild/stages/stdlib.mjs';
import * as stdx from '../srcbuild/stages/stdx.mjs';
import * as tools from '../srcbuild/stages/tools.mjs';
import * as verify from '../srcbuild/stages/verify.mjs';

const CLI = path.resolve(import.meta.dirname, '..', 'cli.mjs');
const COMMANDS = [
  'install-system-deps', 'print-version', 'install-static-libs', 'install-mingw',
  'install-target-python', 'fetch', 'build', 'package', 'verify', 'run-all',
];
const GLOBAL_OPTIONS = [
  '--workspace', '--build-root', '--target', '--build-type', '--cangjie-version',
  '--stdx-version', '--log-level', '--version', '--help',
];

function runCli(args, {env = {}} = {}) {
  const cleanEnv = {...process.env, ...env};
  for (const name of ['CANGJIE_VERSION', 'CANGJIE_WORKSPACE', 'CANGJIE_BUILD_ROOT']) {
    if (!(name in env)) delete cleanEnv[name];
  }
  return spawnSync(process.execPath, [CLI, ...args], {encoding: 'utf8', env: cleanEnv});
}

function directory(root, ...parts) {
  const result = path.join(root, ...parts);
  fs.mkdirSync(result, {recursive: true});
  return result;
}

function file(root, parts, contents = '') {
  const result = path.join(root, ...parts);
  fs.mkdirSync(path.dirname(result), {recursive: true});
  fs.writeFileSync(result, contents);
  return result;
}

async function captureCommands(root, action) {
  const previousDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  const originalWrite = process.stderr.write;
  let output = '';
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  try {
    await action();
  } finally {
    process.stderr.write = originalWrite;
    if (previousDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previousDryRun;
  }
  return output.split('\n')
    .filter(line => line.includes('| $ '))
    .map(line => line.slice(line.indexOf('| $ ') + 4).replaceAll(root, '<ROOT>'));
}

function expected(root, cwd, argv) {
  const prefix = cwd ? `(cd ${cwd} && )` : '';
  return `${prefix}${formatCommand(argv)}`.replaceAll(root, '<ROOT>');
}

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'buildunify1-parity-'));
  const workspace = directory(root, 'workspace');
  const buildRoot = directory(root, 'buildtools');
  const compilerRoot = directory(workspace, 'cangjie_compiler');
  const runtimeRoot = directory(workspace, 'cangjie_runtime');
  const toolsRoot = directory(workspace, 'cangjie_tools');
  const stdxRoot = directory(workspace, 'cangjie_stdx');

  directory(compilerRoot, 'output');
  for (const subdirectory of ['lib', 'runtime']) {
    file(runtimeRoot, ['runtime', 'output', 'common', 'linux_relwithdebinfo_x86_64', subdirectory, '.keep']);
  }
  directory(runtimeRoot, 'runtime', 'output');
  directory(runtimeRoot, 'runtime', 'target');
  file(runtimeRoot, ['stdlib', 'output', '.keep']);
  directory(stdxRoot);
  directory(compilerRoot, 'include');
  file(toolsRoot, ['cjpm', 'build', 'build.py'], '# fixture\n');
  file(toolsRoot, ['cjpm', 'dist', 'cjpm']);
  for (const parts of [
    ['cjfmt', 'build'], ['hyperlangExtension', 'build'], ['cangjie-language-server', 'build'],
  ]) directory(toolsRoot, ...parts);
  file(toolsRoot, ['cjfmt', 'build', 'build', 'bin', 'cjfmt']);
  file(toolsRoot, ['cjfmt', 'config', 'default.toml']);
  file(toolsRoot, ['hyperlangExtension', 'target', 'bin', 'main']);
  file(toolsRoot, ['hyperlangExtension', 'src', 'dtsparser', 'keep.txt']);
  file(toolsRoot, ['hyperlangExtension', 'src', 'dtsparser', 'drop.cj']);
  file(toolsRoot, ['cangjie-language-server', 'output', 'bin', 'LSPServer']);
  file(stdxRoot, ['target', 'linux_x86_64_cjnative', '.keep']);
  file(compilerRoot, ['output', 'envsetup.sh']);
  file(workspace, ['verify', 'hello']);

  return {
    root,
    config: buildConfig({workspace, buildRoot, cangjieVersion: '1.2.3'}),
  };
}

test('target/build-type matrix matches config.py', () => {
  for (const targetKey of ['linux-x64', 'linux-aarch64', 'darwin-arm64', 'darwin-x64', 'windows-x64']) {
    for (const buildType of ['release', 'debug', 'relwithdebinfo']) {
      const config = buildConfig({targetKey, buildType});
      assert.equal(config.crossBuildType, targetKey === 'windows-x64' ? 'release' : buildType);
    }
  }
});

test('native target contracts match the source-build runner matrix', () => {
  const expected = {
    'linux-x64': ['linux', 'x86_64', 'linux_x86_64_cjnative', 'linux_x86_64', 47],
    'linux-aarch64': ['linux', 'aarch64', 'linux_aarch64_cjnative', 'linux_aarch64', 47],
    'darwin-arm64': ['darwin', 'aarch64', 'darwin_aarch64_cjnative', 'darwin_aarch64', 0],
    'darwin-x64': ['darwin', 'x86_64', 'darwin_x86_64_cjnative', 'darwin_x86_64', 0],
  };
  for (const [targetKey, [osName, arch, tuple, llvmPlatform, bitcode]] of Object.entries(expected)) {
    const {spec} = buildConfig({targetKey}).target;
    assert.deepEqual(
      [spec.os, spec.arch, spec.runtimeTuple, spec.llvmPlatform, spec.expectedStdArtifacts.bitcode],
      [osName, arch, tuple, llvmPlatform, bitcode],
    );
  }
});

test('CLI commands, options, defaults, and help match cli.py', () => {
  const help = runCli(['--help']);
  assert.equal(help.status, 0, help.stderr);
  for (const command of COMMANDS) {
    assert.match(help.stdout, new RegExp(`\\b${command}\\b`));
    const commandHelp = runCli([command, '--help']);
    assert.equal(commandHelp.status, 0, `${command}: ${commandHelp.stderr}`);
  }
  for (const option of GLOBAL_OPTIONS) assert.ok(help.stdout.includes(option), option);
  for (const stageName of ['compiler', 'runtime', 'stdlib', 'stdx', 'tools']) {
    const stageHelp = runCli(['build', stageName, '--help']);
    assert.equal(stageHelp.status, 0, `${stageName}: ${stageHelp.stderr}`);
  }

  const version = runCli(['--version']);
  assert.equal(version.status, 0, version.stderr);
  assert.equal(version.stdout, '0.1.0\n');

  const defaultVersion = runCli(['print-version']);
  assert.equal(defaultVersion.status, 0, defaultVersion.stderr);
  assert.equal(defaultVersion.stdout, '0.0.0-dev\n');

  const explicitVersion = runCli([
    '--target', 'windows-x64', '--build-type', 'debug', '--cangjie-version', 'v1.2.3',
    '--stdx-version', '7', '--log-level', 'ERROR', 'print-version',
  ]);
  assert.equal(explicitVersion.status, 0, explicitVersion.stderr);
  assert.equal(explicitVersion.stdout, '1.2.3\n');
});

test('CLI usage errors exit 2 like Typer and do not silently accept arguments', () => {
  const cases = [
    [], ['-h'], ['unknown-command'], ['--target', 'macos-arm64', 'print-version'],
    ['--build-type', 'lto', 'print-version'], ['--stdx-version', 'nope', 'print-version'],
    ['--stdx-version', '1.0', 'print-version'], ['--stdx-version', '1e2', 'print-version'],
    ['--log-level', 'debug', 'print-version'], ['build'], ['build', 'unknown-stage'],
    ['build', 'compiler', 'extra'], ['print-version', 'extra'],
    ['fetch', '--repo-url', 'compiler'], ['fetch', '--repo-url', 'mystery=x'],
    ['fetch', '--repo-url', 'compiler=a', '--repo-url', 'compiler=b'],
    ['fetch', '--unknown'], ['run-all', '--unknown'],
  ];
  for (const args of cases) {
    const result = runCli(args);
    assert.equal(result.status, 2, `${args.join(' ')}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
});

test('CLI build failures exit 1 like entrypoint()', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'buildunify1-cli-exit-'));
  try {
    const result = runCli(['--workspace', root, 'verify']);
    assert.equal(result.status, 1, result.stderr);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('Linux source stages emit the Python command order', async () => {
  const {root, config} = makeFixture();
  try {
    const workspace = config.workspace;
    const compilerRoot = path.join(workspace, 'cangjie_compiler');
    const runtimeRoot = path.join(workspace, 'cangjie_runtime', 'runtime');
    const stdlibRoot = path.join(workspace, 'cangjie_runtime', 'stdlib');
    const stdxRoot = path.join(workspace, 'cangjie_stdx');
    const toolsRoot = path.join(workspace, 'cangjie_tools');
    const commands = await captureCommands(root, async () => {
      await compiler.run(config);
      await runtime.run(config);
      await stdlib.run(config);
      await stdx.run(config);
      await tools.run(config);
      await packageStage.run(config);
      await verify.run(config);
    });

    const expectedCommands = [
      expected(root, compilerRoot, ['python3', 'build.py', 'clean']),
      expected(root, compilerRoot, ['python3', 'build.py', 'build', '-t', 'relwithdebinfo', '--no-tests', '--build-cjdb', '-v', '1.2.3']),
      expected(root, compilerRoot, ['python3', 'build.py', 'install']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'clean']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'build', '--target', 'native', '-t', 'relwithdebinfo', '-v', '1.2.3']),
      expected(root, runtimeRoot, ['python3', 'build.py', 'install']),
      expected(root, stdlibRoot, ['python3', 'build.py', 'clean']),
      expected(root, stdlibRoot, [
        'python3', 'build.py', 'build', '-t', 'relwithdebinfo', '--target', 'native',
        `--target-lib=${path.join(runtimeRoot, 'target')}`, '--target-lib=/usr/lib/x86_64-linux-gnu',
      ]),
      expected(root, stdlibRoot, ['python3', 'build.py', 'install']),
      expected(root, stdxRoot, ['python3', 'build.py', 'clean']),
      expected(root, stdxRoot, [
        'python3', 'build.py', 'build', '-t', 'relwithdebinfo',
        `--include=${path.join(compilerRoot, 'include')}`, '--target-lib=/usr/lib/x86_64-linux-gnu',
      ]),
      expected(root, stdxRoot, ['python3', 'build.py', 'install']),
      expected(root, toolsRoot, [
        'git', 'fetch', '--depth', '1', 'https://github.com/cjcj-dev/cangjie-tools.git',
        '1212a25c07be1a400be85e6ff2902788d3ecec0a',
      ]),
      expected(root, toolsRoot, ['git', 'rev-parse', 'FETCH_HEAD']),
      expected(root, toolsRoot, [
        'git', 'checkout', '1212a25c07be1a400be85e6ff2902788d3ecec0a', '--', 'cjpm',
      ]),
    ];
    for (const [name, subpath] of [
      ['cjpm', path.join('cjpm', 'build')],
      ['cjfmt', path.join('cjfmt', 'build')],
      ['hle', path.join('hyperlangExtension', 'build')],
      ['lsp', path.join('cangjie-language-server', 'build')],
    ]) {
      const cwd = path.join(toolsRoot, subpath);
      expectedCommands.push(expected(root, cwd, ['python3', 'build.py', 'clean']));
      const buildArgs = ['python3', 'build.py', 'build', '-t', 'release'];
      if (name === 'cjpm') buildArgs.push('--set-rpath', '$ORIGIN/../../runtime/lib/linux_x86_64_cjnative');
      expectedCommands.push(expected(root, cwd, buildArgs));
      expectedCommands.push(expected(root, cwd, ['python3', 'build.py', 'install']));
    }
    expectedCommands.push(
      expected(root, null, ['tar', '--format=gnu', '-czf', path.join(workspace, 'software', 'cangjie-sdk-linux-x64-1.2.3.tar.gz'), '-C', path.join(workspace, 'software'), 'cangjie']),
      expected(root, null, ['tar', '--format=gnu', '-czf', path.join(workspace, 'software', 'cangjie-stdx-linux-x64-1.2.3.1.tar.gz'), '-C', path.join(workspace, 'software'), 'linux_x86_64_cjnative']),
      expected(root, path.join(workspace, 'verify'), ['bash', '-c', `set -e; source '${path.join(workspace, 'software', 'cangjie', 'envsetup.sh')}'; cjc hello.cj -o hello && ./hello`]),
    );
    assert.deepEqual(commands, expectedCommands);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('package paths and archive roots match package.py', async () => {
  const {root, config} = makeFixture();
  try {
    const [sdk, stdxArchive] = await packageStage.run(config);
    assert.equal(sdk, path.join(config.softwareDir, 'cangjie-sdk-linux-x64-1.2.3.tar.gz'));
    assert.equal(stdxArchive, path.join(config.softwareDir, 'cangjie-stdx-linux-x64-1.2.3.1.tar.gz'));
    const sdkList = await runCommand(['tar', '-tf', sdk], {capture: true, logOutput: false});
    const stdxList = await runCommand(['tar', '-tf', stdxArchive], {capture: true, logOutput: false});
    assert.equal(sdkList.stdout.split('\n')[0], 'cangjie/');
    assert.equal(stdxList.stdout.split('\n')[0], 'linux_x86_64_cjnative/');
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'bin', 'cjpm')));
    assert.ok(!fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'dtsparser', 'drop.cj')));
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
