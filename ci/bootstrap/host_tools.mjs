#!/usr/bin/env zx
// Native bootstrap conventions: host_llvm.mjs:9 and build_tuple.sh:23.
// Keep the machine identity separate from the selected compilation target.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {getTarget} from '../../build/lib/targets.mjs';

export function nativeHost() {
  if (!['linux', 'darwin'].includes(process.platform)
      || !['x64', 'arm64'].includes(process.arch)) {
    throw new Error(`BOOTSTRAP_HOST_UNSUPPORTED ${process.platform}/${process.arch}`);
  }
  const key = `${process.platform}-${process.platform === 'linux' && process.arch === 'arm64' ? 'aarch64' : process.arch}`;
  const {spec} = getTarget(key);
  const darwin = spec.os === 'darwin';
  return Object.freeze({
    tuple: spec.runtimeTuple,
    platform: spec.llvmPlatform,
    os: spec.os,
    arch: spec.arch,
    library: spec.hostLlvmLibrary,
    runtimeLibrary: spec.runtimeLibrary,
    librarySuffix: spec.sharedLibrarySuffix,
    linker: darwin ? 'ld64.lld' : 'ld.lld',
    loader: spec.loaderEnv,
    format: spec.fileFormat,
    multiarch: darwin ? '' : `${spec.arch}-linux-gnu`,
    systemPath: darwin
      ? '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
      : '/usr/bin:/bin',
    dynsymRuler: darwin ? 'native-nm-defined' : 'readelf--dyn-syms',
  });
}

// Capture the native child's real rc; callers may inspect failures explicitly.
export function execute(command, args, {check = true, ...options} = {}) {
  const result = spawnSync(command, args, {encoding:'utf8', maxBuffer:128 * 1024 * 1024, ...options});
  if (result.error) throw result.error;
  const out = {stdout:result.stdout || '', stderr:result.stderr || '', exitCode:result.status, signal:result.signal};
  if (check && (out.exitCode !== 0 || out.signal)) {
    const error = new Error(`${command} rc=${out.exitCode} signal=${out.signal || 'none'} ${out.stderr.trim()}`);
    error.exitCode = out.exitCode; error.signal = out.signal; throw error;
  }
  return out;
}

// The GNU utilities preserve the existing manifest and cache byte formats.
// zx interpolates each argument separately; filenames never become shell code.
export async function fileTool(tool, args) {
  if (!['sha256sum', 'readlink', 'install', 'sort', 'tar', 'find'].includes(tool)) {
    throw new Error(`BOOTSTRAP_FILE_TOOL_UNSUPPORTED ${tool}`);
  }
  const command = `${nativeHost().os === 'darwin' ? 'g' : ''}${tool}`;
  return execute(command, args);
}

// Candidate host_nm.py:9-32, preserving the native tool's actual return code.
export async function readSymbols(args) {
  const darwin = nativeHost().os === 'darwin';
  const translated = darwin
    ? args.map(arg => arg === '-D' ? '-g' : arg === '--defined-only' ? '-U' : arg)
    : args;
  const command = darwin ? ['xcrun', 'nm'] : ['nm'];
  const result = execute(command[0], [...command.slice(1), ...translated], {check:false});
  const stdout = darwin
    ? result.stdout.replace(/^(.*\s[A-Za-z?]\s+)_([^\s]+)(\r?)$/gm, '$1$2$3')
    : result.stdout;
  return {stdout, stderr: result.stderr, exitCode: result.exitCode};
}

// Do not carry credentials or unrelated caller variables into env -i builds.
export function compilerCacheEnvironment() {
  const names = [
    'CMAKE_C_COMPILER_LAUNCHER', 'CMAKE_CXX_COMPILER_LAUNCHER', 'CMAKE_ASM_COMPILER_LAUNCHER',
    'SCCACHE_PATH', 'SCCACHE_DIR', 'SCCACHE_CACHE_SIZE', 'SCCACHE_IDLE_TIMEOUT',
    'SCCACHE_GHA_ENABLED', 'SCCACHE_LOG', 'SCCACHE_ERROR_LOG',
  ];
  return Object.fromEntries(names.filter(name => process.env[name])
    .map(name => [name, process.env[name]]));
}

// Official Option.cpp consumes SDKROOT for Darwin native system libraries.
export async function nativeEnvironment() {
  if (nativeHost().os !== 'darwin') return {};
  const root = process.env.SDKROOT || execute('xcrun', ['--sdk', 'macosx', '--show-sdk-path']).stdout.trim();
  if (!fs.statSync(root).isDirectory()) throw new Error(`BOOTSTRAP_SDKROOT_MISSING ${root}`);
  return {SDKROOT: root};
}

// stdlib/cmake/darwin_toolchain.cmake requires LLVM archive tools. This path
// belongs to std builds; it must not replace the native compiler tool domain.
export async function stdSystemPath() {
  const host = nativeHost();
  if (host.os !== 'darwin') return host.systemPath;
  const prefix = execute('brew', ['--prefix', 'llvm@16']).stdout.trim();
  fs.accessSync(path.join(prefix, 'bin', 'llvm-ranlib'), fs.constants.X_OK);
  return `${prefix}/bin:${host.systemPath}`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3 || !['identity', 'tuple'].includes(process.argv[2])) {
    throw new Error('usage: host_tools.mjs identity|tuple');
  }
  const host = nativeHost();
  console.log(process.argv[2] === 'tuple' ? host.tuple : JSON.stringify(host));
}
