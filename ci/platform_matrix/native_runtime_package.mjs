#!/usr/bin/env zx
// Consume the normal native install, then the very same package on this host.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sdkPlatform, cleanSdkEnvironment} from '../bootstrap/sdk-platform.mjs';
import {verifyEntryFormat} from '../bootstrap/sdk-entry-producer.mjs';
import {darwinCommand as command} from '../release/darwin_commands.mjs';

const root = path.resolve(process.env.PLATFORM_CI_ROOT || '.platform-ci');
const source = path.resolve(process.env.RUNTIME_SOURCE || 'runtime-source');
const platform = process.env.NATIVE_RUNTIME_PLATFORM;
const native = sdkPlatform(platform);
assert.ok(['linux', 'darwin'].includes(native.os), 'NATIVE_CONSUMER_PLATFORM');
assert.equal(native.os, process.platform, 'NATIVE_CONSUMER_HOST');
assert.equal(native.arch, process.arch, 'NATIVE_CONSUMER_CPU');
const install = path.join(root, 'runtime-install');
const work = path.join(root, 'native-consumers');
fs.mkdirSync(work); // One execution owns this evidence directory; never replace a previous run.
const summary = {platform, source, install, installed:'NOT_RUN', package:'NOT_RUN',
  unpack:'NOT_RUN', unpacked:'NOT_RUN', rc:null};
const run = (label, executable, args, options = {}) => command(work, label, executable, args,
  {cwd:root, ...options});
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function members(directory, relative = '') {
  const result = {};
  for (const name of fs.readdirSync(path.join(directory, relative)).sort()) {
    const entry = path.join(relative, name), file = path.join(directory, entry), stat = fs.lstatSync(file);
    if (stat.isDirectory()) Object.assign(result, members(directory, entry));
    else if (stat.isSymbolicLink()) result[entry] = {link:fs.readlinkSync(file)};
    else { assert.ok(stat.isFile(), 'NATIVE_PACKAGE_REGULAR_FILE'); result[entry] = {size:stat.size, sha256:digest(file)}; }
  }
  return result;
}
try {
  const facts = JSON.parse(fs.readFileSync(path.join(install, 'NATIVE-INPUTS.json'), 'utf8'));
  assert.equal(facts.platform, platform, 'NATIVE_CONSUMER_INSTALL_PLATFORM');
  assert.equal(fs.readFileSync(path.join(install, 'SOURCE_SHA'), 'utf8').trim(), facts.runtime_sha,
    'NATIVE_CONSUMER_INSTALL_SOURCE');
  assert.equal(facts.runtime_sha, process.env.CJCJ_NATIVE_RUNTIME_REF, 'NATIVE_CONSUMER_SELECTED_SOURCE');
  summary.runtime_sha = facts.runtime_sha;
  summary.paired_llvm_sha = facts.paired_llvm_sha; // Source fact only; no LLVM binary is consumed here.
  const cache = fs.readFileSync(path.join(source, 'runtime/CMakebuild/CMakeCache.txt'), 'utf8');
  const value = key => new RegExp(`^${key}:[^=]+=(.*)$`, 'm').exec(cache)?.[1]?.trim();
  const compiler = value('CMAKE_CXX_COMPILER');
  assert.ok(path.isAbsolute(compiler || ''), 'NATIVE_CONSUMER_CONFIGURED_COMPILER');
  const launcher = value('CMAKE_CXX_COMPILER_LAUNCHER');
  assert.ok(!launcher || path.isAbsolute(launcher) && !launcher.includes(';'), 'NATIVE_CONSUMER_COMPILER_LAUNCHER');
  run('compiler-version', compiler, ['--version']);
  const loader = path.join(work, 'native-loader');
  const args = ['-std=c++17', fileURLToPath(new URL('../release/darwin_loader.cpp', import.meta.url)),
    ...(native.os === 'linux' ? ['-ldl'] : []), '-o', loader];
  if (native.os === 'darwin') {
    const sysroot = value('CMAKE_OSX_SYSROOT');
    if (sysroot) args.unshift('-isysroot', sysroot);
    args.unshift('-arch', native.arch === 'arm64' ? 'arm64' : 'x86_64');
  }
  run('compile-loader', launcher || compiler, launcher ? [compiler, ...args] : args);
  await verifyEntryFormat(loader, platform);
  async function consume(prefix, phase) {
    const env = cleanSdkEnvironment(prefix, platform);
    // Only this prefix contributes runtime library directories. System libraries remain native OS dependencies.
    const libraryDirectory = path.join(prefix, 'runtime/lib', native.tuple);
    env[native.loader] = libraryDirectory;
    summary[phase] = {runtime:'NOT_RUN', bounds:'NOT_RUN', libraryDirectory};
    for (const [role, basename, symbol, mode] of [
      ['runtime', 'libcangjie-runtime', 'CJ_MCC_HandleReturnSafepoint', 'runtime'],
      ['bounds', 'libboundscheck', 'memcpy_s', 'boundscheck'],
    ]) {
      const library = path.join(libraryDirectory, basename + native.shared);
      assert.ok(fs.existsSync(library), `NATIVE_LIBRARY_MISSING ${phase} ${role}: ${library}`);
      await verifyEntryFormat(library, platform);
      if (native.os === 'darwin') assert.equal(fs.readFileSync(library).readUInt32LE(12), 6, 'NATIVE_MACHO_DYLIB');
      summary[phase][role] = {library, sha256:digest(library), rc:null};
      run(`${phase}-${role}`, loader, [library, symbol, mode], {env});
      summary[phase][role].rc = 0;
    }
  }
  await consume(install, 'installed');
  const original = members(install);
  assert.ok(!fs.existsSync(path.join(root, 'runtime-install.tar')), 'NATIVE_PACKAGE_ALREADY_EXISTS');
  run('package', 'tar', ['-cf', './runtime-install.tar', '-C', './runtime-install', '.']);
  summary.package = 0;
  const unpack = path.join(root, 'runtime-unpacked');
  fs.mkdirSync(unpack); // Must be fresh, including when an earlier unpack failed.
  run('unpack', 'tar', ['-xf', './runtime-install.tar', '-C', './runtime-unpacked']);
  summary.unpack = 0;
  assert.deepEqual(members(unpack), original, 'NATIVE_PACKAGE_MEMBER_BYTES');
  fs.writeFileSync(path.join(work, 'package-members.json'), JSON.stringify(original, null, 2)+'\n');
  await consume(unpack, 'unpacked');
  summary.rc = 0;
} catch (error) {
  summary.rc = error.exitCode || 1;
  summary.error = error.message;
  process.exitCode = summary.rc;
  console.error(error.stack);
} finally {
  fs.writeFileSync(path.join(work, 'summary.json'), JSON.stringify(summary, null, 2)+'\n');
}
