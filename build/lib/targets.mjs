// Platform contracts follow cangjie_build/docs/linux.md:127-175,228-259 and
// cangjie_build/docs/macos.md:82-116,157-196. Native targets deliberately keep
// architecture, runtime tuple, LLVM artifact, loader environment, and final-std
// shape together so later stages never infer a release tuple from the runner.

import {ConfigError} from './errors.mjs';

const linuxX64 = Object.freeze({
  sourceBuild: Object.freeze({runner: 'ubuntu-22.04', reasons: Object.freeze([])}),
  spec: Object.freeze({
    key: 'linux-x64', sdkName: 'linux-x64', archiveFormat: 'tar.gz',
    packageHost: Object.freeze(['linux', 'x64']), hostLlvmLibrary: 'libLLVM-15.so',
    nativeFilePattern: /ELF 64-bit.*(?:x86-64|x86_64)/i,
    requiredLlvmTools: Object.freeze(['llc', 'opt', 'ld.lld', 'llvm-objcopy']),
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
    kkk2Supported: true,
    needsStaticLibs: true, os: 'linux', arch: 'x86_64', nodePlatform: 'linux', nodeArch: 'x64',
    runtimeTuple: 'linux_x86_64_cjnative', llvmPlatform: 'linux_x86_64',
    llvmRunner: 'ubuntu-22.04', llvmGlibc: '2.35', llvmTargets: 'X86', llvmPortability: 'glibc2.35',
    llvmBinDir: '/usr/lib/llvm-15/bin', opensslLibDir: '/usr/lib/x86_64-linux-gnu',
    loaderEnv: 'LD_LIBRARY_PATH', sharedLibrarySuffix: '.so',
    runtimeLibrary: 'libcangjie-runtime.so', fileFormat: 'ELF', fileArch: 'x86-64',
    tarCommand: 'tar', rpathOrigin: '$ORIGIN', legacyNcursesPackages: true,
    expectedStdArtifacts: Object.freeze({cjos: 47, bitcode: 47, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47}),
  }),
  compilerOutputDirs: () => ['output'],
  runtimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_x86_64`,
  hostRuntimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_x86_64`,
  runtimeLibSubdir: () => 'linux_x86_64_cjnative',
  stdxTargetSubdir: () => 'linux_x86_64_cjnative',
  primaryCompilerOutput: () => 'output',
});

const linuxAArch64 = Object.freeze({
  sourceBuild: Object.freeze({runner: 'ubuntu-24.04-arm', reasons: Object.freeze([
    'ci/colour-runtime/linux_aarch64.env is missing; extend the coloured runtime producer to linux_aarch64: https://github.com/cjcj-dev/cjcj/issues/763',
  ])}),
  spec: Object.freeze({
    key: 'linux-aarch64', sdkName: 'linux-aarch64', archiveFormat: 'tar.gz',
    packageHost: Object.freeze(['linux', 'arm64']), hostLlvmLibrary: 'libLLVM-15.so',
    nativeFilePattern: /ELF 64-bit.*(?:ARM aarch64|aarch64)/i,
    requiredLlvmTools: Object.freeze(['llc', 'opt', 'ld.lld', 'llvm-objcopy']),
    exeSuffix: '', outputDirSuffix: 'aarch64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: true, os: 'linux', arch: 'aarch64', nodePlatform: 'linux', nodeArch: 'arm64',
    runtimeTuple: 'linux_aarch64_cjnative', llvmPlatform: 'linux_aarch64',
    llvmRunner: 'ubuntu-22.04-arm', llvmGlibc: '2.35', llvmTargets: 'AArch64', llvmPortability: 'glibc2.35',
    llvmBinDir: '/usr/lib/llvm-15/bin', opensslLibDir: '/usr/lib/aarch64-linux-gnu',
    loaderEnv: 'LD_LIBRARY_PATH', sharedLibrarySuffix: '.so',
    runtimeLibrary: 'libcangjie-runtime.so', fileFormat: 'ELF', fileArch: 'ARM aarch64',
    tarCommand: 'tar', rpathOrigin: '$ORIGIN', legacyNcursesPackages: false,
    expectedStdArtifacts: Object.freeze({cjos: 47, bitcode: 47, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47}),
  }),
  compilerOutputDirs: () => ['output'],
  runtimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_aarch64`,
  hostRuntimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_aarch64`,
  runtimeLibSubdir: () => 'linux_aarch64_cjnative',
  stdxTargetSubdir: () => 'linux_aarch64_cjnative',
  primaryCompilerOutput: () => 'output',
});

