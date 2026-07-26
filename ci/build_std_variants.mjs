#!/usr/bin/env zx
// Build the flag-off and sticky std variants with the official C++ frontend.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  OPTIMIZED_STD_SUBDIR,
  STICKY_LLC_OPTION,
  compareStdCjos,
  copyCompiledStdLibraries,
  createStickySdkOverlay,
  stickyPreflight,
} from '../build/lib/std-variants.mjs';

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

const here = import.meta.dirname;
const platform = 'linux_x86_64_cjnative';
const officialCjcSha256 = process.env.CJCJ_OFFICIAL_CJC_SHA256
  || 'ed806687b1fa0228b84d18b72e01cdc174d75d140cf5f7dd6267598fb80cb509';
const pins = Object.fromEntries((await fs.readFile(path.join(here, 'runtime_pin.env'), 'utf8'))
  .split(/\r?\n/).filter(Boolean).map(line => line.split('=', 2)));
const sourceUrl = process.env.RUNTIME_SRC_URL || pins.RUNTIME_SRC_URL;
const sourceRef = process.env.RUNTIME_REF || pins.RUNTIME_REF;
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-std-variants-'));
const source = path.join(work, 'source');
const flagOffSdk = path.join(work, 'flag-off-sdk');
const stickySdk = path.join(work, 'sticky-sdk');
const flagOffCjo = path.join(work, 'flag-off-cjo');

async function requireFile(file, label) {
  if (!(await fs.stat(file).catch(() => null))?.isFile()) throw new Error(`${label} missing: ${file}`);
  return file;
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
}

async function createFlagOffSdkOverlay() {
  await fs.mkdir(flagOffSdk, {recursive: true});
  for (const name of ['bin', 'include', 'modules', 'runtime', 'tools']) {
    await fs.symlink(path.join(sdk, name), path.join(flagOffSdk, name), 'dir');
  }
  await fs.symlink(path.join(sdk, 'third_party'), path.join(flagOffSdk, 'third_party'), 'dir');

  const sdkLib = path.join(sdk, 'lib');
  const overlayLib = path.join(flagOffSdk, 'lib');
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

async function copyDirectoryContents(from, to) {
  await fs.mkdir(to, {recursive: true});
  for (const entry of await fs.readdir(from)) {
    await fs.cp(path.join(from, entry), path.join(to, entry), {recursive: true, force: true});
  }
}

try {
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

  await createFlagOffSdkOverlay();
  await runBuild(flagOffSdk, 'clean');
  const startedFlagOff = process.hrtime.bigint();
  await runBuild(flagOffSdk, 'build', '-t', 'release', `-j${jobs}`,
    `--target-lib=${path.join(flagOffSdk, 'runtime', 'lib', platform)}`);
  const flagOffSeconds = Number(process.hrtime.bigint() - startedFlagOff) / 1e9;
  await runBuild(flagOffSdk, 'install');

  const stdlib = path.join(source, 'stdlib');
  const buildOutput = path.join(stdlib, 'build', 'build');
  const installedOutput = path.join(stdlib, 'output');
  await fs.rm(out, {recursive: true, force: true});
  await copyDirectoryContents(installedOutput, out);
  const flagOffLibraries = copyCompiledStdLibraries(
    path.join(buildOutput, 'lib', platform), path.join(out, 'lib', platform));
  await fs.cp(path.join(installedOutput, 'modules', platform, 'std'), flagOffCjo, {recursive: true});

  createStickySdkOverlay(flagOffSdk, stickySdk);
  await runBuild(stickySdk, 'clean');
  const startedSticky = process.hrtime.bigint();
  await runBuild(stickySdk, 'build', '-t', 'release', `-j${jobs}`,
    `--target-lib=${path.join(flagOffSdk, 'runtime', 'lib', platform)}`);
  const stickySeconds = Number(process.hrtime.bigint() - startedSticky) / 1e9;

  const cjoResults = compareStdCjos(flagOffCjo, path.join(buildOutput, 'modules', platform, 'std'));
  const different = cjoResults.filter(result => !result.identical);
  if (different.length !== 0) {
    throw new Error(`sticky backend changed CJO bytes: ${different.map(result => result.name).join(', ')}`);
  }
  const stickyDirectory = path.join(out, 'lib', OPTIMIZED_STD_SUBDIR, platform);
  const stickyLibraries = copyCompiledStdLibraries(path.join(buildOutput, 'lib', platform), stickyDirectory);
  const preflight = stickyPreflight(stickyDirectory);

  const manifest = {
    recipe: 'official-cjc-plus-fixed-llc', sourceUrl, sourceRef, cjcSha256,
    cjo: {total: cjoResults.length, identical: cjoResults.length - different.length},
    flagOff: {...flagOffLibraries, seconds: flagOffSeconds},
    sticky: {...stickyLibraries, seconds: stickySeconds, preflight},
  };
  await fs.writeFile(path.join(out, 'STD_VARIANTS.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`STD_VARIANTS CJO=${manifest.cjo.identical}/${manifest.cjo.total} `
    + `STICKY_PREFLIGHT=${preflight.loggedBaseSymbols}/${preflight.stickyRelocations} `
    + `TIME=${flagOffSeconds.toFixed(2)}s+${stickySeconds.toFixed(2)}s`);
} finally {
  if (process.env.CJCJ_KEEP_STD_VARIANTS_WORK !== '1') {
    await fs.rm(work, {recursive: true, force: true});
  } else {
    console.log(`preserving std variant work directory: ${work}`);
  }
}
