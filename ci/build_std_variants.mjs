#!/usr/bin/env zx
// Build the single sticky std closure with the official C++ frontend.
// Host is always Linux x64. Target defaults to native linux_x86_64_cjnative;
// --target windows-x64 cross-builds with llvm-mingw and records managed DLLs.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  STICKY_LLC_OPTION,
  copyCompiledStdLibraries,
  createStickySdkOverlay,
  stickyPreflight,
} from '../build/lib/std-variants.mjs';
import {resolveRuntimeSource} from './runtime-pin.mjs';

$.stdio = 'inherit';

const sdkArgument = String(argv.sdk || process.env.CANGJIE_HOME || '');
const outArgument = String(argv.outdir || '');
const targetArgument = String(argv.target || process.env.CJCJ_STICKY_STD_TARGET || 'linux-x64');
const targetToolchain = String(argv['target-toolchain'] || process.env.RUNTIME_TOOLCHAIN || '');
const targetLibOverride = String(argv['target-lib'] || process.env.CJCJ_STICKY_TARGET_LIB || '');
const sdk = path.resolve(sdkArgument || '.');
const out = path.resolve(outArgument || '.');
const jobs = String(argv.jobs || process.env.CJCJ_STD_BUILD_JOBS || '12');
if (!sdkArgument || !outArgument || sdk === path.parse(sdk).root || out === path.parse(out).root) {
  throw new Error('usage: build_std_variants.mjs --sdk <official-sdk> --outdir <bundle> [--target linux-x64|windows-x64] [--target-toolchain <mingw>] [--jobs N]');
}
if (process.platform !== 'linux' || process.arch !== 'x64') {
  throw new Error(`sticky std variants are unsupported on ${process.platform}/${process.arch}`);
}

const TARGETS = {
  'linux-x64': {
    platform: 'linux_x86_64_cjnative',
    buildTarget: null,
    checklist: 'sticky_native_members_linux_x86_64.json',
    libraryPattern: /^libcangjie-std(?:[-.].*)?\.(?:a|so)$/,
    managedPattern: null,
    needsToolchain: false,
  },
  'windows-x64': {
    platform: 'windows_x86_64_cjnative',
    buildTarget: 'windows-x86_64',
    checklist: 'sticky_native_members_windows_x86_64.json',
    libraryPattern: /^libcangjie-std(?:[-.].*)?\.a$/,
    managedPattern: /^libcangjie-std(?:[-.].*)?\.dll$/,
    needsToolchain: true,
  },
};
const targetSpec = TARGETS[targetArgument];
if (!targetSpec) {
  throw new Error(`unsupported sticky std target: ${targetArgument} (allowed: ${Object.keys(TARGETS).join(', ')})`);
}
if (targetSpec.needsToolchain && !targetToolchain) {
  throw new Error(`sticky std target ${targetArgument} requires --target-toolchain / RUNTIME_TOOLCHAIN`);
}
const platform = targetSpec.platform;
const officialCjcSha256 = process.env.CJCJ_OFFICIAL_CJC_SHA256
  || 'ed806687b1fa0228b84d18b72e01cdc174d75d140cf5f7dd6267598fb80cb509';
const {runtimeRef: sourceRef, sourceUrl, pinRef, overrideRef} = await resolveRuntimeSource();
const nativeChecklistPath = path.resolve(
  import.meta.dirname, '..', 'tools', targetSpec.checklist);
const nativeChecklist = JSON.parse(await fs.readFile(nativeChecklistPath, 'utf8'));
if (nativeChecklist.sourceRef !== sourceRef || nativeChecklist.platform !== platform) {
  throw new Error(`native std member checklist does not cover ${sourceRef}/${platform}`);
}
const nativeMembers = nativeChecklist.nativeMembers;
if (!nativeMembers || Array.isArray(nativeMembers) || typeof nativeMembers !== 'object') {
  throw new Error(`invalid native std member checklist: ${nativeChecklistPath}`);
}
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-sticky-std-'));
const source = path.join(work, 'source');
const buildSdk = path.join(work, 'build-sdk');
const stickySdk = path.join(work, 'sticky-sdk');

