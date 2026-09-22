// Platform contracts follow cangjie_build/docs/linux.md:127-175,228-259 and
// cangjie_build/docs/macos.md:82-116,157-196. Native targets deliberately keep
// architecture, runtime tuple, LLVM artifact, loader environment, and final-std
// shape together so later stages never infer a release tuple from the runner.

import {ConfigError} from './errors.mjs';

const linuxX64 = Object.freeze({
  spec: Object.freeze({
    key: 'linux-x64', sdkName: 'linux-x64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
    kkk2Supported: true,
    needsStaticLibs: true, os: 'linux', arch: 'x86_64', nodePlatform: 'linux', nodeArch: 'x64',
    runtimeTuple: 'linux_x86_64_cjnative', llvmPlatform: 'linux_x86_64',
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
  spec: Object.freeze({
    key: 'linux-aarch64', sdkName: 'linux-aarch64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'aarch64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: true, os: 'linux', arch: 'aarch64', nodePlatform: 'linux', nodeArch: 'arm64',
    runtimeTuple: 'linux_aarch64_cjnative', llvmPlatform: 'linux_aarch64',
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
  spec: Object.freeze({
    key: 'darwin-arm64', sdkName: 'mac-aarch64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'aarch64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'darwin', arch: 'aarch64', nodePlatform: 'darwin', nodeArch: 'arm64',
    runtimeTuple: 'darwin_aarch64_cjnative', llvmPlatform: 'darwin_aarch64',
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
  spec: Object.freeze({
    key: 'darwin-x64', sdkName: 'mac-x64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'darwin', arch: 'x86_64', nodePlatform: 'darwin', nodeArch: 'x64',
    runtimeTuple: 'darwin_x86_64_cjnative', llvmPlatform: 'darwin_x86_64',
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
    exeSuffix: '.exe', outputDirSuffix: 'x86_64', crossCompile: true, needsMingw: true,
    kkk2Supported: false,
    needsStaticLibs: false, os: 'windows', arch: 'x86_64', nodePlatform: 'linux', nodeArch: 'x64',
    runtimeTuple: 'windows_x86_64_cjnative', llvmPlatform: 'windows_x86_64',
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
// source cell only (srcbuild.yml `if: matrix.target == 'linux-x64'`), so the
// Windows tuple is the one tuple with a producer other than its own host.
const DAG_CROSS_STD_PRODUCERS = Object.freeze({
  windows_x86_64_cjnative: 'linux-x64',
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

// ARM32 is abandoned for 0.0.2 (user order: 放弃 32 位). Tuples listed here are
// present in the official package but deliberately not carried by ours.
const DROPPED_ARM32_TUPLES = Object.freeze([
  'linux_android23_arm_cjnative',
  'linux_ohos_arm_cjnative',
]);

function releasePlatform(fields) {
  return Object.freeze({
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
    key: 'linux-arm64', officialArchive: 'cangjie-sdk-linux-aarch64', host: 'linux-aarch64',
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
    key: 'win32-x64', officialArchive: 'cangjie-sdk-windows-x64', host: 'windows-x64', runner: 'windows-2025',
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
    archiveFormat: hostTarget.spec.archiveFormat,
    llvmPlatform: hostTarget.spec.llvmPlatform,
    runtimeTuple: hostTarget.spec.runtimeTuple,
    crossStd: Object.freeze(crossStd),
    droppedTuples: platform.droppedTuples,
    reasons: Object.freeze(reasons),
  });
}
