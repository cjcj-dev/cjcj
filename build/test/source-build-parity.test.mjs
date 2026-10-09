import {pinnedRemote} from '../../ci/fixtures/git/pinned-remote.mjs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {assertGitObjectProof, assertRemoteObjectProof} from './git-object-proof.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {assertHostContract, hostContract} from '../lib/targets.mjs';
import {resolveSourceMirror, sourceFetchArguments, sourceLsRemoteArguments} from '../lib/git.mjs';
import {formatCommand, run as runCommand} from '../lib/runner.mjs';
import {
  assertHostRuntimeCommands,
  assertPlainHostRuntime,
  assertRuntimeCommonCache,
  assertRuntimeSplit,
  assertSdkCompilerRuntimeAbi,
  hostLoaderPath,
} from '../lib/runtime-split.mjs';
// The cjpm pin is read, never repeated: `git fetch --depth 1 <sha>` only works
// when that exact sha is reachable on the remote, so the pin and the assertion
// must be the same string by construction.
const cjpmPin = Object.fromEntries(
  fs.readFileSync(new URL('../../ci/cjpm_pin.env', import.meta.url), 'utf8')
    .split('\n')
    .filter(line => /^[A-Z_]+=/.test(line))
    .map(line => {
      const at = line.indexOf('=');
      return [line.slice(0, at), line.slice(at + 1).trim()];
    }),
);

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
  '--workspace', '--build-root', '--target', '--host-profile', '--build-type', '--cangjie-version',
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
  const officialSdkRoot = directory(root, 'official-sdk');
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
  file(officialSdkRoot, ['envsetup.sh']);
  file(workspace, ['verify', 'hello']);

  return {
    root,
    config: buildConfig({workspace, buildRoot, officialSdkRoot, cangjieVersion: '1.2.3'}),
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

test('every source target declares one host, SDK name, and cross-build policy', () => {
  const expected = {
    'linux-x64': ['linux', 'x64', 'linux-x64', false, true],
    'linux-aarch64': ['linux', 'arm64', 'linux-aarch64', false, false],
    'darwin-arm64': ['darwin', 'arm64', 'mac-aarch64', false, false],
    'darwin-x64': ['darwin', 'x64', 'mac-x64', false, false],
    'windows-x64': ['linux', 'x64', 'windows-x64', true, false],
  };
  for (const [target, contract] of Object.entries(expected)) {
    const actual = hostContract(target);
    assert.deepEqual(
      [actual.platform, actual.arch, actual.sdkName, actual.crossCompile, actual.kkk2Supported],
      contract,
    );
    assert.match(actual.requiredHost, new RegExp(`^${contract[0]}/${contract[1]}`));
  }
});

test('assert-host-contract helper prints HOST_CONTRACT or exits 2 with required host', () => {
  const helper = path.resolve(import.meta.dirname, '../../ci/srcbuild/steps/assert-host-contract.mjs');
  const ok = spawnSync(process.execPath, [helper, '--target', 'linux-x64', '--profile', 'kkk2'], {encoding: 'utf8'});
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /HOST_CONTRACT target=linux-x64 .*sdk=linux-x64 cross=no profile=kkk2/);
  const windows = spawnSync(process.execPath, [helper, '--target', 'windows-x64', '--profile', 'kkk2'], {encoding: 'utf8'});
  assert.equal(windows.status, 2, windows.stdout + windows.stderr);
  assert.match(windows.stderr, /required host/);
});