const darwinArm64 = Object.freeze({
  sourceBuild: Object.freeze({runner: 'macos-15', reasons: Object.freeze([
    'ci/bootstrap/bootstrap.sh rejects Darwin; implement Darwin bootstrap: https://github.com/cjcj-dev/cjcj/issues/473',
  ])}),
  spec: Object.freeze({
    key: 'darwin-arm64', sdkName: 'mac-aarch64', archiveFormat: 'tar.gz',
    packageHost: Object.freeze(['darwin', 'arm64']), hostLlvmLibrary: 'libLLVM.dylib',
    nativeFilePattern: /Mach-O 64-bit.*(?:arm64|aarch64)/i,
    requiredLlvmTools: Object.freeze(['llc', 'opt', 'ld64.lld']),
    exeSuffix: '', outputDirSuffix: 'aarch64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'darwin', arch: 'aarch64', nodePlatform: 'darwin', nodeArch: 'arm64',
    runtimeTuple: 'darwin_aarch64_cjnative', llvmPlatform: 'darwin_aarch64',
    llvmRunner: 'macos-15', llvmGlibc: null, llvmTargets: 'AArch64', llvmPortability: 'macos15',
    llvmBinDir: '/opt/homebrew/opt/llvm@16/bin', opensslLibDir: '/opt/homebrew/opt/openssl@3/lib',
    loaderEnv: 'DYLD_LIBRARY_PATH', sharedLibrarySuffix: '.dylib',
    runtimeLibrary: 'libcangjie-runtime.dylib', fileFormat: 'Mach-O', fileArch: 'arm64',
    tarCommand: 'gtar', rpathOrigin: '@loader_path', legacyNcursesPackages: false,
    expectedStdArtifacts: Object.freeze({cjos: 47, bitcode: 0, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47}),
  }),
  compilerOutputDirs: () => ['output'],
  runtimeOutputSubdir: buildType => `darwin_${buildType.toLowerCase()}_aarch64`,
  hostRuntimeOutputSubdir: buildType => `darwin_${buildType.toLowerCase()}_aarch64`,
  runtimeLibSubdir: () => 'darwin_aarch64_cjnative',
  stdxTargetSubdir: () => 'darwin_aarch64_cjnative',
  primaryCompilerOutput: () => 'output',
});

const darwinX64 = Object.freeze({
  sourceBuild: Object.freeze({runner: 'macos-15-intel', reasons: Object.freeze([
    'ci/bootstrap/bootstrap.sh rejects Darwin; implement Darwin bootstrap: https://github.com/cjcj-dev/cjcj/issues/473',
  ])}),
  spec: Object.freeze({
    key: 'darwin-x64', sdkName: 'mac-x64', archiveFormat: 'tar.gz',
    packageHost: Object.freeze(['darwin', 'x64']), hostLlvmLibrary: 'libLLVM.dylib',
    nativeFilePattern: /Mach-O 64-bit.*x86_64/i,
    requiredLlvmTools: Object.freeze(['llc', 'opt', 'ld64.lld']),
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'darwin', arch: 'x86_64', nodePlatform: 'darwin', nodeArch: 'x64',
    runtimeTuple: 'darwin_x86_64_cjnative', llvmPlatform: 'darwin_x86_64',
    llvmRunner: 'macos-15-intel', llvmGlibc: null, llvmTargets: 'X86', llvmPortability: 'macos15',
    llvmBinDir: '/usr/local/opt/llvm@16/bin', opensslLibDir: '/usr/local/opt/openssl@3/lib',
    loaderEnv: 'DYLD_LIBRARY_PATH', sharedLibrarySuffix: '.dylib',
    runtimeLibrary: 'libcangjie-runtime.dylib', fileFormat: 'Mach-O', fileArch: 'x86_64',
    tarCommand: 'gtar', rpathOrigin: '@loader_path', legacyNcursesPackages: false,
    expectedStdArtifacts: Object.freeze({cjos: 47, bitcode: 0, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47}),
  }),
  compilerOutputDirs: () => ['output'],
  runtimeOutputSubdir: buildType => `darwin_${buildType.toLowerCase()}_x86_64`,
  hostRuntimeOutputSubdir: buildType => `darwin_${buildType.toLowerCase()}_x86_64`,
  runtimeLibSubdir: () => 'darwin_x86_64_cjnative',
  stdxTargetSubdir: () => 'darwin_x86_64_cjnative',
  primaryCompilerOutput: () => 'output',
});