async function requireFile(file, label) {
  if (!(await fs.stat(file).catch(() => null))?.isFile()) throw new Error(`${label} missing: ${file}`);
  return file;
}

async function requireDirectory(directory, label) {
  if (!(await fs.stat(directory).catch(() => null))?.isDirectory()) {
    throw new Error(`${label} missing: ${directory}`);
  }
  return directory;
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
}

async function matchingFiles(directory, pattern) {
  if (!(await fs.stat(directory).catch(() => null))?.isDirectory()) return [];
  return (await fs.readdir(directory)).filter(name => pattern.test(name)).sort();
}

async function createBuildSdkOverlay() {
  await fs.mkdir(buildSdk, {recursive: true});
  for (const name of ['bin', 'include', 'modules', 'runtime', 'tools']) {
    await fs.symlink(path.join(sdk, name), path.join(buildSdk, name), 'dir');
  }
  await fs.symlink(path.join(sdk, 'third_party'), path.join(buildSdk, 'third_party'), 'dir');

  const sdkLib = path.join(sdk, 'lib');
  const overlayLib = path.join(buildSdk, 'lib');
  const sdkTargetLib = path.join(sdkLib, platform);
  const overlayTargetLib = path.join(overlayLib, platform);
  await requireDirectory(sdkTargetLib, `SDK target lib ${platform}`);
  await fs.mkdir(overlayTargetLib, {recursive: true});
  for (const entry of await fs.readdir(sdkLib, {withFileTypes: true})) {
    if (entry.name === platform) continue;
    await fs.symlink(path.join(sdkLib, entry.name), path.join(overlayLib, entry.name),
      entry.isDirectory() ? 'dir' : 'file');
  }
  for (const entry of await fs.readdir(sdkTargetLib, {withFileTypes: true})) {
    if (entry.name === 'libcangjie-ast-support.a') continue;
    await fs.symlink(path.join(sdkTargetLib, entry.name), path.join(overlayTargetLib, entry.name),
      entry.isDirectory() ? 'dir' : 'file');
  }

  const astSupport = path.join(overlayTargetLib, 'libcangjie-ast-support.a');
  const officialAstSupport = path.join(sdkTargetLib, 'libcangjie-ast-support.a');
  // Linux sticky recipe derives ast-support from std-astFFI by dropping ast_api.cpp.o
  // (exactly 70 members). Windows official SDK already ships the support archive;
  // its FFI archive has a different member set, so reuse the official object.
  if (targetSpec.buildTarget) {
    await fs.copyFile(await requireFile(officialAstSupport, 'official windows ast-support'), astSupport);
  } else {
    if (await fs.stat(officialAstSupport).catch(() => null)) {
      // still derive for linux so sticky builds match the historical recipe
    }
    const astFfi = await requireFile(path.join(sdkTargetLib, 'libcangjie-std-astFFI.a'), 'official ast FFI');
    await fs.copyFile(astFfi, astSupport);
    const llvmAr = await requireFile(path.join(sdk, 'third_party', 'llvm', 'bin', 'llvm-ar'), 'SDK llvm-ar');
    await $`${llvmAr} d ${astSupport} ast_api.cpp.o`;
    const members = (await $({stdio: 'pipe'})`${llvmAr} t ${astSupport}`).stdout.trim().split('\n').filter(Boolean);
    if (members.length !== 70 || members.includes('ast_api.cpp.o')) {
      throw new Error(`derived ast-support archive has unexpected members=${members.length}`);
    }
  }
}

async function runBuild(home, ...args) {
  const libraryPath = [
    path.join(home, 'third_party', 'llvm', 'lib'),
    path.join(home, 'runtime', 'lib', platform),
    path.join(home, 'tools', 'lib'),
    process.env.LD_LIBRARY_PATH || '',
  ].filter(Boolean).join(path.delimiter);
  const pathEntries = [path.join(home, 'bin')];
  if (targetToolchain) pathEntries.push(path.join(targetToolchain, 'bin'));
  pathEntries.push(process.env.PATH || '');
  const buildEnv = {
    ...process.env,
    CANGJIE_HOME: home,
    PATH: pathEntries.filter(Boolean).join(path.delimiter),
    LD_LIBRARY_PATH: libraryPath,
  };
  if (targetToolchain) buildEnv.RUNTIME_TOOLCHAIN = targetToolchain;
  await $({cwd: path.join(source, 'stdlib'), env: buildEnv})
    `python3 build.py ${args}`;
}

