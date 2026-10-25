#!/usr/bin/env zx
// Consume native producer installations; this does not assemble or qualify a full SDK.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {darwinPlatform, verifyDarwinMachO, verifyDarwinLlvm} from './darwin_llvm.mjs';
import {hostIdentity, prepareHostLlvm} from './host_llvm.mjs';
import {bootstrapArtifact} from './bootstrap_artifact.mjs';
import {darwinCommand} from './darwin_commands.mjs';

export function darwinConsumerHost(target = process.env.CJCJ_SRCBUILD_TARGET) {
  // The real host decides this before any acquisition or external command.
  assert.equal(process.platform, 'darwin', 'DARWIN_CONSUMER_NATIVE_HOST');
  const host = darwinPlatform(hostPlatform());
  assert.equal(target, `darwin-${host.arch}`, 'DARWIN_CONSUMER_HOST_TARGET');
  return host;
}
export function loadDarwinPins(platform) {
  for (const relative of ['runtime_pin.env', 'llvm_pin.env',
    `llvm-dylib/${platform}.env`, `colour-runtime/${platform}.env`]) {
    for (const line of fs.readFileSync(new URL(`../${relative}`, import.meta.url), 'utf8').split('\n')) {
      const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
      if (match) process.env[match[1]] = match[2];
    }
  }
}
export function consumeDarwinInputs(work, target = process.env.CJCJ_SRCBUILD_TARGET) {
  const host = darwinConsumerHost(target);
  work = path.resolve(work);
  const logs = path.join(work, 'commands');
  const execute = (label, command, args) => darwinCommand(logs, label, command, args);
  assert.ok(process.env.SCCACHE_PATH, 'DARWIN_CONSUMER_SCCACHE_REQUIRED');
  const tools = Object.fromEntries(['clang++', 'nm', 'lipo'].map(name =>
    [name, execute(`find-${name}`, 'xcrun', ['--find', name]).stdout.trim()]));
  const appleSdk = execute('apple-sdk', 'xcrun', ['--sdk', 'macosx', '--show-sdk-path']).stdout.trim();
  assert.ok(fs.statSync(appleSdk).isDirectory(), 'DARWIN_CONSUMER_APPLE_SDK');
  const hostPin = hostIdentity();
  const hostRoot = bootstrapArtifact(process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT,
    hostPin.repository, hostPin.artifact_id, work, 'HOST_LLVM');
  process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT = hostRoot;
  process.env.CJCJ_BOOTSTRAP_HOST_LLVM_WORK = work;
  const hostBinary = verifyDarwinMachO(prepareHostLlvm().file, host.platform);
  const colourRoot = bootstrapArtifact(process.env.CJCJ_BOOTSTRAP_DYLIB_ARTIFACT,
    'cjcj-dev/cjcj', process.env.LLVM_DYLIB_ARTIFACT_ID, work, 'LLVM_DYLIB');
  const colour = verifyDarwinLlvm(colourRoot, host.platform, process.env.LLVM_SHA);
  const runtimeRoot = bootstrapArtifact(process.env.CJCJ_BOOTSTRAP_COLOUR_RT,
    'cjcj-dev/cjcj', process.env.COLOUR_RT_ARTIFACT_ID, work, 'COLOUR_RT');
  // A freshly installed runtime records SOURCE_SHA; published native artifacts
  // carry the same producer fact in their existing manifest.
  const sourceFile = path.join(runtimeRoot, 'SOURCE_SHA');
  const runtimeManifest = fs.existsSync(sourceFile) ? null
    : JSON.parse(fs.readFileSync(path.join(runtimeRoot, 'manifest.json'), 'utf8'));
  const runtimeSha = runtimeManifest?.runtime_sha || fs.readFileSync(sourceFile, 'utf8').trim();
  assert.match(process.env.RUNTIME_REF || '', /^[a-f0-9]{40}$/, 'DARWIN_RUNTIME_SOURCE_PIN');
  assert.equal(runtimeSha, process.env.RUNTIME_REF, 'DARWIN_RUNTIME_SOURCE_MISMATCH');
  if (runtimeManifest) assert.equal(runtimeManifest.platform, host.platform, 'DARWIN_RUNTIME_PLATFORM_MISMATCH');
  const runtimeBinaries = ['libcangjie-runtime.dylib', 'libboundscheck.dylib']
    .map(name => verifyDarwinMachO(path.join(runtimeRoot, 'runtime/lib', host.tuple, name), host.platform));
  const architecture = execute('runtime-archive', tools.lipo,
    ['-archs', path.join(runtimeRoot, 'lib', host.tuple, 'libcangjie-runtime.a')]).stdout.trim();
  assert.equal(architecture, host.arch === 'arm64' ? 'arm64' : 'x86_64', 'DARWIN_RUNTIME_ARCHIVE_CPU');
  // Defined export, not a dependency's symbol. Never invoke a safepoint without
  // a managed caller; the runtime arm proves load/binding, with ABI hold intact.
  const exported = execute('runtime-exports', tools.nm, ['-g', '-U', runtimeBinaries[0].file]).stdout;
  const defined = new Set(exported.split('\n').map(line => line.trim().split(/\s+/).at(-1)));
  for (const symbol of ['CJ_MCC_HandleReturnSafepoint', 'CJ_MCC_PackageInitBegin',
    'CJ_MCC_PackageInitComplete', 'CJ_MCC_PackageInitFail', 'CJ_MCC_PackageInitAbort'])
    assert.ok(defined.has('_'+symbol), `DARWIN_RUNTIME_EXPORT_MISSING ${symbol}`);
  const bounds = execute('bounds-exports', tools.nm, ['-g', '-U', runtimeBinaries[1].file]).stdout;
  assert.match(bounds, /\b_memcpy_s\s*$/m, 'DARWIN_BOUNDSCHECK_EXPORT_MISSING');
  const loader = path.join(work, 'darwin-loader');
  execute('compile-loader', process.env.SCCACHE_PATH, [tools['clang++'], '-std=c++17', '-isysroot', appleSdk,
    fileURLToPath(new URL('./darwin_loader.cpp', import.meta.url)), '-o', loader]);
  const loaded = [];
  for (const [stage, binary, symbol, mode] of [['host-llvm', hostBinary, 'LLVMContextCreate', 'llvm'],
    ['colour-llvm', colour, 'LLVMContextCreate', 'llvm'],
    ['runtime', runtimeBinaries[0], 'CJ_MCC_HandleReturnSafepoint', 'runtime'],
    ['boundscheck', runtimeBinaries[1], 'memcpy_s', 'boundscheck']]) {
    const result = execute(stage, loader, [binary.file, symbol, mode]);
    const origin = /^DARWIN_LOADED_ORIGIN (.+)$/m.exec(result.stdout)?.[1];
    assert.equal(origin, fs.realpathSync(binary.file), 'DARWIN_CONSUMER_LOADED_ORIGIN');
    if (mode === 'llvm') assert.match(result.stdout, /DARWIN_LLVM_CONTEXT_OK/, 'DARWIN_CONSUMER_FUNCTION_CALL');
    loaded.push({...binary, loaded:origin, symbol, mode});
  }
  const result = {target, platform:host.platform, tuple:host.tuple, tools, apple_sdk:appleSdk,
    inputs:{host_llvm:hostRoot, colour_llvm:colourRoot, runtime:runtimeRoot},
    sources:{llvm:process.env.LLVM_SHA, runtime:runtimeSha}, loader, loaded,
    runtime_archive_architecture:architecture, full_sdk:'NOT_RUN', runtime_abi:'NOT_RUN'};
  fs.writeFileSync(path.join(work, 'darwin-consumer.json'), JSON.stringify(result, null, 2)+'\n');
  console.log(`DARWIN_NATIVE_INPUT_CONSUMED host_tuple=${host.tuple} target=${target}`);
  return result;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { consumeDarwinInputs(process.argv[2], process.argv[3]); }
  catch (error) { console.error(error.stack); process.exitCode = error.exitCode || 1; }
}
