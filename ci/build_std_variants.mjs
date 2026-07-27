#!/usr/bin/env zx
// Build the single sticky std closure with the official C++ frontend.

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
const sdk = path.resolve(sdkArgument || '.');
const out = path.resolve(outArgument || '.');
const jobs = String(argv.jobs || process.env.CJCJ_STD_BUILD_JOBS || '12');
if (!sdkArgument || !outArgument || sdk === path.parse(sdk).root || out === path.parse(out).root) {
  throw new Error('usage: build_std_variants.mjs --sdk <official-sdk> --outdir <bundle> [--jobs N]');
}
if (process.platform !== 'linux' || process.arch !== 'x64') {
  throw new Error(`sticky std variants are unsupported on ${process.platform}/${process.arch}`);
}

const platform = 'linux_x86_64_cjnative';
const officialCjcSha256 = process.env.CJCJ_OFFICIAL_CJC_SHA256
  || 'ed806687b1fa0228b84d18b72e01cdc174d75d140cf5f7dd6267598fb80cb509';
const {runtimeRef: sourceRef, sourceUrl, pinRef, overrideRef} = await resolveRuntimeSource();
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-sticky-std-'));
const source = path.join(work, 'source');
const buildSdk = path.join(work, 'build-sdk');
const stickySdk = path.join(work, 'sticky-sdk');

async function requireFile(file, label) {
  if (!(await fs.stat(file).catch(() => null))?.isFile()) throw new Error(`${label} missing: ${file}`);
  return file;
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
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

  const astFfi = await requireFile(path.join(sdkTargetLib, 'libcangjie-std-astFFI.a'), 'official ast FFI');
  const astSupport = path.join(overlayTargetLib, 'libcangjie-ast-support.a');
  await fs.copyFile(astFfi, astSupport);
  const llvmAr = await requireFile(path.join(sdk, 'third_party', 'llvm', 'bin', 'llvm-ar'), 'SDK llvm-ar');
  await $`${llvmAr} d ${astSupport} ast_api.cpp.o`;
  const members = (await $({stdio: 'pipe'})`${llvmAr} t ${astSupport}`).stdout.trim().split('\n').filter(Boolean);
  if (members.length !== 70 || members.includes('ast_api.cpp.o')) {
    throw new Error(`derived ast-support archive has unexpected members=${members.length}`);
  }
}

async function runBuild(home, ...args) {
  const libraryPath = [
    path.join(home, 'third_party', 'llvm', 'lib'),
    path.join(home, 'runtime', 'lib', platform),
    path.join(home, 'tools', 'lib'),
    process.env.LD_LIBRARY_PATH || '',
  ].filter(Boolean).join(path.delimiter);
  const buildEnv = {
    ...process.env,
    CANGJIE_HOME: home,
    PATH: [path.join(home, 'bin'), process.env.PATH || ''].filter(Boolean).join(path.delimiter),
    LD_LIBRARY_PATH: libraryPath,
  };
  await $({cwd: path.join(source, 'stdlib'), env: buildEnv})
    `python3 build.py ${args}`;
}

try {
  console.log(`[sticky-std] source ref=${sourceRef} pin=${pinRef} override=${overrideRef || '<none>'}`);
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
  await runBuild(stickySdk, 'clean');
  const startedSticky = process.hrtime.bigint();
  await runBuild(stickySdk, 'build', '-t', 'release', `-j${jobs}`,
    `--target-lib=${path.join(buildSdk, 'runtime', 'lib', platform)}`);
  const stickySeconds = Number(process.hrtime.bigint() - startedSticky) / 1e9;
  await runBuild(stickySdk, 'install');

  const stdlib = path.join(source, 'stdlib');
  const buildOutput = path.join(stdlib, 'build', 'build');
  const installedOutput = path.join(stdlib, 'output');
  await fs.rm(out, {recursive: true, force: true});
  const cjoDirectory = path.join(out, 'modules', platform, 'std');
  await fs.mkdir(path.dirname(cjoDirectory), {recursive: true});
  await fs.cp(path.join(installedOutput, 'modules', platform, 'std'), cjoDirectory, {recursive: true});
  const stickyDirectory = path.join(out, 'lib', platform);
  const stickyLibraries = copyCompiledStdLibraries(path.join(buildOutput, 'lib', platform), stickyDirectory);
  const preflight = stickyPreflight(stickyDirectory);
  const librarySha256 = Object.fromEntries(await Promise.all(stickyLibraries.files.map(async name =>
    [name, await sha256(path.join(stickyDirectory, name))])));
  const cjoFiles = (await fs.readdir(cjoDirectory)).filter(name => name.endsWith('.cjo')).sort();
  if (cjoFiles.length === 0) throw new Error('sticky std build produced no CJO files');
  const cjoSha256 = Object.fromEntries(await Promise.all(cjoFiles.map(async name =>
    [name, await sha256(path.join(cjoDirectory, name))])));

  const manifest = {
    recipe: 'official-cjc-plus-fixed-llc', closure: 'single-sticky', role: 'final',
    provenance: 'official-cjc-sticky-lowering', sourceUrl, sourceRef, cjcSha256,
    sticky: {...stickyLibraries, sha256: librarySha256, seconds: stickySeconds, preflight},
    cjo: {files: cjoFiles, sha256: cjoSha256},
  };
  await fs.writeFile(path.join(out, 'STICKY_STD.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`STICKY_STD LIBS=${stickyLibraries.files.length} `
    + `PREFLIGHT=${preflight.loggedBaseSymbols}/${preflight.stickyRelocations} `
    + `TIME=${stickySeconds.toFixed(2)}s`);
} finally {
  if (process.env.CJCJ_KEEP_STICKY_STD_WORK !== '1') {
    await fs.rm(work, {recursive: true, force: true});
  } else {
    console.log(`preserving std variant work directory: ${work}`);
  }
}
