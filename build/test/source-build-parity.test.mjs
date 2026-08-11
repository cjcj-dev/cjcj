import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {formatCommand, run as runCommand} from '../lib/runner.mjs';
import {
  assertHostRuntimeCommands,
  assertPlainHostRuntime,
  assertRuntimeCommonCache,
  assertRuntimeSplit,
  hostLoaderPath,
} from '../lib/runtime-split.mjs';
import * as compiler from '../srcbuild/stages/compiler.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import * as runtime from '../srcbuild/stages/runtime.mjs';
import {baseEnv, copyContents} from '../srcbuild/stages/common.mjs';
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
  directory(toolsRoot, 'cjcov', 'build');
  file(toolsRoot, ['cjcov', 'dist', 'cjcov']);
  directory(toolsRoot, 'cjtrace-recover', 'build');
  file(toolsRoot, ['cjtrace-recover', 'dist', 'bin', 'cjtrace-recover']);
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

test('source builds fail closed unless host runtime is plain and target runtime is coloured', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-runtime-split-'));
  try {
    const target = buildConfig({targetKey: 'linux-x64'}).target;
    const hostSdk = directory(root, 'host-sdk');
    const targetSdk = directory(root, 'target-sdk');
    const relative = ['runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary];
    const hostRuntime = file(hostSdk, relative, 'host-runtime');
    const targetRuntime = file(targetSdk, relative, 'target-runtime');
    const symbols = runtime => runtime === hostRuntime ? '' : `00000000 D g_cjLoadBadMask\n`;
    const messages = [];

    const result = assertRuntimeSplit({
      hostSdk,
      targetSdk,
      target,
      readSymbols: symbols,
      log: message => messages.push(message),
    });
    assert.equal(result.hostCount, 0);
    assert.equal(result.targetCount, 1);
    assert.notEqual(result.hostRuntime, result.targetRuntime);
    assert.match(messages.join('\n'), /RUNTIME_SPLIT_ASSERT_PASS host=0 .* target=1 /);

    const hostMessages = [];
    const hostOnly = assertPlainHostRuntime({
      hostSdk,
      target,
      readSymbols: symbols,
      log: message => hostMessages.push(message),
    });
    assert.equal(hostOnly.hostRuntime, hostRuntime);
    assert.equal(hostOnly.hostCount, 0);
    assert.match(hostMessages.join('\n'), /HOST_RUNTIME_ASSERT_PASS host=0 /);
    assert.throws(
      () => assertPlainHostRuntime({
        hostSdk,
        target,
        readSymbols: () => `00000000 D g_cjLoadBadMask\n`,
      }),
      /count contract failed: host=1 .* expected host=0/,
    );

    assert.throws(
      () => assertRuntimeSplit({
        hostSdk,
        targetSdk,
        target,
        readSymbols: () => `00000000 D g_cjLoadBadMask\n`,
      }),
      /count contract failed: host=1 .* target=1 .* expected host=0 target=1/,
    );

    const loader = hostLoaderPath({hostSdk, targetSdk, target, inherited: '/inherited'}).split(path.delimiter);
    assert.deepEqual(loader.slice(0, 3), [
      path.join(targetSdk, 'third_party', 'llvm', 'lib'),
      path.dirname(hostRuntime),
      path.join(targetSdk, 'tools', 'lib'),
    ]);
    assert.ok(!loader.includes(path.dirname(targetRuntime)));

    const earlyHostLoader = hostLoaderPath({
      hostSdk,
      targetSdk,
      target,
      inherited: '/inherited',
      includeTargetLlvm: false,
    }).split(path.delimiter);
    assert.deepEqual(earlyHostLoader, [
      path.dirname(hostRuntime),
      path.join(targetSdk, 'tools', 'lib'),
      '/inherited',
    ]);
    assert.ok(!earlyHostLoader.includes(path.join(targetSdk, 'third_party', 'llvm', 'lib')));

    const generatedBuild = file(root, ['stdx', 'build.ninja'], [
      `command = env LD_LIBRARY_PATH=${path.dirname(hostRuntime)}:${path.dirname(targetRuntime)} cjc package.cj`,
      '',
    ].join('\n'));
    assert.equal(assertHostRuntimeCommands({
      buildFile: generatedBuild,
      hostRuntime,
      targetRuntime,
      loaderEnv: 'LD_LIBRARY_PATH',
      log: () => {},
    }), 1);
    fs.writeFileSync(generatedBuild,
      `command = env LD_LIBRARY_PATH=${path.dirname(targetRuntime)}:${path.dirname(hostRuntime)} cjc package.cj\n`);
    assert.throws(
      () => assertHostRuntimeCommands({
        buildFile: generatedBuild,
        hostRuntime,
        targetRuntime,
        loaderEnv: 'LD_LIBRARY_PATH',
      }),
      /generated cjc command selects target runtime before host/,
    );

    const crossTarget = buildConfig({targetKey: 'windows-x64'}).target;
    const crossHostSdk = directory(root, 'cross-host-sdk');
    const crossTargetSdk = directory(root, 'cross-target-sdk');
    const crossHostRuntime = file(crossHostSdk, [
      'runtime', 'lib', crossTarget.spec.hostRuntimeTuple, crossTarget.spec.hostRuntimeLibrary,
    ], 'plain-linux-host-runtime');
    const crossTargetRuntime = file(crossTargetSdk, [
      'runtime', 'lib', crossTarget.spec.runtimeTuple, crossTarget.spec.runtimeLibrary,
    ], 'coloured-windows-target-runtime');
    const crossResult = assertRuntimeSplit({
      hostSdk: crossHostSdk,
      targetSdk: crossTargetSdk,
      target: crossTarget,
      readSymbols: runtime => runtime === crossHostRuntime ? '' : `00000000 D g_cjLoadBadMask\n`,
      log: () => {},
    });
    assert.equal(crossResult.hostRuntime, crossHostRuntime);
    assert.equal(crossResult.targetRuntime, crossTargetRuntime);

    const runtimeTarget = directory(root, 'workspace', 'cangjie_runtime', 'runtime', 'target');
    const cache = file(root, ['stdlib', 'build', 'build', 'CMakeCache.txt'], [
      `RUNTIME_COMMON_LIB_DIR:STRING=${path.join(runtimeTarget, 'common', 'linux_release_x86_64', 'lib', target.spec.runtimeTuple)}`,
      '',
    ].join('\n'));
    assertRuntimeCommonCache({cache, runtimeTarget, log: () => {}});
    fs.writeFileSync(cache, 'RUNTIME_COMMON_LIB_DIR:STRING=/wrong/host/runtime\n');
    assert.throws(
      () => assertRuntimeCommonCache({cache, runtimeTarget}),
      /RUNTIME_COMMON_LIB_DIR escaped target runtime/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('tools select the target compiler home while keeping the plain host loader', () => {
  const {root, config} = makeFixture();
  const previousHostSdk = process.env.CJCJ_SRCBUILD_HOST_SDK;
  try {
    const hostSdk = directory(root, 'host-sdk');
    const targetSdk = path.join(config.repoPath('compiler'), 'output');
    const runtimeRelative = [
      'runtime', 'lib', config.target.spec.runtimeTuple, config.target.spec.runtimeLibrary,
    ];
    const hostRuntime = file(hostSdk, runtimeRelative, 'plain-host-runtime');
    file(targetSdk, runtimeRelative, 'coloured-target-runtime');
    process.env.CJCJ_SRCBUILD_HOST_SDK = hostSdk;

    const env = tools.targetToolsEnv(config);
    const pathEntries = env.PATH.split(path.delimiter);
    assert.deepEqual(pathEntries.slice(0, 2), [
      path.join(targetSdk, 'bin'),
      path.join(targetSdk, 'tools', 'bin'),
    ]);
    assert.ok(pathEntries.indexOf(path.join(hostSdk, 'bin')) > 1);
    assert.equal(env[config.target.spec.loaderEnv].split(path.delimiter)[0], path.dirname(hostRuntime));
  } finally {
    if (previousHostSdk === undefined) delete process.env.CJCJ_SRCBUILD_HOST_SDK;
    else process.env.CJCJ_SRCBUILD_HOST_SDK = previousHostSdk;
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('runtime producer uses the host loader before the target runtime exists', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-runtime-producer-'));
  const previousDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  const previousHostSdk = process.env.CJCJ_SRCBUILD_HOST_SDK;
  const previousLoader = process.env.LD_LIBRARY_PATH;
  try {
    const workspace = directory(root, 'workspace');
    const buildRoot = directory(root, 'buildtools');
    const config = buildConfig({workspace, buildRoot, targetKey: 'linux-x64'});
    const cangjieHome = directory(workspace, 'cangjie_compiler', 'output');
    const runtimeDirectory = directory(
      cangjieHome, 'runtime', 'lib', config.target.runtimeLibSubdir(config.buildType),
    );
    file(runtimeDirectory, ['libboundscheck.so']);
    file(runtimeDirectory, ['libsecurec.so']);
    const hostSdk = directory(root, 'host-sdk');
    const hostRuntime = file(hostSdk, [
      'runtime', 'lib', config.target.spec.runtimeTuple, config.target.spec.runtimeLibrary,
    ]);

    process.env.CANGJIE_BUILD_DRY_RUN = '1';
    process.env.CJCJ_SRCBUILD_HOST_SDK = hostSdk;
    process.env.LD_LIBRARY_PATH = '/inherited';
    const env = baseEnv(config);
    const loader = env.LD_LIBRARY_PATH.split(path.delimiter);
    assert.equal(env.CANGJIE_HOME, cangjieHome);
    assert.equal(loader[0], path.dirname(hostRuntime));
    assert.ok(!fs.existsSync(path.join(runtimeDirectory, config.target.spec.runtimeLibrary)));
  } finally {
    if (previousDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previousDryRun;
    if (previousHostSdk === undefined) delete process.env.CJCJ_SRCBUILD_HOST_SDK;
    else process.env.CJCJ_SRCBUILD_HOST_SDK = previousHostSdk;
    if (previousLoader === undefined) delete process.env.LD_LIBRARY_PATH;
    else process.env.LD_LIBRARY_PATH = previousLoader;
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('SDK overlays preserve relative symlinks across clean rebuilds', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-overlay-links-'));
  try {
    const source = directory(root, 'source');
    const destination = directory(root, 'destination');
    fs.writeFileSync(path.join(source, 'libsample.so.1'), 'runtime');
    fs.symlinkSync('libsample.so.1', path.join(source, 'libsample.so'));
    copyContents(source, destination, {stage: 'test.overlay.first'});
    copyContents(source, destination, {stage: 'test.overlay.clean-rebuild'});
    assert.equal(fs.readlinkSync(path.join(destination, 'libsample.so')), 'libsample.so.1');
    assert.equal(
      fs.realpathSync(path.join(destination, 'libsample.so')),
      path.join(destination, 'libsample.so.1'),
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
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
    // cjcov and cjtrace-recover extend the upstream tool set on purpose: they
    // are Cangjie-written and must come from source rather than the base SDK.
    for (const [name, subpath] of [
      ['cjpm', path.join('cjpm', 'build')],
      ['cjfmt', path.join('cjfmt', 'build')],
      ['hle', path.join('hyperlangExtension', 'build')],
      ['lsp', path.join('cangjie-language-server', 'build')],
      ['cjcov', path.join('cjcov', 'build')],
      ['cjtrace-recover', path.join('cjtrace-recover', 'build')],
    ]) {
      const cwd = path.join(toolsRoot, subpath);
      expectedCommands.push(expected(root, cwd, ['python3', 'build.py', 'clean']));
      const buildArgs = ['python3', 'build.py', 'build', '-t', 'release'];
      if (name === 'cjpm') buildArgs.push('--set-rpath', '$ORIGIN/../../runtime/lib/linux_x86_64_cjnative');
      expectedCommands.push(expected(root, cwd, buildArgs));
      const installArgs = ['python3', 'build.py', 'install'];
      if (name === 'cjtrace-recover') {
        installArgs.push('--prefix', path.join(toolsRoot, 'cjtrace-recover', 'dist'));
      }
      expectedCommands.push(expected(root, cwd, installArgs));
    }
    expectedCommands.push(
      expected(root, null, ['tar', '--format=gnu', '-czf', path.join(workspace, 'software', 'cangjie-sdk-linux-x64-1.2.3.tar.gz'), '-C', path.join(workspace, 'software'), 'cangjie']),
      expected(root, null, ['tar', '--format=gnu', '-czf', path.join(workspace, 'software', 'cangjie-stdx-linux-x64-1.2.3.1.tar.gz'), '-C', path.join(workspace, 'software'), 'linux_x86_64_cjnative']),
      expected(root, path.join(workspace, 'verify'), [
        'bash', '-c',
        'set -e; source "$1"; export "$2=$3"; "$5" hello.cj -o hello; export "$2=$4"; ./hello',
        'srcbuild-verify', path.join(workspace, 'software', 'cangjie', 'envsetup.sh'),
        'LD_LIBRARY_PATH', '<HOST_LIBRARIES>', '<TARGET_LIBRARIES>', '<HOST_CJC>',
      ]),
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
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'bin', 'cjcov')));
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'bin', 'cjtrace-recover')));
    assert.ok(!fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'dtsparser', 'drop.cj')));
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