const windowsX64 = Object.freeze({
  spec: Object.freeze({
    key: 'windows-x64', sdkName: 'windows-x64', archiveFormat: 'zip',
    packageHost: Object.freeze(['win32', 'x64']),
    nativeFilePattern: /PE32\+ executable.*x86-64/i,
    requiredLlvmTools: Object.freeze(['llc', 'opt', 'ld.lld', 'llvm-ar']),
    exeSuffix: '.exe', outputDirSuffix: 'x86_64', crossCompile: true, needsMingw: true,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'windows', arch: 'x86_64', nodePlatform: 'linux', nodeArch: 'x64',
    runtimeTuple: 'windows_x86_64_cjnative', llvmPlatform: 'windows_x86_64',
    llvmRunner: 'windows-2022', llvmGlibc: null, llvmTargets: 'AArch64;ARM;X86', llvmPortability: 'windows2022',
    hostRuntimeTuple: 'linux_x86_64_cjnative', hostRuntimeLibrary: 'libcangjie-runtime.so',
    llvmBinDir: '/usr/lib/llvm-15/bin', opensslLibDir: '/usr/lib/x86_64-linux-gnu', loaderEnv: 'LD_LIBRARY_PATH',
    sharedLibrarySuffix: '.dll', runtimeLibrary: 'libcangjie-runtime.dll',
    fileFormat: 'PE32+', fileArch: 'x86-64', tarCommand: '', rpathOrigin: '',
    legacyNcursesPackages: true,
    expectedStdArtifacts: Object.freeze({cjos: 47, bitcode: 0, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47}),
  }),
  compilerOutputDirs: () => ['output', 'output-x86_64-w64-mingw32'],
  runtimeOutputSubdir: buildType => `windows_${buildType.toLowerCase()}_x86_64`,
  hostRuntimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_x86_64`,
  runtimeLibSubdir: () => 'windows_x86_64_cjnative',
  stdxTargetSubdir: () => 'windows_x86_64_cjnative',
  primaryCompilerOutput: () => 'output-x86_64-w64-mingw32',
});

const registry = new Map([
  [linuxX64.spec.key, linuxX64],
  [linuxAArch64.spec.key, linuxAArch64],
  [darwinArm64.spec.key, darwinArm64],
  [darwinX64.spec.key, darwinX64],
  [windowsX64.spec.key, windowsX64],
]);

export function getTarget(key) {
  const target = registry.get(key);
  if (!target) {
    // A release platform that is not a buildable target (linux-x64-android, ...)
    // must not fall through to "unknown": the operator asked for a real package
    // and gets told exactly which tuple or capability has no producer.
    const release = releaseRegistry.get(key);
    if (release) {
      const readiness = releasePlatformReadiness(key);
      throw new ConfigError(
        `release platform '${key}' is ${readiness.status}, not a buildable target: ${readiness.reasons.join('; ')}`,
      );
    }
    throw new ConfigError(`unknown target '${key}'; valid: ${allTargets().join(', ')}`);
  }
  return target;
}

export function allTargets() {
  return [...registry.keys()].sort();
}

export function llvmToolMatrix(requested = 'all', {platformSet = '', publishTuple = false} = {}) {
  const targets = [...registry.values()].map(target => target.spec);
  let selected;
  if (platformSet) {
    if (!['all', 'windows-only', 'darwin-windows'].includes(platformSet)) {
      throw new ConfigError(`unknown LLVM platform set '${platformSet}'`);
    }
    selected = targets.filter(spec => platformSet === 'all'
      || (platformSet === 'windows-only' ? spec.os === 'windows' : spec.os !== 'linux'));
  } else if (!requested || requested === 'all') {
    selected = targets.filter(spec => spec.os !== 'windows');
  } else {
    const wanted = requested.split(',').map(value => value.trim()).filter(Boolean);
    const unknown = wanted.filter(value => !targets.some(spec => spec.llvmPlatform === value));
    if (unknown.length) throw new ConfigError(`unknown LLVM platforms: ${unknown.join(', ')}`);
    selected = targets.filter(spec => wanted.includes(spec.llvmPlatform));
  }
  if (!selected.length) throw new ConfigError(`no LLVM platforms selected from '${requested}'`);
  if (publishTuple && !selected.some(spec => spec.key === 'linux-x64')) {
    selected.push(getTarget('linux-x64').spec);
  }
  return {include: selected.map(spec => ({
    runner: spec.llvmRunner,
    platform: spec.llvmPlatform,
    'llvm-targets': spec.llvmTargets,
    'portability-tag': spec.llvmPortability,
    glibc: spec.llvmGlibc,
  }))};
}

export function sourceBuildCells() {
  return [...registry.values()].filter(target => target.sourceBuild).map(({spec, sourceBuild}) => ({
    target: spec.key,
    runner: sourceBuild.runner,
    llvm_platform: spec.llvmPlatform,
    static_libs: spec.needsStaticLibs,
    status: sourceBuild.reasons.length ? 'blocked' : 'runnable',
    reasons: [...sourceBuild.reasons],
  }));
}

export function targetForHost(platform = process.platform, arch = process.arch) {
  return [...registry.values()].find(({spec}) => spec.packageHost[0] === platform && spec.packageHost[1] === arch);
}

const CI_BUILD_RUNNERS = Object.freeze([
  ['ubuntu-24.04', 'linux-x64', false],
  ['ubuntu-22.04', 'linux-x64', false],
  ['ubuntu-26.04', 'linux-x64', true],
  ['ubuntu-24.04-arm', 'linux-aarch64', false],
]);
const PLATFORM_RUNNERS = Object.freeze([
  ['macos-26', 'darwin-arm64'], ['macos-26-intel', 'darwin-x64'],
  ['macos-15', 'darwin-arm64'], ['macos-15-intel', 'darwin-x64'],
  ['ubuntu-24.04', 'linux-x64'], ['ubuntu-24.04-arm', 'linux-aarch64'],
  ['ubuntu-22.04', 'linux-x64'], ['ubuntu-22.04-arm', 'linux-aarch64'],
  ['windows-2025', 'windows-x64'], ['windows-2022', 'windows-x64'],
]);

export function ciBuildCells() {
  return CI_BUILD_RUNNERS.map(([runner, target, experimental]) => ({
    runner, llvm_platform: getTarget(target).spec.llvmPlatform, experimental,
  }));
}

export function ciProvisionCells() {
  return [{runner: 'macos-latest'}];
}

export function platformTestCells() {
  return PLATFORM_RUNNERS.map(([runner, target]) => ({
    runner, llvm_platform: getTarget(target).spec.llvmPlatform,
    sdk_runtime_dir: getTarget(target).spec.runtimeTuple,
  }));
}

export function hostContract(key) {
  const {spec} = getTarget(key);
  const cross = spec.crossCompile ? 'yes' : 'no';
  const toolchain = spec.needsMingw ? ' with MinGW toolchain' : '';
  return Object.freeze({
    target: spec.key,
    platform: spec.nodePlatform,
    arch: spec.nodeArch,
    sdkName: spec.sdkName,
    crossCompile: spec.crossCompile,
    kkk2Supported: spec.kkk2Supported,
    requiredHost: `${spec.nodePlatform}/${spec.nodeArch}${toolchain} (cross=${cross})`,
  });
}

export function assertHostContract(key, {
  platform = process.platform,
  arch = process.arch,
  profile = 'generic',
} = {}) {
  if (!['generic', 'kkk2'].includes(profile)) {
    throw new ConfigError(`unknown host profile '${profile}'; valid: generic, kkk2`);
  }
  const contract = hostContract(key);
  if (platform !== contract.platform || arch !== contract.arch) {
    throw new ConfigError(
      `target ${key} required host ${contract.requiredHost}; current host ${platform}/${arch}`,
    );
  }
  if (profile === 'kkk2' && !contract.kkk2Supported) {
    throw new ConfigError(
      `target ${key} required host ${contract.requiredHost}; host profile kkk2 supports only linux-x64`,
    );
  }
  return contract;
}

// ---------------------------------------------------------------------------
// Release platforms (cjcj#73, P24). The official nightly ships fourteen platform
// packages (cjv nightly.json for 1.3.0-alpha.20260904010027 lists 14/14; the
// per-package tuple inventory is reports/EVIDENCE-exp_sdk_parity/platform-trees-0831).
// Each release platform is one host SDK -- a buildable target above -- plus zero
// or more target-side tuples cross-built on that host. The table below is the
// only place that says which GitHub-hosted runner packages a platform, which
// tuples the package carries, and what the runner must provide. Workflows read
// it through ci/release/platform-matrix.mjs; nothing else may restate it.
//
// Readiness is derived, not declared: a platform is buildable only when every
// tuple it carries has a producer in the P01-P23 DAG. A tuple without a producer
// makes the platform `blocked` with the missing stage spelled out, so the matrix
// reports the gap as a red job instead of a package that quietly lacks a tuple.

// What the P01-P23 chain produces today. Host SDKs: every key in the target
// registry, each producing final-std-<target> for its own runtime tuple. Cross
// std: ci/srcbuild/steps/build-windows-final-std.mjs runs on the linux-x64
// source cell only (srcbuild-target.yml source-mingw/source-android), so the
// Windows and Android tuples are produced by the Linux source cell; Android
// runtime and final std use ci/srcbuild/steps/build-android-final-std.mjs.
const DAG_CROSS_STD_PRODUCERS = Object.freeze({
  windows_x86_64_cjnative: 'linux-x64',
  linux_android_aarch64_cjnative: 'linux-x64',
});

// tuple -> target key whose source cell uploads final-std-<target> for it.
function stdProducerFor(tuple) {
  for (const [key, target] of registry) {
    if (target.spec.runtimeTuple === tuple && !target.spec.crossCompile) return key;
  }
  return DAG_CROSS_STD_PRODUCERS[tuple];
}

// Runner-side capabilities a platform needs beyond what the DAG installs itself.
// `probe` is what ci/release/platform-matrix.mjs check runs on the runner.
export const RELEASE_REQUIREMENTS = Object.freeze({
  'android-ndk': Object.freeze({
    summary: 'Android NDK (r25+) with toolchains/llvm/prebuilt',
    envCandidates: Object.freeze(['ANDROID_NDK_ROOT', 'ANDROID_NDK_LATEST_HOME', 'ANDROID_NDK_HOME']),
    marker: 'toolchains/llvm/prebuilt',
  }),
  'ohos-sdk': Object.freeze({
    summary: 'OpenHarmony native SDK with native/llvm/bin',
    envCandidates: Object.freeze(['OHOS_SDK_HOME', 'OHOS_NDK_HOME', 'HOS_SDK_HOME']),
    marker: 'native/llvm/bin',
  }),
  'xcode-ios': Object.freeze({
    summary: 'Xcode with iphoneos and iphonesimulator SDKs',
    xcrunSdks: Object.freeze(['iphoneos', 'iphonesimulator']),
  }),
});

// Which DAG stage installs each requirement and probes it on its own runner.
// Same shape as DAG_CROSS_STD_PRODUCERS: the entry names a real job in
// release-matrix.yml, and build/test/release-platforms.test.mjs fails if that job
// or its action stops installing and probing, so this table cannot drift away
// from the workflow into a claim the pipeline does not honour.
export const DAG_REQUIREMENT_PRODUCERS = Object.freeze({
  'android-ndk': Object.freeze({job: 'prerequisites', action: './.github/actions/setup-release-sdk'}),
  'ohos-sdk': Object.freeze({job: 'prerequisites', action: './.github/actions/setup-release-sdk'}),
  'xcode-ios': Object.freeze({job: 'prerequisites', action: './.github/actions/setup-release-sdk'}),
});

// ARM32 is abandoned for 0.0.2 (user order: 放弃 32 位). Tuples listed here are
// present in the official package but deliberately not carried by ours.
const DROPPED_ARM32_TUPLES = Object.freeze([
  'linux_android23_arm_cjnative',
  'linux_ohos_arm_cjnative',
]);

function releasePlatform(fields) {
  return Object.freeze({
    archiveKey: fields.key,
    crossTuples: Object.freeze([]),
    requires: Object.freeze([]),
    droppedTuples: Object.freeze([]),
    crossCompiledHost: false,
    excluded: '',
    ...fields,
  });
}

const RELEASE_PLATFORMS = Object.freeze([
  releasePlatform({
    key: 'linux-x64', officialArchive: 'cangjie-sdk-linux-x64', host: 'linux-x64',
    runner: 'ubuntu-24.04', crossTuples: Object.freeze(['windows_x86_64_cjnative']),
  }),
  releasePlatform({
    key: 'linux-arm64', archiveKey: 'linux-aarch64', officialArchive: 'cangjie-sdk-linux-aarch64', host: 'linux-aarch64',
    runner: 'ubuntu-24.04-arm', crossTuples: Object.freeze(['windows_x86_64_cjnative']),
  }),
  releasePlatform({
    key: 'linux-x64-android', officialArchive: 'cangjie-sdk-linux-x64-android', host: 'linux-x64',
    runner: 'ubuntu-24.04', crossTuples: Object.freeze(['linux_android_aarch64_cjnative']),
    droppedTuples: Object.freeze(['linux_android23_arm_cjnative']), requires: Object.freeze(['android-ndk']),
  }),
  releasePlatform({
    key: 'linux-x64-ohos', officialArchive: 'cangjie-sdk-linux-x64-ohos', host: 'linux-x64',
    runner: 'ubuntu-24.04',
    crossTuples: Object.freeze(['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative', 'windows_x86_64_cjnative']),
    requires: Object.freeze(['ohos-sdk']),
  }),
  releasePlatform({
    key: 'darwin-arm64', officialArchive: 'cangjie-sdk-mac-aarch64', host: 'darwin-arm64', runner: 'macos-15',
  }),
  releasePlatform({
    key: 'darwin-x64', officialArchive: 'cangjie-sdk-mac-x64', host: 'darwin-x64', runner: 'macos-15-intel',
  }),
  releasePlatform({
    key: 'darwin-arm64-android', officialArchive: 'cangjie-sdk-mac-aarch64-android', host: 'darwin-arm64',
    runner: 'macos-15', crossTuples: Object.freeze(['linux_android_aarch64_cjnative']),
    droppedTuples: Object.freeze(['linux_android23_arm_cjnative']), requires: Object.freeze(['android-ndk']),
  }),
  releasePlatform({
    key: 'darwin-arm64-ios', officialArchive: 'cangjie-sdk-mac-aarch64-ios', host: 'darwin-arm64',
    runner: 'macos-15',
    crossTuples: Object.freeze(['ios_aarch64_cjnative', 'ios_simulator_aarch64_cjnative', 'ios_simulator_x86_64_cjnative']),
    requires: Object.freeze(['xcode-ios']),
  }),
  releasePlatform({
    key: 'darwin-arm64-ohos', officialArchive: 'cangjie-sdk-mac-aarch64-ohos', host: 'darwin-arm64',
    runner: 'macos-15', crossTuples: Object.freeze(['linux_ohos_aarch64_cjnative']),
    requires: Object.freeze(['ohos-sdk']),
  }),
  releasePlatform({
    // Device-side SDK: bin/cjc itself is an OHOS aarch64 executable (official
    // package 50.9 MB vs 64.4 MB linux-arm64), so the compiler, runtime and std
    // are all cross-compiled on a Linux host. No DAG stage does that.
    key: 'ohos-arm64', officialArchive: 'cangjie-sdk-ohos-aarch64', host: 'linux-x64', runner: 'ubuntu-24.04',
    crossTuples: Object.freeze(['linux_ohos_aarch64_cjnative']), crossCompiledHost: true,
    requires: Object.freeze(['ohos-sdk']),
  }),
  releasePlatform({
    // Cross std comes from the linux-x64 source cell; the package job itself runs
    // on Windows (release.yml phase 3).
    key: 'win32-x64', archiveKey: 'windows-x64', officialArchive: 'cangjie-sdk-windows-x64', host: 'windows-x64', runner: 'windows-2025',
  }),
  releasePlatform({
    key: 'win32-x64-android', officialArchive: 'cangjie-sdk-windows-x64-android', host: 'windows-x64',
    runner: 'windows-2025', crossTuples: Object.freeze(['linux_android_aarch64_cjnative', 'linux_x86_64_cjnative']),
    droppedTuples: Object.freeze(['linux_android23_arm_cjnative']), requires: Object.freeze(['android-ndk']),
  }),
  releasePlatform({
    key: 'win32-x64-ohos', officialArchive: 'cangjie-sdk-windows-x64-ohos', host: 'windows-x64',
    runner: 'windows-2025', crossTuples: Object.freeze(['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative']),
    requires: Object.freeze(['ohos-sdk']),
  }),
  releasePlatform({
    key: 'win32-x64-ohos-arm32', officialArchive: 'cangjie-sdk-windows-x64-ohos-arm32', host: 'windows-x64',
    runner: 'windows-2025',
    crossTuples: Object.freeze(['linux_ohos_aarch64_cjnative', 'linux_ohos_x86_64_cjnative']),
    droppedTuples: Object.freeze(['linux_ohos_arm_cjnative']), requires: Object.freeze(['ohos-sdk']),
    excluded: 'ARM32 abandoned for 0.0.2 (user order); the package exists only to carry linux_ohos_arm_cjnative',
  }),
]);

const releaseRegistry = new Map(RELEASE_PLATFORMS.map(platform => [platform.key, platform]));

export function allReleasePlatforms() {
  return RELEASE_PLATFORMS.map(platform => platform.key);
}

export function getReleasePlatform(key) {
  const platform = releaseRegistry.get(key);
  if (!platform) {
    throw new ConfigError(`unknown release platform '${key}'; valid: ${allReleasePlatforms().join(', ')}`);
  }
  return platform;
}

export function isDroppedArm32Tuple(tuple) {
  return DROPPED_ARM32_TUPLES.includes(tuple);
}

// {status: 'buildable' | 'blocked' | 'excluded', reasons: string[], ...}. `reasons`
// is empty exactly when status is 'buildable'; every blocked reason names the
// tuple or capability and what would have to exist for it to clear.
export function releasePlatformReadiness(key) {
  const platform = getReleasePlatform(key);
  const hostTarget = getTarget(platform.host);
  const reasons = [];
  if (platform.excluded) {
    return Object.freeze({key, status: 'excluded', host: platform.host, runner: platform.runner, reasons: Object.freeze([platform.excluded])});
  }
  if (platform.crossCompiledHost) {
    reasons.push(`device-side SDK: bin/cjc, runtime and std must all be cross-compiled for ${platform.crossTuples.join(', ')}; the P01-P23 DAG only builds a host SDK for ${platform.host}`);
  }
  const crossStd = {};
  for (const tuple of platform.crossTuples) {
    if (tuple === hostTarget.spec.runtimeTuple) continue;
    const producer = stdProducerFor(tuple);
    if (producer) {
      crossStd[tuple] = producer;
      continue;
    }
    if (isDroppedArm32Tuple(tuple)) {
      reasons.push(`tuple ${tuple}: ARM32 abandoned for 0.0.2 (user order)`);
      continue;
    }
    reasons.push(`tuple ${tuple}: no P01-P23 stage cross-builds a runtime and final std for it (P24 cross target)`);
  }
  for (const requirement of platform.requires) {
    const contract = RELEASE_REQUIREMENTS[requirement];
    if (!contract) throw new ConfigError(`release platform ${key} names unknown requirement '${requirement}'`);
    // Installed and probed by a DAG stage (release-matrix.yml `prerequisites`),
    // so the gap is not "nobody provides it" any more. What may still be missing
    // is the cross-built tuple above, which is reported on its own line.
    if (DAG_REQUIREMENT_PRODUCERS[requirement]) continue;
    reasons.push(`requires ${requirement}: ${contract.summary}; no DAG stage installs or consumes it`);
  }
  // The host SDK's own std comes from its source cell, except for a host whose
  // std is itself cross-built (windows-x64: linux-x64 builds final-std-windows-x64
  // and the package job runs on Windows).
  const sourceTarget = hostTarget.spec.crossCompile ? stdProducerFor(hostTarget.spec.runtimeTuple) : platform.host;
  return Object.freeze({
    key,
    status: reasons.length ? 'blocked' : 'buildable',
    host: platform.host,
    sourceTarget,
    hostStdCrossBuilt: Boolean(hostTarget.spec.crossCompile),
    runner: platform.runner,
    officialArchive: platform.officialArchive,
    archiveKey: platform.archiveKey,
    archiveFormat: hostTarget.spec.archiveFormat,
    llvmPlatform: hostTarget.spec.llvmPlatform,
    runtimeTuple: hostTarget.spec.runtimeTuple,
    crossStd: Object.freeze(crossStd),
    droppedTuples: platform.droppedTuples,
    reasons: Object.freeze(reasons),
  });
}
