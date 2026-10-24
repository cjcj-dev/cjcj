// Build execution context, separate from the release/source-producer registry.
import {getTarget, assertHostContract} from './targets.mjs';
import {ConfigError} from './errors.mjs';

export function getBuildTarget(key, {platform = process.platform, arch = process.arch, env = process.env} = {}) {
  const target = getTarget(key);
  if (key !== 'windows-x64' || platform !== 'win32' || arch !== 'x64') return target;
  return Object.freeze({
    ...target,
    spec: Object.freeze({
      ...target.spec,
      crossCompile: false, needsMingw: false, nodePlatform: 'win32',
      hostRuntimeTuple: target.spec.runtimeTuple,
      hostRuntimeLibrary: target.spec.runtimeLibrary,
      llvmBinDir: env.CJCJ_NATIVE_LLVM_BIN || null,
      opensslLibDir: env.CJCJ_NATIVE_OPENSSL_LIB || null,
      loaderEnv: 'PATH', legacyNcursesPackages: false,
    }),
    compilerOutputDirs: () => ['output'],
    primaryCompilerOutput: () => 'output',
    hostRuntimeOutputSubdir: target.runtimeOutputSubdir,
  });
}

export function assertBuildHostContract(key, options = {}) {
  const platform = options.platform ?? process.platform;
  const arch = options.arch ?? process.arch;
  if (key !== 'windows-x64' || platform !== 'win32' || arch !== 'x64') return assertHostContract(key, options);
  const profile = options.profile ?? 'generic';
  if (profile !== 'generic') throw new ConfigError(`native Windows requires generic host profile, received ${profile}`);
  return Object.freeze({target: key, platform, arch, sdkName: key, crossCompile: false,
    kkk2Supported: false, requiredHost: 'win32/x64 (cross=no)'});
}