try {
  console.log(`[sticky-std] target=${targetArgument} platform=${platform} source ref=${sourceRef} pin=${pinRef} override=${overrideRef || '<none>'}`);
  const cjc = await requireFile(path.join(sdk, 'bin', 'cjc'), 'official cjc');
  const cjcSha256 = await sha256(cjc);
  if (cjcSha256 !== officialCjcSha256) {
    throw new Error(`official cjc SHA-256 mismatch: expected ${officialCjcSha256}, got ${cjcSha256}`);
  }
  const llc = await requireFile(path.join(sdk, 'third_party', 'llvm', 'bin', 'llc'), 'fixed llc');
  const llcHelp = await $({stdio: 'pipe'})`${llc} --help-hidden`;
  if (!llcHelp.stdout.includes(STICKY_LLC_OPTION)) {
    throw new Error(`fixed llc does not support ${STICKY_LLC_OPTION}`);
  }

  await $`git -C ${work} init -q source`;
  await $`git -C ${source} remote add origin ${sourceUrl}`;
  await $`git -C ${source} fetch --depth 1 origin ${sourceRef}`;
  await $`git -C ${source} checkout -q FETCH_HEAD`;
  const actualRef = (await $({stdio: 'pipe'})`git -C ${source} rev-parse HEAD`).stdout.trim();
  if (actualRef !== sourceRef) throw new Error(`runtime source mismatch: expected ${sourceRef}, got ${actualRef}`);

  await createBuildSdkOverlay();
  createStickySdkOverlay(buildSdk, stickySdk);

  const targetLib = targetLibOverride
    || path.join(buildSdk, 'runtime', 'lib', platform);
  await requireDirectory(targetLib, 'sticky std target-lib');

  const buildArgs = ['build', '-t', 'release', `-j${jobs}`, `--target-lib=${targetLib}`];
  if (targetSpec.buildTarget) {
    buildArgs.push(`--target=${targetSpec.buildTarget}`, `--target-toolchain=${targetToolchain}`);
  }
  await runBuild(stickySdk, 'clean');
  const startedSticky = process.hrtime.bigint();
  await runBuild(stickySdk, ...buildArgs);
  const stickySeconds = Number(process.hrtime.bigint() - startedSticky) / 1e9;
  await runBuild(stickySdk, 'install');

  const stdlib = path.join(source, 'stdlib');
  const buildOutput = targetSpec.buildTarget
    ? path.join(stdlib, 'build', `build-libs-x86_64-w64-mingw32`)
    : path.join(stdlib, 'build', 'build');
  const installedOutput = path.join(stdlib, 'output');
  await fs.rm(out, {recursive: true, force: true});
  const cjoDirectory = path.join(out, 'modules', platform, 'std');
  await fs.mkdir(path.dirname(cjoDirectory), {recursive: true});
  await fs.cp(path.join(installedOutput, 'modules', platform, 'std'), cjoDirectory, {recursive: true});
  const stickyDirectory = path.join(out, 'lib', platform);
  const compiledLibDir = targetSpec.buildTarget
    ? path.join(buildOutput, 'lib')
    : path.join(buildOutput, 'lib', platform);
  // Windows cross puts .a under build/lib/ and DLLs under build/lib/windows_.../
  const stickySourceDir = targetSpec.buildTarget
    ? path.join(buildOutput, 'lib')
    : path.join(buildOutput, 'lib', platform);
  await fs.mkdir(stickyDirectory, {recursive: true});
  const stickyNames = await matchingFiles(stickySourceDir, targetSpec.libraryPattern);
  if (stickyNames.length === 0) {
    // native linux layout nests platform; windows layout may place .a in lib/
    const nested = path.join(buildOutput, 'lib', platform);
    const nestedNames = await matchingFiles(nested, targetSpec.libraryPattern);
    if (nestedNames.length === 0) throw new Error(`no compiled sticky std libraries under ${stickySourceDir} or ${nested}`);
    for (const name of nestedNames) {
      await fs.copyFile(path.join(nested, name), path.join(stickyDirectory, name));
    }
  } else {
    for (const name of stickyNames) {
      await fs.copyFile(path.join(stickySourceDir, name), path.join(stickyDirectory, name));
    }
  }
  const stickyLibraries = {
    files: (await matchingFiles(stickyDirectory, targetSpec.libraryPattern)),
    bytes: 0,
  };
  stickyLibraries.bytes = (await Promise.all(stickyLibraries.files.map(async name =>
    (await fs.stat(path.join(stickyDirectory, name))).size))).reduce((a, b) => a + b, 0);
  if (stickyLibraries.files.length === 0) throw new Error(`no sticky std libraries staged under ${stickyDirectory}`);

  let preflight = null;
  if (!targetSpec.managedPattern) {
    preflight = stickyPreflight(stickyDirectory);
  }

  const managedFiles = [];
  const managedHashes = {};
  if (targetSpec.managedPattern) {
    const managedSource = path.join(buildOutput, 'lib', platform);
    const managedOut = path.join(out, 'runtime', 'lib', platform);
    await fs.mkdir(managedOut, {recursive: true});
    const dllNames = await matchingFiles(managedSource, targetSpec.managedPattern);
    if (dllNames.length === 0) throw new Error(`no managed Windows std DLLs under ${managedSource}`);
    for (const name of dllNames) {
      const relative = path.join('runtime', 'lib', platform, name);
      await fs.copyFile(path.join(managedSource, name), path.join(managedOut, name));
      managedFiles.push(relative);
      managedHashes[relative] = await sha256(path.join(managedOut, name));
    }
    managedFiles.sort();
  }

  const nativeLibraries = stickyLibraries.files.filter(name => name.endsWith('FFI.a'));
  const librarySha256 = Object.fromEntries(await Promise.all(stickyLibraries.files.map(async name =>
    [name, await sha256(path.join(stickyDirectory, name))])));
  const cjoFiles = (await fs.readdir(cjoDirectory)).filter(name => name.endsWith('.cjo')).sort();
  if (cjoFiles.length === 0) throw new Error('sticky std build produced no CJO files');
  const cjoSha256 = Object.fromEntries(await Promise.all(cjoFiles.map(async name =>
    [name, await sha256(path.join(cjoDirectory, name))])));

  const manifest = {
    recipe: 'official-cjc-plus-fixed-llc', closure: 'single-sticky', role: 'final',
    provenance: 'official-cjc-sticky-lowering', sourceUrl, sourceRef, cjcSha256,
    nativeLibraries, nativeMembers,
    sticky: {...stickyLibraries, sha256: librarySha256, seconds: stickySeconds, ...(preflight ? {preflight} : {})},
    cjo: {files: cjoFiles, sha256: cjoSha256},
  };
  if (managedFiles.length !== 0) {
    manifest.managed = {files: managedFiles, sha256: managedHashes};
  }
  await fs.writeFile(path.join(out, 'STICKY_STD.json'), `${JSON.stringify(manifest, null, 2)}\n`);

  const checker = path.resolve(import.meta.dirname, '..', 'tools', 'check_sticky_closure.py');
  await $({stdio: 'inherit'})`python3 ${checker} --manifest ${path.join(out, 'STICKY_STD.json')} --sdk ${out} --platform ${platform}`;

  const managedNote = managedFiles.length ? ` managed=${managedFiles.length}` : '';
  const preflightNote = preflight
    ? ` PREFLIGHT=${preflight.loggedBaseSymbols}/${preflight.stickyRelocations}`
    : '';
  console.log(`STICKY_STD target=${targetArgument} LIBS=${stickyLibraries.files.length} CJO=${cjoFiles.length}`
    + `${managedNote}${preflightNote} TIME=${stickySeconds.toFixed(2)}s`);
} finally {
  if (process.env.CJCJ_KEEP_STICKY_STD_WORK !== '1') {
    await fs.rm(work, {recursive: true, force: true});
  } else {
    console.log(`preserving std variant work directory: ${work}`);
  }
}
