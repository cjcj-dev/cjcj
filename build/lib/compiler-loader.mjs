import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {sdkEnvironment} from './sdk-environment.mjs';

function probe(command, args, env) {
  const result = spawnSync(command, args, {encoding: 'utf8', env, maxBuffer: 16 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status}): ${result.stderr}`);
  return result.stdout;
}

export function compilerLlvmName(platform) {
  return platform.startsWith('linux-') ? 'libLLVM-15.so'
    : platform.startsWith('darwin-') ? 'libLLVM.dylib' : null;
}

function llvmDependencies(binary, platform) {
  if (platform.startsWith('linux-')) {
    return [...probe('readelf', ['-d', binary]).matchAll(/\(NEEDED\).*\[([^\]]+)\]/g)]
      .map(match => match[1]).filter(name => /libLLVM/.test(name));
  }
  if (platform.startsWith('darwin-')) {
    return probe('otool', ['-L', binary]).split('\n').slice(1)
      .map(line => line.trim().split(/\s+\(/)[0]).filter(name => /libLLVM/.test(name));
  }
  return [];
}

// Keep cjc's LLVM separate from the SDK debugger's library. Unlike upstream's
// static cjc, this compiler consumes a shared LLVM from its build SDK.
export async function prepareCompilerLoader({sdk, platform, expectedSha256}) {
  const binary = path.join(sdk, 'bin/cjc');
  const dependencies = llvmDependencies(binary, platform);
  if (!dependencies.length) return undefined;
  const name = compilerLlvmName(platform);
  if (dependencies.length !== 1 || path.basename(dependencies[0]) !== name) {
    throw new Error(`unexpected compiler LLVM dependencies: ${dependencies.join(', ')}`);
  }
  const source = path.join(sdk, 'third_party/llvm/lib', name);
  const actual = crypto.createHash('sha256').update(await fs.readFile(source)).digest('hex');
  if (actual !== expectedSha256) throw new Error('compiler build LLVM SHA-256 mismatch');
  const library = path.join(sdk, 'third_party/cjc/lib', name);
  await fs.mkdir(path.dirname(library), {recursive: true});
  await fs.copyFile(source, library);
  if (platform.startsWith('linux-')) {
    // Do this after cjpm, which interprets $ORIGIN in link-option as an env var.
    probe('patchelf', ['--set-rpath', '$ORIGIN/../third_party/cjc/lib', binary]);
  } else {
    probe('install_name_tool', ['-id', `@rpath/${name}`, library]);
    probe('install_name_tool', ['-change', dependencies[0], `@rpath/${name}`, binary]);
  }
  return library;
}

export async function assertCompilerLoader({sdk, platform}) {
  if (platform.startsWith('windows-')) return; // PE uses the existing static LLVM tuple.
  const binary = path.join(sdk, 'bin/cjc');
  if (platform.startsWith('darwin-')) {
    const dependencies = llvmDependencies(binary, platform);
    const commands = probe('otool', ['-l', binary]);
    const paths = [...commands.matchAll(/cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset/g)].map(match => match[1]);
    if (paths.some(entry => !entry.startsWith('@loader_path/'))) {
      throw new Error(`compiler search path is not SDK-relative: ${paths.join(':')}`);
    }
    if (dependencies.length) {
      if (dependencies.length !== 1 || dependencies[0] !== '@rpath/libLLVM.dylib'
        || !paths.includes('@loader_path/../third_party/cjc/lib')) {
        throw new Error('compiler LLVM Mach-O lookup is not SDK-relative');
      }
      await fs.access(path.join(sdk, 'third_party/cjc/lib/libLLVM.dylib'));
    }
    console.log(`COMPILER_MACHO_LOOKUP_OK ${binary}`);
    return;
  }
  if (!platform.startsWith('linux-')) throw new Error(`unsupported compiler platform: ${platform}`);
  const dynamic = probe('readelf', ['-d', binary]);
  const paths = [...dynamic.matchAll(/\((?:RUNPATH|RPATH)\).*\[([^\]]*)\]/g)].flatMap(match => match[1].split(':'));
  if (paths.some(entry => !entry.startsWith('$ORIGIN/'))) {
    throw new Error(`compiler search path is not SDK-relative: ${paths.join(':')}`);
  }
  const dependencies = llvmDependencies(binary, platform);
  if (dependencies.length && (!/\(RUNPATH\)/.test(dynamic) || !paths.includes('$ORIGIN/../third_party/cjc/lib'))) {
    throw new Error('compiler LLVM RUNPATH missing $ORIGIN/../third_party/cjc/lib');
  }
  const output = probe('ldd', [binary], sdkEnvironment(sdk));
  if (/not found/.test(output)) throw new Error(`compiler unresolved dependency:\n${output}`);
  if (dependencies.length) {
    const name = compilerLlvmName(platform);
    const resolved = output.split('\n').map(line => line.trim().match(/^(\S+) => (.*?) \(0x/))
      .filter(Boolean).filter(match => match[1] === name);
    const expected = await fs.realpath(path.join(sdk, 'third_party/cjc/lib', name));
    if (resolved.length !== 1 || await fs.realpath(resolved[0][2]) !== expected) {
      throw new Error(`compiler LLVM resolved outside its SDK: ${output}`);
    }
    console.log(`COMPILER_LLVM_RESOLVED ${name} => ${expected}`);
  }
  console.log(`COMPILER_LOADER_OK ${binary}`);
}
