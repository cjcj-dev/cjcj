// Port of cangjie-build/src/cangjie_build/targets.py.

import {ConfigError} from './errors.mjs';

const linuxX64 = Object.freeze({
  spec: Object.freeze({
    key: 'linux-x64', sdkName: 'linux-x64', archiveFormat: 'tar.gz',
    exeSuffix: '', outputDirSuffix: 'x86_64', crossCompile: false, needsMingw: false,
  }),
  compilerOutputDirs: () => ['output'],
  runtimeOutputSubdir: buildType => `linux_${buildType.toLowerCase()}_x86_64`,
  runtimeLibSubdir: buildType => `linux_${buildType.toLowerCase()}_x86_64_cjnative`,
  stdxTargetSubdir: () => 'linux_x86_64_cjnative',
  primaryCompilerOutput: () => 'output',
});

const windowsX64 = Object.freeze({
  spec: Object.freeze({
    key: 'windows-x64', sdkName: 'windows-x64', archiveFormat: 'zip',
    exeSuffix: '.exe', outputDirSuffix: 'x86_64', crossCompile: true, needsMingw: true,
  }),
  compilerOutputDirs: () => ['output', 'output-x86_64-w64-mingw32'],
  runtimeOutputSubdir: buildType => `windows_${buildType.toLowerCase()}_x86_64`,
  runtimeLibSubdir: buildType => `windows_${buildType.toLowerCase()}_x86_64_cjnative`,
  stdxTargetSubdir: () => 'windows_x86_64_cjnative',
  primaryCompilerOutput: () => 'output-x86_64-w64-mingw32',
});

const registry = new Map([
  [linuxX64.spec.key, linuxX64],
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
