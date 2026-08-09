#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import {getTarget} from '../../../build/lib/targets.mjs';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubEnv = process.env.GITHUB_ENV;
const githubPath = process.env.GITHUB_PATH;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
if (!workspace || !githubEnv || !githubPath || !targetKey) {
  throw new Error('CANGJIE_WORKSPACE, GITHUB_ENV, GITHUB_PATH and CJCJ_SRCBUILD_TARGET are required');
}
const target = getTarget(targetKey);
const {spec} = target;
if (process.platform !== spec.nodePlatform || process.arch !== spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${spec.nodePlatform}/${spec.nodeArch}, current ${process.platform}/${process.arch}`);
}

const root = path.resolve(import.meta.dirname, '../../..');
const sdk = path.join(workspace, 'software', 'cangjie');
const fixedRoot = path.resolve(process.env.CJCJ_FIXED_LLVM_DIR || '.srcbuild/fixed-llc');
const llvmBin = path.join(sdk, 'third_party', 'llvm', 'bin');
const llvmLib = path.join(sdk, 'third_party', 'llvm', 'lib');

function parseManifest(text, label) {
  const result = {};
  for (const line of text.split(/\r?\n/).filter(Boolean)) {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`${label}: malformed line: ${line}`);
    const key = line.slice(0, separator);
    if (key in result) throw new Error(`${label}: duplicate key: ${key}`);
    result[key] = line.slice(separator + 1);
  }
  return result;
}

const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const manifestFile = path.join(fixedRoot, 'llvm-tools.manifest');
const manifest = parseManifest(await fs.readFile(manifestFile, 'utf8'), manifestFile);
const pins = parseManifest(await fs.readFile(path.join(root, 'ci', 'llvm_pin.env'), 'utf8'), 'ci/llvm_pin.env');
for (const [key, expected] of [
  ['PLATFORM', spec.llvmPlatform],
  ['LLVM_SHA', pins.LLVM_SHA],
  ['CANGJIE_COMPILER_SHA', pins.CANGJIE_COMPILER_SHA],
  ['FLATBUFFERS_SHA', pins.FLATBUFFERS_SHA],
]) {
  if (manifest[key] !== expected) throw new Error(`fixed LLVM manifest ${key}: expected ${expected}, got ${manifest[key]}`);
}

const versions = {};
for (const [tool, hashKey] of [['llc', 'LLC_SHA256'], ['opt', 'OPT_SHA256']]) {
  const compressed = await fs.readFile(path.join(fixedRoot, `${tool}.gz`));
  const binary = zlib.gunzipSync(compressed);
  const digest = sha256(binary);
  if (digest !== manifest[hashKey]) {
    throw new Error(`${tool} sha256 mismatch: expected ${manifest[hashKey]}, got ${digest}`);
  }
  const temporary = path.join(llvmBin, `${tool}.fixed`);
  await fs.writeFile(temporary, binary, {mode: 0o755});
  const kind = (await $({stdio: 'pipe'})`file -b ${temporary}`).stdout.trim();
  if (!kind.includes(spec.fileFormat) || !kind.includes(spec.fileArch)) {
    throw new Error(`${tool} has wrong native format for ${targetKey}: ${kind}`);
  }
  const version = await $({stdio: 'pipe'})`${temporary} --version`;
  versions[tool] = `${version.stdout}${version.stderr}`.trim();
  await fs.rename(temporary, path.join(llvmBin, tool));
}
if (versions.llc !== versions.opt) throw new Error('fixed llc and opt report different versions');

// A successful --version is necessary but not sufficient: validate every LLVM
// executable consumed by cjcj, then use the native loader inspector. This is our
// fixed-tuple check in addition to the official compiler/runtime/std build order.
for (const tool of ['llc', 'opt', 'llvm-objcopy', 'llvm-ar', 'llvm-strip']) {
  const executable = path.join(llvmBin, tool);
  const kind = (await $({stdio: 'pipe'})`file -b ${executable}`).stdout.trim();
  if (!kind.includes(spec.fileFormat) || !kind.includes(spec.fileArch)) {
    throw new Error(`${tool} has wrong native format for ${targetKey}: ${kind}`);
  }
  await $`set -o pipefail; ${executable} --version | head -3`;
  if (spec.os === 'darwin') {
    await $`otool -L ${executable}`;
  } else {
    const dependencies = await $({stdio: 'pipe'})`ldd ${executable}`;
    if (/not found/i.test(dependencies.stdout)) throw new Error(`${tool} has unresolved dependencies`);
  }
}

const shim = path.join(fixedRoot, 'cjselfhost_llvmshim.o');
const shimData = await fs.readFile(shim);
if (sha256(shimData) !== manifest.SHIM_SHA256) throw new Error('fixed LLVM shim sha256 mismatch');
const shimKind = (await $({stdio: 'pipe'})`file -b ${shim}`).stdout.trim();
if (!shimKind.includes(spec.fileFormat) || !shimKind.includes(spec.fileArch)) {
  throw new Error(`LLVM shim has wrong native format for ${targetKey}: ${shimKind}`);
}
await fs.copyFile(manifestFile, path.join(sdk, 'third_party', 'llvm', 'LLVM_TOOLS_MANIFEST'));

const runtimeLib = path.join(sdk, 'runtime', 'lib', spec.runtimeTuple);
const toolsLib = path.join(sdk, 'tools', 'lib');
for (const directory of [llvmLib, runtimeLib, toolsLib, spec.opensslLibDir]) {
  if (directory) await fs.access(directory);
}
const runtimeBinary = path.join(runtimeLib, spec.runtimeLibrary);
const runtimeSymbols = await $({stdio: 'pipe'})`nm -g ${runtimeBinary}`;
if (!runtimeSymbols.stdout.includes('g_cjLoadBadMask')) {
  throw new Error(`${runtimeBinary} does not export g_cjLoadBadMask; refusing an uncoloured target runtime`);
}
if (!(await fs.readFile(runtimeBinary)).includes('MRT_GCV2_')) {
  throw new Error(`${runtimeBinary} carries no MRT_GCV2_ markers; refusing a stock target runtime`);
}
const libraryPath = [llvmLib, runtimeLib, toolsLib, process.env[spec.loaderEnv] || ''].filter(Boolean).join(path.delimiter);
const envLines = [
  `CANGJIE_HOME=${sdk}`,
  `CANGJIE_STDX_PATH=${path.join(workspace, 'cangjie_stdx', 'target', spec.runtimeTuple, 'static', 'stdx')}`,
  `CJCJ_LLVM_SHIM_O=${shim}`,
  `CJCJ_SRCBUILD_RUNTIME_TUPLE=${spec.runtimeTuple}`,
  `CJCJ_SRCBUILD_LLVM_PLATFORM=${spec.llvmPlatform}`,
  `OPENSSL_PATH=${spec.opensslLibDir}`,
  'CJSTD_COLOURED=YES',
  'CJSTD_PREFLIGHT_C2=GREEN',
  `CJSTD_PROVENANCE_NOTE=source runtime exports g_cjLoadBadMask; bootstrap native hello passed before fixed tuple activation`,
  `${spec.loaderEnv}=${libraryPath}`,
];
if (spec.os === 'darwin') {
  const sdkRoot = (await $({stdio: 'pipe'})`xcrun --sdk macosx --show-sdk-path`).stdout.trim();
  if (!sdkRoot) throw new Error('xcrun returned an empty macOS SDK path');
  envLines.push(`SDKROOT=${sdkRoot}`);
  envLines.push(`DYLD_FALLBACK_LIBRARY_PATH=${libraryPath}`);
}
await fs.appendFile(githubEnv, `${envLines.join('\n')}\n`);
await fs.appendFile(githubPath, `${path.join(sdk, 'bin')}\n${path.join(sdk, 'tools', 'bin')}\n`);
console.log(`FIXED_LLVM_TUPLE_ACTIVATED target=${targetKey} platform=${manifest.PLATFORM} llvm=${manifest.LLVM_SHA} llc=${manifest.LLC_SHA256} opt=${manifest.OPT_SHA256} shim=${manifest.SHIM_SHA256}`);
