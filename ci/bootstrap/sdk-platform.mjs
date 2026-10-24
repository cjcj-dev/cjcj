// Native SDK filenames belong to the frozen platform, including configuration-only
// consumers running on a different host. Never select them from process.arch.
import {PLATFORMS, reject} from './sdk-io.mjs';

export function sdkPlatform(platform) {
  const tuple = PLATFORMS[platform];
  if (!tuple) reject('PLATFORM', 'sdk', platform);
  const [os, arch, runtimeTuple] = tuple;
  return {os, arch, tuple: runtimeTuple,
    exe: os === 'win32' ? '.exe' : '',
    shared: os === 'darwin' ? '.dylib' : os === 'win32' ? '.dll' : '.so',
    loader: os === 'darwin' ? 'DYLD_LIBRARY_PATH' : os === 'win32' ? 'PATH' : 'LD_LIBRARY_PATH',
    llvmLibrary: os === 'darwin' ? 'libLLVM.dylib' : os === 'win32' ? 'libLLVM-15.dll' : 'libLLVM-15.so',
    llvmDirectory: os === 'win32' ? 'bin' : 'lib',
    nativeTargets: os === 'win32' ? ['lldb', 'all', 'install'] : ['lldb', 'cjdb', 'lldb-boundscheck', 'lldb-cangjie-lsp', 'lldb-cangjie-frontend', 'all', 'install'],
    linker: os === 'darwin' ? 'ld64.lld' : 'ld.lld'};
}

// sdk-native-stage runs the ordinary, unsanitized cjnative std build. Its
// AddCangjieSource.cmake install graph emits LTO bitcode on Linux, but not
// Windows or ordinary Darwin. CJO, static/shared core and FFI remain required
// on every supported native target; do not infer a target from the runner.
export function stdInstallFiles(platform) {
  const native = sdkPlatform(platform);
  return [
    `modules/${native.tuple}/std/std.core.cjo`,
    ...(native.os === 'linux' ? [`modules/${native.tuple}/std/libstd.core.bc`] : []),
    `lib/${native.tuple}/libcangjie-std-core.a`,
    `runtime/lib/${native.tuple}/libcangjie-std-core${native.shared}`,
    `lib/libstdFFI${native.shared}`,
  ];
}

// Node's `process.platform` name is not the name an entry recipe carries: the
// launcher and its readers compare against `windows`, and writing `win32` there
// produced a recipe the launcher refused on the very platform it was built for.
// One mapping, used by both the producer and the checker.
export const ENTRY_PLATFORM_NAMES = Object.freeze({win32: 'windows', darwin: 'darwin', linux: 'linux'});
export function entryPlatformName(platform) {
  const name = ENTRY_PLATFORM_NAMES[sdkPlatform(platform).os];
  if (!name) reject('PLATFORM', 'entry', platform);
  return name;
}

// PATH is also the Windows DLL loader. Keep both tool and library search paths.
export function sdkEnvironment(sdk, platform, base = process.env, runtimeRoot = sdk) {
  const native = sdkPlatform(platform), delimiter = native.os === 'win32' ? ';' : ':';
  const tools = [sdk+'/bin', sdk+'/tools/bin', sdk+'/third_party/llvm/bin'];
  const libraries = [runtimeRoot+'/runtime/lib/'+native.tuple, runtimeRoot+'/lib/'+native.tuple,
    sdk+'/third_party/llvm/'+native.llvmDirectory, sdk+'/tools/lib'];
  return {...base, CANGJIE_HOME:sdk,
    PATH:[...tools, ...(native.loader === 'PATH' ? libraries : []), base.PATH].filter(Boolean).join(delimiter),
    ...(native.loader === 'PATH' ? {} : {[native.loader]:[...libraries,base[native.loader]].filter(Boolean).join(delimiter)})};
}

// Installed consumers must not inherit an earlier SDK's module/library search
// path. Keep unrelated build controls (including jobserver descriptors) intact.
export function cleanSdkEnvironment(sdk,platform,base=process.env,runtimeRoot=sdk) {
  const clean={...base};
  for(const key of ['CANGJIE_HOME','CANGJIE_PATH','LIBRARY_PATH','LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT',
    'DYLD_LIBRARY_PATH','DYLD_FALLBACK_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH'])delete clean[key];
  if(base.CANGJIE_HOME) {
    const delimiter=sdkPlatform(platform).os==='win32'?';':':';
    clean.PATH=(base.PATH||'').split(delimiter).filter(p=>p!==base.CANGJIE_HOME&&!p.startsWith(base.CANGJIE_HOME+'/')&&!p.startsWith(base.CANGJIE_HOME+'\\')).join(delimiter);
  }
  return sdkEnvironment(sdk,platform,clean,runtimeRoot);
}
