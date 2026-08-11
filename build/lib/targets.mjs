// Platform contracts follow cangjie_build/docs/linux.md:127-175,228-259 and
// cangjie_build/docs/macos.md:82-116,157-196. Native targets deliberately keep
// architecture, runtime tuple, LLVM artifact, loader environment, and final-std
// shape together so later stages never infer a release tuple from the runner.

import {ConfigError} from './errors.mjs';

const linuxX64 = Object.freeze({
  spec: Object.freeze({
    key: 'linux-x64', sdkName: 'linux-x64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
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
  if (!target) throw new ConfigError(`unknown target '${key}'; valid: ${allTargets().join(', ')}`);
  return target;
}

export function allTargets() {
  return [...registry.keys()].sort();
}