test('host assertion accepts the matching platform and rejects a wrong one before build stages', () => {
  assert.equal(assertHostContract('linux-x64', {
    platform: 'linux', arch: 'x64', profile: 'kkk2',
  }).target, 'linux-x64');
  assert.throws(
    () => assertHostContract('darwin-arm64', {platform: 'linux', arch: 'x64'}),
    /target darwin-arm64 required host darwin\/arm64.*current host linux\/x64/,
  );
  assert.throws(
    () => assertHostContract('windows-x64', {
      platform: 'linux', arch: 'x64', profile: 'kkk2',
    }),
    /target windows-x64 required host linux\/x64 with MinGW toolchain.*kkk2 supports only linux-x64/,
  );
  assert.throws(
    () => assertHostContract('plan9-mips', {platform: 'linux', arch: 'x64', profile: 'kkk2'}),
    /unknown target 'plan9-mips'/,
  );
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

test('packaged SDK colour ABI accepts a SAME fake SDK', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-colour-abi-same-'));
  try {
    const target = buildConfig({targetKey: 'linux-x64'}).target;
    const sdk = directory(root, 'sdk');
    const compiler = file(sdk, ['bin', 'cjc'], 'fake compiler');
    const runtime = file(sdk, [
      'runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary,
    ], 'fake runtime');
    const messages = [];
    const result = assertSdkCompilerRuntimeAbi({
      sdk,
      target,
      readCompiler: fileName => fileName === compiler ? '' : 'unexpected',
      readRuntime: fileName => fileName === runtime ? '' : 'unexpected',
      log: message => messages.push(message),
    });
    assert.equal(result.compilerCount, 0);
    assert.equal(result.runtimeCount, 0);
    assert.match(messages.join('\n'), /SDK_COLOUR_ABI_ASSERT_PASS compiler=0 .* runtime=0 /);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('packaged SDK colour ABI recognizes Darwin leading-underscore symbols', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-colour-abi-darwin-'));
  try {
    const target = buildConfig({targetKey: 'darwin-arm64'}).target;
    const sdk = directory(root, 'sdk');
    file(sdk, ['bin', 'cjc'], 'fake Mach-O compiler');
    file(sdk, [
      'runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary,
    ], 'fake Mach-O runtime');
    const symbols = '                 U _g_cjLoadBadMask\n';
    const result = assertSdkCompilerRuntimeAbi({
      sdk,
      target,
      readCompiler: () => symbols,
      readRuntime: () => '0000000000000000 T _g_cjLoadBadMask\n',
      log: () => {},
    });
    assert.equal(result.compilerCount, 1);
    assert.equal(result.runtimeCount, 1);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('packaged SDK colour ABI rejects a MISMATCH fake SDK', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-colour-abi-mismatch-'));
  try {
    const target = buildConfig({targetKey: 'linux-x64'}).target;
    const sdk = directory(root, 'sdk');
    file(sdk, ['bin', 'cjc'], 'fake compiler');
    file(sdk, [
      'runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary,
    ], 'fake runtime');
    assert.throws(
      () => assertSdkCompilerRuntimeAbi({
        sdk,
        target,
        readCompiler: () => '',
        readRuntime: () => `00000000 D g_cjLoadBadMask\n`,
      }),
      /g_cjLoadBadMask ABI mismatch: compiler=0 .* runtime=1 /,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('packaged SDK colour ABI rejects an nm failure', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-colour-abi-nm-failure-'));
  try {
    const target = buildConfig({targetKey: 'linux-x64'}).target;
    const sdk = directory(root, 'sdk');
    file(sdk, ['bin', 'cjc'], 'not an object file');
    file(sdk, [
      'runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary,
    ], 'fake runtime');
    assert.throws(
      () => assertSdkCompilerRuntimeAbi({sdk, target, readRuntime: () => ''}),
      /nm failed for packaged compiler .* rc=[^0]/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('packaged SDK colour ABI rejects a missing runtime', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-colour-abi-missing-'));
  try {
    const target = buildConfig({targetKey: 'linux-x64'}).target;
    const sdk = directory(root, 'sdk');
    file(sdk, ['bin', 'cjc'], 'fake compiler');
    assert.throws(
      () => assertSdkCompilerRuntimeAbi({sdk, target, readCompiler: () => ''}),
      /packaged runtime is missing:/,
    );
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('tools select the target compiler home while keeping the plain host loader', () => {
  const {root, config: platformConfig} = makeFixture();
  const config = Object.freeze({
    ...platformConfig,
    target: Object.freeze({
      ...platformConfig.target,
      spec: Object.freeze({
        ...platformConfig.target.spec,
        llvmBinDir: directory(root, 'platform-deps', 'llvm', 'bin'),
        opensslLibDir: directory(root, 'platform-deps', 'openssl', 'lib'),
      }),
    }),
  });
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

    let env;
    try {
      env = tools.targetToolsEnv(config);
    } catch (error) {
      if (error?.stage === 'environment') assert.fail(`UNKNOWN: ${error.message}`);
      throw error;
    }
    const pathEntries = env.PATH.split(path.delimiter);
    assert.deepEqual(pathEntries.slice(0, 2), [
      path.join(targetSdk, 'bin'),
      path.join(targetSdk, 'tools', 'bin'),
    ]);
    assert.ok(pathEntries.indexOf(path.join(hostSdk, 'bin')) > 1);
    assert.equal(env[config.target.spec.loaderEnv].split(path.delimiter)[0], path.dirname(hostRuntime));

    const missingDependencyConfig = Object.freeze({
      ...config,
      target: Object.freeze({
        ...config.target,
        spec: Object.freeze({...config.target.spec, llvmBinDir: path.join(root, 'missing-llvm', 'bin')}),
      }),
    });
    assert.throws(
      () => tools.targetToolsEnv(missingDependencyConfig),
      /required platform dependency directory missing:/,
    );
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
    const prefixMap = `-ffile-prefix-map=${path.resolve(workspace)}=.`;
    assert.match(env.CFLAGS, new RegExp(prefixMap.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    assert.match(env.CXXFLAGS, /ffile-prefix-map=\.\.=/);
    assert.match(env.CXXFLAGS, /fdebug-compilation-dir=\./);
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
    ['--target', 'darwin-arm64', 'print-version'],
    ['--target', 'windows-x64', '--host-profile', 'kkk2', 'print-version'],
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
      // Read the pin rather than repeating it. tools.mjs:48-51 takes the url and
      // ref straight from ci/cjpm_pin.env, so a literal here is a second copy of
      // the pin that no one updates with the first: when CJPM_FORK_REF moved to
      // pick up the cjpm-side jobserver, this assertion still named the old sha
      // and would have failed for a reason that has nothing to do with the
      // command order it exists to check.
      expected(root, toolsRoot, [
        'git', ...sourceFetchArguments(cjpmPin.CJPM_FORK_URL, cjpmPin.CJPM_FORK_REF),
      ]),
      expected(root, toolsRoot, ['git', 'rev-parse', 'FETCH_HEAD']),
      expected(root, toolsRoot, [
        'git', 'checkout', cjpmPin.CJPM_FORK_REF, '--', 'cjpm',
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
      expected(root, null, ['chmod', '-R', 'u+rwX,go+rX', path.join(workspace, 'software', 'cangjie')]),
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
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'check_sdk_usable.mjs')));
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'verifier_artifact_gate.mjs')));
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'bin', 'cjcov')));
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'bin', 'cjtrace-recover')));
    assert.ok(!fs.existsSync(path.join(config.softwareDir, 'cangjie', 'tools', 'dtsparser', 'drop.cj')));
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('package retains compiler and pcre relative links after input removal', async () => {
  const {root, config} = makeFixture();
  try {
    const input = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());
    const tuple = 'linux_x86_64_cjnative';
    file(input, ['bin', 'cjcj-stage1'], 'managed compiler');
    for (const name of ['cjc', 'cjc-frontend']) fs.symlinkSync('cjcj-stage1', path.join(input, 'bin', name));
    for (const sdk of [input, config.officialSdkRoot]) {
      file(sdk, ['runtime', 'lib', tuple, 'libpcre2-8.so.0.14.0'], 'producer pcre');
      fs.symlinkSync('libpcre2-8.so.0.14.0', path.join(sdk, 'runtime', 'lib', tuple, 'libpcre2-8.so.0'));
      fs.symlinkSync('libpcre2-8.so.0', path.join(sdk, 'runtime', 'lib', tuple, 'libpcre2-8.so'));
    }
    file(config.officialSdkRoot, ['bin', 'cjc'], 'official compiler');
    fs.symlinkSync('cjc', path.join(config.officialSdkRoot, 'bin', 'cjc-frontend'));
    let archives, packageError;
    try { archives = await packageStage.run(config); } catch (error) { packageError = error; }
    const staged = path.join(config.softwareDir, 'cangjie');
    console.log('PACKAGE_RELATIVE_COMPILER_ASSERT_REACHED');
    assert.equal(fs.readlinkSync(path.join(staged, 'bin', 'cjc')), 'cjcj-stage1', packageError?.message);
    assert.equal(fs.readlinkSync(path.join(staged, 'bin', 'cjc-frontend')), 'cjcj-stage1');
    console.log('PACKAGE_RELATIVE_PCRE_ASSERT_REACHED');
    assert.equal(fs.readlinkSync(path.join(staged, 'runtime', 'lib', tuple, 'libpcre2-8.so')), 'libpcre2-8.so.0');
    assert.ifError(packageError);
    const extracted = directory(root, 'extracted');
    await runCommand(['tar', '-xzf', archives[0], '-C', extracted]);
    fs.rmSync(input, {recursive: true, force: true});
    fs.rmSync(staged, {recursive: true, force: true});
    console.log('PACKAGE_INPUT_INDEPENDENCE_ASSERT_REACHED');
    const published = path.join(extracted, 'cangjie');
    for (const name of ['cjc', 'cjc-frontend']) assert.equal(fs.readFileSync(path.join(published, 'bin', name), 'utf8'), 'managed compiler');
    assert.equal(fs.readFileSync(path.join(published, 'runtime', 'lib', tuple, 'libpcre2-8.so'), 'utf8'), 'producer pcre');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

test('package retains pcre and stdx links independently of compiler aliases', async () => {
  const {root, config} = makeFixture();
  try {
    const input = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());
    const tuple = 'linux_x86_64_cjnative';
    for (const sdk of [input, config.officialSdkRoot]) {
      file(sdk, ['runtime', 'lib', tuple, 'libpcre2-8.so.0.14.0'], 'producer pcre');
      fs.symlinkSync('libpcre2-8.so.0.14.0', path.join(sdk, 'runtime', 'lib', tuple, 'libpcre2-8.so.0'));
      fs.symlinkSync('libpcre2-8.so.0', path.join(sdk, 'runtime', 'lib', tuple, 'libpcre2-8.so'));
    }
    const stdxInput = path.join(config.repoPath('stdx'), 'target', config.target.stdxTargetSubdir());
    file(stdxInput, ['target.bc'], 'producer stdx');
    fs.symlinkSync('target.bc', path.join(stdxInput, 'module.bc'));
    let archives, packageError;
    try { archives = await packageStage.run(config); } catch (error) { packageError = error; }
    const staged = path.join(config.softwareDir, 'cangjie');
    console.log('PACKAGE_INDEPENDENT_PCRE_ASSERT_REACHED');
    assert.equal(fs.readlinkSync(path.join(staged, 'runtime', 'lib', tuple, 'libpcre2-8.so')), 'libpcre2-8.so.0', packageError?.message);
    assert.equal(fs.readlinkSync(path.join(staged, 'runtime', 'lib', tuple, 'libpcre2-8.so.0')), 'libpcre2-8.so.0.14.0');
    assert.ifError(packageError);
    const stdxStaged = path.join(config.softwareDir, path.basename(stdxInput));
    console.log('PACKAGE_RELATIVE_STDX_ASSERT_REACHED');
    assert.equal(fs.readlinkSync(path.join(stdxStaged, 'module.bc')), 'target.bc');
    const extracted = directory(root, 'extracted');
    for (const archive of archives) await runCommand(['tar', '-xzf', archive, '-C', extracted]);
    for (const directory of [input, stdxInput, staged, stdxStaged]) fs.rmSync(directory, {recursive: true, force: true});
    assert.equal(fs.readFileSync(path.join(extracted, 'cangjie', 'runtime', 'lib', tuple, 'libpcre2-8.so'), 'utf8'), 'producer pcre');
    assert.equal(fs.readFileSync(path.join(extracted, path.basename(stdxInput), 'module.bc'), 'utf8'), 'producer stdx');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

test('package rejects the exact missing Windows payload path', async () => {
  const {root, config} = makeFixture();
  try {
    const relative = ['modules', 'windows_x86_64_cjnative', 'std', 'std.core.cjo'];
    file(config.officialSdkRoot, relative, 'official payload');
    const input = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());
    file(input, relative, 'produced Windows module');
    await packageStage.run(config);
    fs.rmSync(path.join(input, ...relative));
    console.log('PACKAGE_MISSING_WINDOWS_ASSERT_REACHED');
    await assert.rejects(packageStage.run(config), /missing-official-path\tmodules\/windows_x86_64_cjnative\/std\/std.core.cjo/);
    file(input, relative, 'produced Windows module');
    await packageStage.run(config);
    assert.ok(fs.existsSync(path.join(config.softwareDir, 'cangjie', ...relative)));
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

test('package rejects an extra link outside the published SDK', async () => {
  const {root, config} = makeFixture();
  try {
    const input = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());
    file(root, ['outside'], 'external dependency');
    fs.symlinkSync(path.join(root, 'outside'), path.join(input, 'external'));
    console.log('PACKAGE_EXTERNAL_LINK_ASSERT_REACHED');
    await assert.rejects(packageStage.run(config), /package-link-outside\texternal\t/);
    fs.rmSync(path.join(input, 'external'));
    await packageStage.run(config);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

// A pinned sha that is only reachable in someone's local clone builds fine for
// them and fails for everyone else. tools.mjs fetches it with `git fetch
// --depth 1 <url> <sha>`, which resolves nothing when the object is not
// advertised by the remote, so the pin must name an object the remote actually
// has. This is not hypothetical: CJPM_FORK_REF sat four commits behind the
// cjpm-side jobserver for three days because those commits lived only on a
// local branch, and nothing said so -- the build simply kept using the older
// pin, and the jobserver on the compiler side had no token source.
//
// A failed or interrupted probe is not a successful reachability check.
test('the cjpm pin names an object the remote actually has', {timeout: 60_000}, t => {
  const {CJPM_FORK_URL: url, CJPM_FORK_REF: ref} = cjpmPin;
  assert.match(ref, /^[0-9a-f]{40}$/, 'CJPM_FORK_REF must be a full sha');

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cjpm-pin-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const remote = pinnedRemote(root, 'tools', ref);
  assertRemoteObjectProof(remote, ref);

});

const context = {operation: 'fetch', url: 'controlled-local-remote', ref: 'controlled-pin'};
function rejects(result, pattern) {
  assert.throws(() => assertGitObjectProof(result, context), error => {
    assert.match(error.message, pattern);
    assert.match(error.message, /status=.*signal=.*error=.*stderr=/);
    assert.doesNotMatch(error.message, /is not reachable/);
    return true;
  });
}
test('Git proof timeout preserves ETIMEDOUT and does not claim missing object', () => {
  const result = spawnSync(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {timeout: 100, encoding: 'utf8'});
  assert.equal(result.error?.code, 'ETIMEDOUT');
  rejects(result, /Git timed out/);
});
test('Git proof startup failure preserves ENOENT', () => {
  const result = spawnSync('/nonexistent-cjcj-824-git', [], {encoding: 'utf8'});
  assert.equal(result.error?.code, 'ENOENT');
  rejects(result, /failed to start or complete/);
});
test('Git proof signal termination preserves SIGTERM', () => {
  const result = spawnSync(process.execPath, ['-e', 'process.kill(process.pid, "SIGTERM")'], {encoding: 'utf8'});
  assert.equal(result.signal, 'SIGTERM');
  rejects(result, /terminated by signal/);
});
test('Git proof missing exit status cannot pass', () => {
  rejects({status: null, signal: null, stderr: ''}, /no exit status/);
});
test('Git proof local remote accepts existing object and rejects missing object', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'git-proof-'));
  const git = args => spawnSync('git', args, {cwd: root, encoding: 'utf8', timeout: 5000});
  try {
    assert.equal(git(['init', '--bare', 'remote.git']).status, 0);
    assert.equal(git(['init', 'source']).status, 0);
    assert.equal(git(['-C', 'source', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']).status, 0);
    const ref = git(['-C', 'source', 'rev-parse', 'HEAD']).stdout.trim();
    assert.equal(git(['-C', 'source', 'push', '../remote.git', 'HEAD:refs/heads/main']).status, 0);
    assert.equal(git(['--git-dir=remote.git', 'symbolic-ref', 'HEAD', 'refs/heads/main']).status, 0);
    assert.equal(git(['init', 'consumer']).status, 0);
    const remote = path.join(root, 'remote.git');
    assertRemoteObjectProof(remote, ref, {cwd: path.join(root, 'consumer')});
    assert.throws(() => assertRemoteObjectProof(remote, '0123456789012345678901234567890123456789', {cwd: path.join(root, 'consumer')}), /is not reachable/);
    const probe = git(['ls-remote', 'remote.git']);
    assertGitObjectProof(probe, {...context, operation: 'ls-remote'});
    const fetch = sha => git(['-C', 'consumer', 'fetch', '--dry-run', '--depth', '1', '../remote.git', sha]);
    assertGitObjectProof(fetch(ref), {...context, ref});
    const missing = fetch('0123456789012345678901234567890123456789');
    assert.notEqual(missing.status, 0);
    assert.equal(missing.error, undefined);
    assert.equal(missing.signal, null);
    assert.throws(() => assertGitObjectProof(missing, context), /is not reachable/);
    assert.throws(() => assertGitObjectProof({...probe, status: 128}, {...context, operation: 'ls-remote'}), /remote preflight failed/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('Git proof actual entry rejects failed local preflight without claiming missing object', () => {
  assert.throws(() => assertRemoteObjectProof('/nonexistent-cjcj-824-remote', '0123456789012345678901234567890123456789'), error => {
    assert.match(error.message, /remote preflight failed/);
    assert.doesNotMatch(error.message, /is not reachable/);
    return true;
  });
});
