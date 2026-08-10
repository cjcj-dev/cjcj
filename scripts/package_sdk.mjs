#!/usr/bin/env zx
// Repackage an official SDK with the self-host compiler and optional patched runtime into a relocatable release archive.

import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {requirePrivateStage} from '../build/lib/package-safety.mjs';
import {
  installPythonBundle,
  RELEASE_PYTHON_SOURCE,
} from '../build/lib/python-bundle.mjs';
import {
  BASE_SDK_PROVENANCE,
  CJPM_PROVENANCE,
  verifyBaseSdkProvenance,
  verifyCjpmProvenance,
} from '../build/lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_PROVENANCE,
  verifyGateApparatusProvenance,
} from '../build/lib/release-gate-apparatus.mjs';
import {RELEASE_MANIFEST, writeReleaseManifest} from '../build/lib/release-manifest.mjs';
import {
  PACKAGED_LLVM_TOOL_NAMES,
  formatPackagedLlvmToolsManifest,
  parseLlvmToolsManifest,
  parsePackagedLlvmToolsManifest,
} from '../ci/llvm-tools-manifest.mjs';

const required = name => {
  const value = argv[name];
  if (!value || typeof value !== 'string') { console.error(`package_sdk.mjs: --${name} required`); process.exit(1); }
  return value;
};
const sdk = required('sdk');
const binary = required('binary');
const version = required('version');
const platform = required('platform');
const outdir = required('outdir');
const pythonBundle = required('python-bundle');
const runtimeLib = typeof argv['runtime-lib'] === 'string' ? argv['runtime-lib'] : '';
const runtimeRoot = typeof argv['runtime-root'] === 'string' ? argv['runtime-root'] : '';
const allowStockRuntime = argv['allow-stock-runtime'] === true;
const allowNightlyStd = argv['allow-nightly-std'] === true;
const stdDir = typeof argv['std-dir'] === 'string' ? argv['std-dir'] : '';
const llvmManifest = required('llvm-manifest');
const baseSdkId = typeof argv['base-sdk-id'] === 'string' ? argv['base-sdk-id'] : '';
const baseSdkArchive = required('base-sdk-archive');
const baseSdkProvenance = required('base-sdk-provenance');
const gateHostRuntime = required('gate-host-runtime');
const gateApparatusProvenance = required('gate-apparatus-provenance');
const cjcjSourceRepository = typeof argv['cjcj-source-repo'] === 'string' ? argv['cjcj-source-repo'] : '';
const cjcjSourceCommit = typeof argv['cjcj-source-sha'] === 'string' ? argv['cjcj-source-sha'] : '';
const runtimeSourceRepository = typeof argv['runtime-source-repo'] === 'string' ? argv['runtime-source-repo'] : '';
const runtimeSourceCommit = typeof argv['runtime-source-sha'] === 'string' ? argv['runtime-source-sha'] : '';
const llvmSourceRepository = typeof argv['llvm-source-repo'] === 'string' ? argv['llvm-source-repo'] : '';
const stdSourceRepository = typeof argv['std-source-repo'] === 'string' ? argv['std-source-repo'] : '';
const cjpmProvenance = required('cjpm-provenance');
const cjpmSourceRepository = required('cjpm-source-repo');
const cjpmSourceCommit = required('cjpm-source-sha');
async function exists(file, kind = 'file') {
  try { const stat = await fs.stat(file); return kind === 'dir' ? stat.isDirectory() : stat.isFile(); } catch { return false; }
}

if (!await exists(sdk, 'dir')) { console.error(`SDK dir not found: ${sdk}`); process.exit(2); }
if (!await exists(binary)) { console.error(`cjc binary not found: ${binary}`); process.exit(2); }
if (runtimeLib && !await exists(runtimeLib)) { console.error(`runtime library not found: ${runtimeLib}`); process.exit(2); }
if (runtimeRoot && !await exists(runtimeRoot, 'dir')) { console.error(`runtime root not found: ${runtimeRoot}`); process.exit(2); }
if (stdDir && !await exists(stdDir, 'dir')) { console.error(`std dir not found: ${stdDir}`); process.exit(2); }
if (!await exists(llvmManifest)) { console.error(`LLVM manifest not found: ${llvmManifest}`); process.exit(2); }
if (!await exists(baseSdkArchive)) { console.error(`base SDK archive not found: ${baseSdkArchive}`); process.exit(2); }
if (!await exists(baseSdkProvenance)) { console.error(`base SDK provenance not found: ${baseSdkProvenance}`); process.exit(2); }
if (!await exists(gateHostRuntime)) { console.error(`gate host runtime not found: ${gateHostRuntime}`); process.exit(2); }
if (!await exists(gateApparatusProvenance)) {
  console.error(`gate apparatus provenance not found: ${gateApparatusProvenance}`);
  process.exit(2);
}
if (!await exists(cjpmProvenance)) { console.error(`cjpm provenance not found: ${cjpmProvenance}`); process.exit(2); }
if (!await exists(pythonBundle, 'dir')) { console.error(`Python bundle dir not found: ${pythonBundle}`); process.exit(2); }

const platforms = {
  'linux-x64': ['linux_x86_64_cjnative', 'tar', ''],
  'linux-aarch64': ['linux_aarch64_cjnative', 'tar', ''],
  'darwin-arm64': ['darwin_aarch64_cjnative', 'tar', ''],
  'darwin-x64': ['darwin_x86_64_cjnative', 'tar', ''],
  'windows-x64': ['windows_x86_64_cjnative', 'zip', '.exe'],
};
if (!platforms[platform]) { console.error(`unsupported --platform: ${platform}`); process.exit(2); }
const [runtimeDir, archiveType, exeSuffix] = platforms[platform];
const runtimeLibrary = platform.startsWith('darwin-') ? 'libcangjie-runtime.dylib' : 'libcangjie-runtime.so';
const isWindows = platform === 'windows-x64';
const packageName = `cjcj-${version}-${platform}`;
const inputLlvmManifest = parseLlvmToolsManifest(await fs.readFile(llvmManifest, 'utf8'), {
  label: llvmManifest,
  schema: 'core-or-native',
});
if (inputLlvmManifest.schema !== 'core-lineage') {
  throw new Error(`release packaging requires core-lineage LLVM manifest, got ${inputLlvmManifest.schema}`);
}
const expectedTupleLldTool = platform.startsWith('darwin-') ? 'ld64.lld' : 'ld.lld';
if (inputLlvmManifest.values.get('LLD_TOOL') !== expectedTupleLldTool) {
  throw new Error(
    `release LLVM LLD tool mismatch: ${inputLlvmManifest.values.get('LLD_TOOL') || '<missing>'} != ${expectedTupleLldTool}`,
  );
}
const verifiedBaseSdkProvenance = await verifyBaseSdkProvenance({
  archive: baseSdkArchive,
  sidecar: baseSdkProvenance,
  platform,
  toolchain: baseSdkId,
});
await verifyGateApparatusProvenance({
  runtime: gateHostRuntime,
  sidecar: gateApparatusProvenance,
  platform,
  expectedToolchain: baseSdkId,
  expectedBaseSdkArchiveSha256: verifiedBaseSdkProvenance.artifact.sha256,
});
await verifyCjpmProvenance({
  binary: path.join(sdk, 'tools', 'bin', `cjpm${exeSuffix}`),
  sidecar: cjpmProvenance,
  platform,
  expectedRepository: cjpmSourceRepository,
  expectedCommit: cjpmSourceCommit,
});
const outputRoot = path.resolve(outdir);
if (outputRoot === path.parse(outputRoot).root) throw new Error('package output root must not be a filesystem root');
const stage = path.join(outputRoot, packageName);
await fs.mkdir(outputRoot, {recursive: true});
await fs.rm(stage, {recursive: true, force: true});

console.log(`[1/9] copy SDK tree -> ${stage}`);
const sdkSource = await fs.realpath(sdk);
if (isWindows) await fs.cp(sdkSource, stage, {recursive: true, dereference: true});
else {
  await $({stdio: 'inherit'})`cp -a ${sdkSource} ${stage}`;
  await $({stdio: 'inherit'})`chmod -R u+rwX,go+rX ${stage}`;
}
await fs.copyFile(baseSdkProvenance, path.join(stage, BASE_SDK_PROVENANCE));
await fs.copyFile(cjpmProvenance, path.join(stage, CJPM_PROVENANCE));
await fs.copyFile(gateApparatusProvenance, path.join(stage, GATE_APPARATUS_PROVENANCE));
await requirePrivateStage(stage, outputRoot, sdkSource);
await fs.rm(path.join(stage, '.cjv'), {recursive: true, force: true});

console.log('[2/9] install our compiler as bin/cjc');
const installed = path.join(stage, `bin/cjc${exeSuffix}`);
await Promise.all([
  fs.rm(path.join(stage, 'bin', 'cjc'), {force: true}),
  fs.rm(path.join(stage, 'bin', 'cjc.exe'), {force: true}),
]);
await fs.copyFile(binary, installed);
await fs.chmod(installed, 0o755);

console.log('[3/9] swap in patched runtime');
let packagedRuntime = '';
if (isWindows) {
  if (!runtimeRoot) { console.error('  ERROR: Windows packaging requires --runtime-root'); process.exit(3); }
  for (const relative of [path.join('runtime', 'lib', runtimeDir), path.join('lib', runtimeDir)]) {
    const source = path.join(runtimeRoot, relative);
    if (!await exists(source, 'dir')) { console.error(`  ERROR: ${source} missing from fork runtime install`); process.exit(3); }
    await fs.cp(source, path.join(stage, relative), {recursive: true, force: true});
    console.log(`  replaced ${relative} from ${source}`);
  }
  const runtimeFiles = await fs.readdir(path.join(stage, 'runtime', 'lib', runtimeDir));
  if (!runtimeFiles.some((name) => ['libcangjie-runtime.dll', 'cangjie-runtime.dll'].includes(name.toLowerCase()))) {
    console.error('  ERROR: fork libcangjie-runtime DLL missing from packaged runtime/lib');
    process.exit(3);
  }
  if (!runtimeFiles.some((name) => name.toLowerCase() === 'libboundscheck.dll')) {
    console.error('  ERROR: fork libboundscheck.dll missing from packaged runtime/lib');
    process.exit(3);
  }
} else if (runtimeLib) {
  const destination = path.join(stage, 'runtime', 'lib', runtimeDir, runtimeLibrary);
  if (!await exists(destination)) { console.error(`  ERROR: ${destination} missing in SDK tree`); process.exit(3); }
  await fs.copyFile(runtimeLib, destination);
  packagedRuntime = destination;
  console.log(`  replaced ${destination}`);
} else if (allowStockRuntime) {
  packagedRuntime = path.join(stage, 'runtime', 'lib', runtimeDir, runtimeLibrary);
  console.log('  skip: --allow-stock-runtime given; the package will carry the stock runtime');
} else {
  console.error('  ERROR: no --runtime-lib, so the package would carry the stock runtime. Two reasons that is wrong:');
  console.error('    1. Stock skips stack-root scanning whenever the main executable is named cjc');
  console.error('       (StackManager.cpp:588). Our bin/cjc is named cjc, so deep compiles corrupt the heap.');
  console.error('       The fork gates that exclusion on IsCangjieExecutable(); stock has no such gate.');
  console.error('    2. Stock has no generational GC, which is what this release ships.');
  console.error('  Pass --runtime-lib <libcangjie-runtime.so>, or --allow-stock-runtime if you mean it.');
  process.exit(3);
}

// Prove the packaged runtime is the fork rather than a stock library left in place: the fork's
// diagnostic switches (MRT_GCV2_*) sit in .rodata and are absent from stock (57 vs 0 on 0806).
// Copying a file proves an action ran, not that the right library arrived.
if (!allowStockRuntime) {
  const runtimeLibDir = path.join(stage, 'runtime', 'lib', runtimeDir);
  const names = isWindows
    ? (await fs.readdir(runtimeLibDir)).filter((name) => ['libcangjie-runtime.dll', 'cangjie-runtime.dll'].includes(name.toLowerCase()))
    : [runtimeLibrary];
  if (isWindows) {
    names.sort((left, right) => Number(right.toLowerCase() === 'libcangjie-runtime.dll') -
      Number(left.toLowerCase() === 'libcangjie-runtime.dll') || left.localeCompare(right));
    packagedRuntime = path.join(runtimeLibDir, names[0]);
  }
  for (const name of names) {
    const packaged = path.join(runtimeLibDir, name);
    if (!(await fs.readFile(packaged)).includes('MRT_GCV2_')) {
      console.error(`  ERROR: ${packaged} carries no MRT_GCV2_ markers, so it is not the fork runtime.`);
      process.exit(3);
    }
    console.log(`  verified fork runtime: ${name}`);
  }
}

// Overlay rebuilt std (.a/.cjo + lib/libcangjie-std-*.a). --std-dir may be:
//   (a) SDK root with modules/<tuple>/std + lib/<tuple>
//   (b) modules tree root containing <tuple>/std
//   (c) the std package dir itself (…/std with std.core.a …)
console.log('[4/9] overlay rebuilt std');
let stdProvenance = '';
if (stdDir) {
  const stdSource = await fs.realpath(stdDir);
  async function resolveStdLayout(root) {
    const candidates = [
      {
        modulesStd: path.join(root, 'modules', runtimeDir, 'std'),
        modulesTop: path.join(root, 'modules', runtimeDir),
        libDir: path.join(root, 'lib', runtimeDir),
        sharedDir: path.join(root, 'runtime', 'lib', runtimeDir),
      },
      {
        modulesStd: path.join(root, runtimeDir, 'std'),
        modulesTop: path.join(root, runtimeDir),
        libDir: path.join(root, '..', 'lib', runtimeDir),
        sharedDir: path.join(root, '..', 'runtime', 'lib', runtimeDir),
      },
      {
        modulesStd: root,
        modulesTop: path.dirname(root),
        libDir: path.join(root, '..', '..', '..', 'lib', runtimeDir),
        sharedDir: path.join(root, '..', '..', '..', 'runtime', 'lib', runtimeDir),
      },
    ];
    for (const candidate of candidates) {
      if (await exists(candidate.modulesStd, 'dir')) return candidate;
    }
    return null;
  }
  const layout = await resolveStdLayout(stdSource);
  if (!layout) {
    console.error(`  ERROR: --std-dir has no modules/<tuple>/std layout: ${stdSource}`);
    process.exit(3);
  }

  // Each release cell is bound to final-std-${platform}. Purge every std seed
  // inherited from the base SDK before installing that exact final root: even
  // the target tuple may contain extra paths or same-name files from nightly.
  // Preserve the non-std contents of every native and cross tuple.
  let prunedStdSeed = 0;
  const stageModules = path.join(stage, 'modules');
  if (await exists(stageModules, 'dir')) {
    for (const tuple of await fs.readdir(stageModules, {withFileTypes: true})) {
      if (!tuple.isDirectory()) continue;
      const tupleRoot = path.join(stageModules, tuple.name);
      const stdPackage = path.join(tupleRoot, 'std');
      if (await exists(stdPackage, 'dir')) {
        await fs.rm(stdPackage, {recursive: true, force: true});
        prunedStdSeed += 1;
      }
      for (const name of ['std.a', 'std.cjo', 'libstd.bc']) {
        const artifact = path.join(tupleRoot, name);
        if (!await exists(artifact)) continue;
        await fs.rm(artifact, {force: true});
        prunedStdSeed += 1;
      }
    }
  }
  for (const parent of [path.join(stage, 'lib'), path.join(stage, 'runtime', 'lib')]) {
    if (!await exists(parent, 'dir')) continue;
    for (const tuple of await fs.readdir(parent, {withFileTypes: true})) {
      if (!tuple.isDirectory()) continue;
      const tupleRoot = path.join(parent, tuple.name);
      for (const name of await fs.readdir(tupleRoot)) {
        if (!name.startsWith('libcangjie-std')) continue;
        await fs.rm(path.join(tupleRoot, name), {recursive: true, force: true});
        prunedStdSeed += 1;
      }
    }
  }
  console.log(`  pruned ${prunedStdSeed} base std seed path(s)`);

  const provenanceCandidates = [
    path.join(stdSource, 'PROVENANCE.txt'),
    path.join(stdSource, '..', 'PROVENANCE.txt'),
    path.join(stdSource, '..', '..', 'PROVENANCE.txt'),
    path.join(stdSource, '..', '..', '..', 'PROVENANCE.txt'),
  ];
  const sourceProvenance = (await Promise.all(provenanceCandidates.map(async file =>
    await exists(file) ? path.resolve(file) : ''))).find(Boolean) || '';
  if (sourceProvenance) {
    stdProvenance = path.join(stage, 'PROVENANCE.txt');
    await fs.copyFile(sourceProvenance, stdProvenance);
    console.log(`  PROVENANCE.txt <- ${sourceProvenance}`);
  } else {
    console.warn(`  WARNING: ${stdSource} has no PROVENANCE.txt; release manifest will record unavailable`);
  }
  const stageModulesStd = path.join(stage, 'modules', runtimeDir, 'std');
  const stageModulesTop = path.join(stage, 'modules', runtimeDir);
  const stageLib = path.join(stage, 'lib', runtimeDir);
  const stageShared = path.join(stage, 'runtime', 'lib', runtimeDir);
  await fs.mkdir(stageModulesStd, {recursive: true});
  await fs.mkdir(stageLib, {recursive: true});
  await fs.mkdir(stageShared, {recursive: true});

  const skipName = name => name === '.cached' || name.endsWith('-temp-files')
    || /\.O[01]\.a$/.test(name) || name === 'core.o';
  const entries = await fs.readdir(layout.modulesStd, {withFileTypes: true});
  let copiedA = 0;
  let copiedCjo = 0;
  let copiedBc = 0;
  for (const entry of entries) {
    if (!entry.isFile() || skipName(entry.name)) continue;
    if (!entry.name.endsWith('.a') && !entry.name.endsWith('.cjo') && !entry.name.endsWith('.bc')) continue;
    await fs.copyFile(path.join(layout.modulesStd, entry.name), path.join(stageModulesStd, entry.name));
    if (entry.name.endsWith('.a')) copiedA += 1;
    else if (entry.name.endsWith('.cjo')) copiedCjo += 1;
    else copiedBc += 1;
  }
  // package-level std.a / std.cjo (and optional libstd.bc) sit beside the std/ dir
  for (const topName of ['std.a', 'std.cjo', 'libstd.bc']) {
    const topSrc = path.join(layout.modulesTop, topName);
    if (await exists(topSrc)) {
      await fs.copyFile(topSrc, path.join(stageModulesTop, topName));
      console.log(`  modules/${runtimeDir}/${topName}`);
    }
  }
  // map std.X.a → lib/libcangjie-std-X.a (dots → hyphens after "std.")
  // prefer pre-built lib/ if present, else synthesize from modules
  let copiedLib = 0;
  const libSourceExists = await exists(layout.libDir, 'dir');
  if (libSourceExists) {
    const libEntries = await fs.readdir(layout.libDir);
    for (const name of libEntries) {
      if (!name.startsWith('libcangjie-std') || !name.endsWith('.a')) continue;
      if (/\.O[01]\.a$/.test(name)) continue;
      await fs.copyFile(path.join(layout.libDir, name), path.join(stageLib, name));
      copiedLib += 1;
    }
  }
  if (copiedLib === 0) {
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.startsWith('std.') || !entry.name.endsWith('.a')) continue;
      if (skipName(entry.name)) continue;
      const base = entry.name.slice(0, -2); // strip .a
      const rest = base.slice('std.'.length);
      const libname = `libcangjie-std-${rest.replaceAll('.', '-')}.a`;
      await fs.copyFile(path.join(layout.modulesStd, entry.name), path.join(stageLib, libname));
      copiedLib += 1;
    }
  }
  let copiedShared = 0;
  if (await exists(layout.sharedDir, 'dir')) {
    const sharedSuffix = isWindows ? '.dll' : platform.startsWith('darwin-') ? '.dylib' : '.so';
    for (const name of await fs.readdir(layout.sharedDir)) {
      if (!name.startsWith('libcangjie-std') || !name.endsWith(sharedSuffix)) continue;
      await fs.copyFile(path.join(layout.sharedDir, name), path.join(stageShared, name));
      copiedShared += 1;
    }
  }
  if (copiedA === 0 && copiedLib === 0) {
    console.error(`  ERROR: --std-dir produced neither module nor installed static std libraries`);
    process.exit(3);
  }
  const coreA = path.join(stageModulesStd, 'std.core.a');
  const coreLib = path.join(stageLib, 'libcangjie-std-core.a');
  if (!await exists(coreLib) || (copiedA > 0 && !await exists(coreA))) {
    console.error('  ERROR: overlay missing libcangjie-std-core.a or the core archive of a supplied module archive set');
    process.exit(3);
  }
  if (copiedShared === 0) {
    console.error(`  ERROR: --std-dir produced zero shared std libraries under ${layout.sharedDir}`);
    process.exit(3);
  }
  console.log(`  modules/${runtimeDir}/std: ${copiedA} .a + ${copiedCjo} .cjo + ${copiedBc} .bc`);
  console.log(`  lib/${runtimeDir}: ${copiedLib} libcangjie-std-*.a`);
  console.log(`  runtime/lib/${runtimeDir}: ${copiedShared} shared std libraries`);

  // Official CMake merges each package's FFI objects into the static lib
  // (AddCJNATIVELibrary.cmake: cangjie-std-core STATIC ${CORE_FFI_OBJECTS_LIST} + core.o,
  // and the same pattern for math/fs/time/…). Overlay of rebuilt CJ-only std.*.a
  // drops that merge, so static link of executables loses Int64.ti / typetemplate
  // and CJ_* FFI entry points. Re-merge from the sibling *FFI.a that the stock
  // SDK copy still carries — but only when stock's static already had native
  // members (ast has *FFI.a for the shared lib only; its STATIC is pure CJ).
  const stageLibEntries = await fs.readdir(stageLib);
  const ffiByStem = new Map();
  for (const name of stageLibEntries) {
    const match = name.match(/^libcangjie-std-(.+)FFI\.a$/);
    if (match) ffiByStem.set(match[1], name);
  }
  const archiveMembers = async (archivePath) => {
    const listed = await $({quiet: true})`ar t ${archivePath}`;
    return listed.stdout.split('\n').map((line) => line.trim()).filter(Boolean);
  };
  const isNativeObject = (member) => /\.(c|cc|cpp|S)\.o$/.test(member);
  let mergedLibs = 0;
  let mergeBytesDelta = 0;
  let coreBefore = 0;
  let coreAfter = 0;
  const mergeWork = await fs.mkdtemp(path.join(path.dirname(stage), 'std-ffi-merge-'));
  try {
    for (const name of stageLibEntries) {
      const match = name.match(/^libcangjie-std-(.+)\.a$/);
      if (!match || name.endsWith('FFI.a') || /\.O[01]\.a$/.test(name)) continue;
      const stem = match[1];
      const ffiName = ffiByStem.get(stem);
      if (!ffiName) continue;
      const staticPath = path.join(stageLib, name);
      const ffiPath = path.join(stageLib, ffiName);
      const members = await archiveMembers(staticPath);
      // After overlay the static is usually a single CJ .o; native members are
      // gone. Decide from the sibling FFI archive + official shape: merge iff
      // FFI has objects AND this is not a shared-only FFI package. Shared-only
      // is detected when the stock SDK (still present as *FFI.a) has a matching
      // static that, on the pre-overlay tree, was pure CJ — we re-check by
      // asking whether any official install merges this stem: native objects
      // live only in *FFI.a for those packages. Conservative signal used here:
      // merge when FFI members look like the core/math/fs family (always), and
      // skip when the rebuilt static already has native objects (no-op), and
      // skip stems whose stock static never absorbs FFI (ast).
      if (stem === 'ast') continue;
      if (members.some(isNativeObject)) continue;
      const before = (await fs.stat(staticPath)).size;
      if (stem === 'core') coreBefore = before;
      const work = path.join(mergeWork, stem);
      await fs.rm(work, {recursive: true, force: true});
      await fs.mkdir(work, {recursive: true});
      const ffiDir = path.join(work, 'ffi');
      const cjDir = path.join(work, 'cj');
      await fs.mkdir(ffiDir);
      await fs.mkdir(cjDir);
      await $({cwd: ffiDir, quiet: true})`ar x ${ffiPath}`;
      await $({cwd: cjDir, quiet: true})`ar x ${staticPath}`;
      const objects = [];
      for (const entry of await fs.readdir(ffiDir)) {
        if (entry.endsWith('.o')) objects.push(path.join(ffiDir, entry));
      }
      for (const entry of await fs.readdir(cjDir)) {
        if (entry.endsWith('.o')) objects.push(path.join(cjDir, entry));
      }
      if (objects.length === 0) {
        console.error(`  ERROR: empty merge inputs for ${name}`);
        process.exit(3);
      }
      const outTmp = path.join(work, name);
      await $({quiet: true})`ar rcs ${outTmp} ${objects}`;
      await fs.copyFile(outTmp, staticPath);
      const after = (await fs.stat(staticPath)).size;
      if (stem === 'core') coreAfter = after;
      mergedLibs += 1;
      mergeBytesDelta += after - before;
      if (stem === 'core') {
        const nm = await $({nothrow: true, quiet: true})`nm ${staticPath}`;
        if (!/(^|\n)[0-9a-fA-F]+ D Int64\.ti(\n|$)/.test(nm.stdout)) {
          console.error('  ERROR: merged libcangjie-std-core.a still lacks D Int64.ti');
          process.exit(3);
        }
      }
    }
  } finally {
    await fs.rm(mergeWork, {recursive: true, force: true});
  }
  console.log(`  merged FFI into ${mergedLibs} static lib(s); size Δ ${mergeBytesDelta} bytes` +
    (coreBefore ? ` (core ${coreBefore}→${coreAfter})` : ''));

  // Prove the overlaid std is ours, not nightly's copied back over itself: nightly's
  // String.indexOf reads this.myData as a raw base, with zero tag tests (measured 0806 --
  // 539 across the whole archive, 0 inside that function), which is the SIGSEGV this
  // release exists to fix. Read the function body, not the archive total.
  const barrierProbe = await $({nothrow: true, quiet: true})`objdump -drwC ${coreLib}`;
  const probeBody = barrierProbe.stdout.split('\n');
  const symbol = '_CNat6String7indexOfHRNatY0_E';
  let inBody = false;
  let tagTests = 0;
  let found = false;
  for (const line of probeBody) {
    if (line.includes(`<${symbol}>:`)) { inBody = true; found = true; continue; }
    if (inBody && (line.trim() === '' || (/^[0-9a-f]+ </.test(line) && !line.includes(symbol)))) inBody = false;
    // The tag test has two shapes. The older toolchain shifts the top 16 bits down
    // and compares against zero; since CJBarrierLowering.cpp:653-665 it loads
    // g_cjLoadBadMask and ands against it instead, so a std built with the current
    // compiler carries no shr at all. Accepting only the shr form would reject a
    // correctly built std, which is why both are counted here.
    if (inBody && (/shr +\$0x30/.test(line) || /g_cjLoadBadMask/.test(line))) tagTests += 1;
  }
  if (!found) {
    console.error(`  ERROR: ${symbol} absent from the overlaid ${path.basename(coreLib)}, so the`);
    console.error('  barrier check has no evidence either way. Not shippable -- absence of a');
    console.error('  symbol is not absence of the defect.');
    process.exit(3);
  }
  if (tagTests === 0) {
    console.error(`  ERROR: ${symbol} carries no tag test in the overlaid std, which is nightly's`);
    console.error('  signature. Under our runtime this.myData is a bit48-coloured pointer, so a');
    console.error('  bare read segfaults. Rebuild std with this release\'s compiler.');
    process.exit(3);
  }
  console.log(`  verified rebuilt std: ${symbol} has ${tagTests} tag tests`);
} else if (allowNightlyStd) {
  console.log('  skip: --allow-nightly-std given; the package will carry the nightly std');
} else {
  console.error('  ERROR: no --std-dir, so the package would carry the nightly std. That std\'s');
  console.error('  String.indexOf has no tag test before reading a bit48-coloured pointer, which');
  console.error('  segfaults under our runtime -- it is the reason this release rebuilds std at all.');
  console.error('  Pass --std-dir <rebuilt std>, or --allow-nightly-std if you mean it.');
  process.exit(3);
}

console.log('[5/9] bundle Python 3.11 for cjdb');
const packagedPython = await installPythonBundle({
  source: pythonBundle,
  stage,
  platform,
  runtimeDir,
});
console.log(`  Python ${packagedPython.version}: ${packagedPython.artifact}`);
console.log(`  cjdb launcher: ${packagedPython.launcher}`);
console.log(`  PSF license: ${packagedPython.license}`);

console.log('[6/9] set relative runtime lookup paths');
if (platform.startsWith('linux-')) {
  // cjc no longer carries $ORIGIN rpaths: the binary does not get to assume where it sits
  // relative to its SDK, and the nightly cjpm rejects $ORIGIN outright. envsetup.sh below is
  // what points at the three directories now, so the only thing left to assert here is that
  // nothing absolute leaked in -- a RUNPATH naming the build host would make the package work
  // on this machine and nowhere else, which is exactly the failure packaging must not ship.
  const dynamic = await $({nothrow: true, quiet: true})`readelf -d ${path.join(stage, 'bin/cjc')}`;
  const runpath = dynamic.stdout.split('\n').find(line => line.includes('RUNPATH'))?.match(/\[(.*)\]/)?.[1] || '';
  const entries = runpath.split(':').filter(Boolean);
  const hostPaths = entries.filter((entry) => entry.startsWith('/'));
  if (hostPaths.length > 0) {
    console.error(`  ERROR: bin/cjc RUNPATH carries build-host paths: ${hostPaths.join(', ')}`);
    console.error('  The link step owns this; fix packages/cjc/cjpm.toml link-option.');
    process.exit(3);
  }

  // Do not paper over a missing library here. Official cjc needs no rpath and no extra
  // LD_LIBRARY_PATH entry because it has no SDK-internal dynamic dependency at all: its ldd
  // lists only pthread/m/dl/stdc++/gcc_s/c, and the SDK ships no LLVM .a, so upstream links
  // LLVM statically at its own build time. Our self-hosted cjc links the shipped
  // libLLVM-15.so instead -- that difference is the thing to fix, and adding a search path
  // would only hide it. libcangjie-runtime.so is not part of the problem; the stock
  // envsetup.sh already covers runtime/lib.
  const dependencies = await $({nothrow: true, quiet: true})`ldd ${path.join(stage, 'bin/cjc')}`;
  const sdkInternal = dependencies.stdout.split('\n')
    .filter((line) => /libLLVM|not found/.test(line))
    .map((line) => line.trim());
  if (sdkInternal.length > 0) {
    console.error('  ERROR: bin/cjc has SDK-internal dynamic dependencies that official cjc does not:');
    for (const line of sdkInternal) console.error(`    ${line}`);
    console.error('  Official links LLVM statically; match that rather than adding a search path.');
    process.exit(3);
  }
  process.stdout.write(`  RUNPATH: ${runpath || '(none, as upstream)'}\n`);
} else if (platform.startsWith('darwin-')) {
  const available = await $({nothrow: true, quiet: true})`command -v install_name_tool`;
  if (available.exitCode !== 0) { console.error('  ERROR: install_name_tool not found'); process.exit(3); }
  const runtimeDestination = path.join(stage, 'runtime', 'lib', runtimeDir, runtimeLibrary);
  const relativeRuntime = `@rpath/${runtimeLibrary}`;
  await $({stdio: 'inherit'})`install_name_tool -id ${relativeRuntime} ${runtimeDestination}`;

  const linked = await $({stdio: 'pipe'})`otool -L ${installed}`;
  const runtimeDependency = linked.stdout.split('\n').slice(1)
    .map((line) => line.trim().split(/\s+\(/)[0])
    .find((dependency) => path.basename(dependency) === runtimeLibrary);
  if (!runtimeDependency) { console.error(`  ERROR: ${installed} has no ${runtimeLibrary} dependency`); process.exit(3); }
  if (runtimeDependency !== relativeRuntime) {
    await $({stdio: 'inherit'})`install_name_tool -change ${runtimeDependency} ${relativeRuntime} ${installed}`;
  }

  const loadCommands = await $({stdio: 'pipe'})`otool -l ${installed}`;
  const rpaths = [];
  const lines = loadCommands.stdout.split('\n');
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index].trim() !== 'cmd LC_RPATH') continue;
    const pathLine = lines.slice(index + 1, index + 5).find((line) => /^\s*path .* \(offset \d+\)$/.test(line));
    if (pathLine) rpaths.push(pathLine.trim().replace(/^path /, '').replace(/ \(offset \d+\)$/, ''));
  }
  const sdkRoot = `${path.resolve(sdk)}${path.sep}`;
  const obsoleteRpaths = [...new Set(rpaths.filter((rpath) =>
    rpath.startsWith(sdkRoot) || rpath.startsWith('@loader_path/../../runtime/')))];
  for (const rpath of obsoleteRpaths) {
    await $({stdio: 'inherit'})`install_name_tool -delete_rpath ${rpath} ${installed}`;
  }
  const relativeRpaths = [
    `@loader_path/../runtime/lib/${runtimeDir}`,
    '@loader_path/../third_party/llvm/lib',
    '@loader_path/../tools/lib',
  ];
  const retainedRpaths = new Set(rpaths.filter((rpath) => !obsoleteRpaths.includes(rpath)));
  for (const rpath of relativeRpaths) {
    if (!retainedRpaths.has(rpath)) await $({stdio: 'inherit'})`install_name_tool -add_rpath ${rpath} ${installed}`;
  }

  const envsetup = path.join(stage, 'envsetup.sh');
  await fs.appendFile(envsetup, [
    '',
    '# Prefer the packaged Darwin libraries when running the self-host compiler.',
    `export DYLD_LIBRARY_PATH="\${CANGJIE_HOME}/runtime/lib/${runtimeDir}:\${CANGJIE_HOME}/third_party/llvm/lib:\${CANGJIE_HOME}/tools/lib\${DYLD_LIBRARY_PATH:+:\${DYLD_LIBRARY_PATH}}"`,
    '',
  ].join('\n'));
  console.log(`  install name: ${relativeRuntime}`);
  console.log(`  rpaths: ${relativeRpaths.join(':')}`);
} else {
  console.log('  Windows resolves packaged DLLs through runtime/lib and PATH');
}

const sha256File = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
const llvmToolEnvironment = {...process.env};
const llvmLibraryPaths = [
  path.join(stage, 'third_party', 'llvm', 'lib'),
  path.join(stage, 'runtime', 'lib', runtimeDir),
  path.join(stage, 'tools', 'lib'),
  path.join(stage, 'python', 'lib'),
].filter(Boolean);
if (platform.startsWith('linux-')) {
  llvmToolEnvironment.LD_LIBRARY_PATH = [...llvmLibraryPaths, process.env.LD_LIBRARY_PATH || '']
    .filter(Boolean).join(path.delimiter);
} else if (platform.startsWith('darwin-')) {
  llvmToolEnvironment.DYLD_LIBRARY_PATH = [...llvmLibraryPaths, process.env.DYLD_LIBRARY_PATH || '']
    .filter(Boolean).join(path.delimiter);
} else {
  llvmToolEnvironment.PATH = [
    path.join(stage, 'third_party', 'llvm', 'bin'),
    ...llvmLibraryPaths,
    process.env.PATH || '',
  ].filter(Boolean).join(path.delimiter);
}

function runLineageProbe(command, args) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    env: llvmToolEnvironment,
    maxBuffer: 4 * 1024 * 1024,
  });
  const output = [result.stdout, result.stderr]
    .filter(value => typeof value === 'string' && value.trim())
    .join('\n').trim();
  return {status: result.status, error: result.error, output};
}

function oneLine(text) {
  return text.split(/\r?\n/).map(line => line.trim()).filter(Boolean).join(' | ').slice(0, 512);
}

function versionLine(executable) {
  const probe = runLineageProbe(executable, ['--version']);
  const lines = probe.output.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const preferred = lines.find(line => /(?:LLVM|LLD|lldb).*version|^LLD\b/i.test(line));
  const detail = oneLine(preferred || lines[0] || probe.error?.message || 'no output');
  if (probe.status === 0) return {version: detail, probe};
  return {version: `unavailable(exit=${probe.status ?? 'spawn'}): ${detail}`.slice(0, 512), probe};
}

const requiredLlvmTools = new Map([
  ['linux-x64', ['llc', 'opt', 'ld.lld', 'llvm-objcopy']],
  ['linux-aarch64', ['llc', 'opt', 'ld.lld', 'llvm-objcopy']],
  ['darwin-arm64', ['llc', 'opt', 'ld64.lld']],
  ['darwin-x64', ['llc', 'opt', 'ld64.lld']],
  ['windows-x64', ['llc', 'opt', 'ld.lld', 'llvm-ar']],
]);
const nativeFilePatterns = new Map([
  ['linux-x64', /ELF 64-bit.*(?:x86-64|x86_64)/i],
  ['linux-aarch64', /ELF 64-bit.*(?:ARM aarch64|aarch64)/i],
  ['darwin-arm64', /Mach-O 64-bit.*(?:arm64|aarch64)/i],
  ['darwin-x64', /Mach-O 64-bit.*x86_64/i],
  ['windows-x64', /PE32\+ executable.*x86-64/i],
]);

function verifyNativeLlvmTool(tool, executable) {
  const fileProbe = runLineageProbe('file', ['-b', executable]);
  if (fileProbe.status !== 0 || !nativeFilePatterns.get(platform).test(fileProbe.output)) {
    throw new Error(`${tool}: wrong native format for ${platform}: ${oneLine(fileProbe.output)}`);
  }
  let loaderProbe;
  if (platform.startsWith('linux-')) {
    loaderProbe = runLineageProbe('ldd', [executable]);
    const staticBinary = /not a dynamic executable|statically linked/i.test(loaderProbe.output);
    if ((!staticBinary && loaderProbe.status !== 0) || /not found/i.test(loaderProbe.output)) {
      throw new Error(`${tool}: loader check failed: ${oneLine(loaderProbe.output)}`);
    }
  } else if (platform.startsWith('darwin-')) {
    loaderProbe = runLineageProbe('otool', ['-L', executable]);
    if (loaderProbe.status !== 0) throw new Error(`${tool}: loader check failed: ${oneLine(loaderProbe.output)}`);
  } else {
    loaderProbe = runLineageProbe('objdump', ['-p', executable]);
    if (loaderProbe.status !== 0) throw new Error(`${tool}: loader check failed: ${oneLine(loaderProbe.output)}`);
  }
  const version = versionLine(executable);
  if (version.probe.status !== 0 || !version.version) {
    throw new Error(`${tool}: --version failed: ${oneLine(version.probe.output)}`);
  }
  return {file: oneLine(fileProbe.output), loader: oneLine(loaderProbe.output), version: version.version};
}

console.log('[7a/9] audit packaged LLVM tool lineage');
const llvmBinRelative = path.join('third_party', 'llvm', 'bin');
const packagedLlvmBin = path.join(stage, llvmBinRelative);
const baseLlvmBin = path.join(sdkSource, llvmBinRelative);
const physicalTools = new Map();
for (const entry of await fs.readdir(packagedLlvmBin, {withFileTypes: true})) {
  if (entry.isDirectory() || entry.name.toLowerCase().endsWith('.dll')) continue;
  const executable = path.join(packagedLlvmBin, entry.name);
  let stat;
  try { stat = await fs.stat(executable); } catch (error) {
    throw new Error(`broken packaged LLVM tool ${entry.name}: ${error.message}`);
  }
  if (!stat.isFile()) continue;
  const tool = entry.name.replace(/\.exe$/i, '');
  if (physicalTools.has(tool)) throw new Error(`duplicate packaged LLVM tool name after suffix normalization: ${tool}`);
  physicalTools.set(tool, entry.name);
}

const allToolNames = [...new Set([...PACKAGED_LLVM_TOOL_NAMES, ...physicalTools.keys()])]
  .sort((left, right) => left.localeCompare(right));
const tupleSha = inputLlvmManifest.values.get('LLVM_SHA');
const baseSdkSha256 = verifiedBaseSdkProvenance.artifact.sha256;
const tupleToolFields = new Map([
  ['llc', 'LLC'],
  ['opt', 'OPT'],
  [expectedTupleLldTool, 'LLD'],
]);
const lineageRows = [];
for (const tool of allToolNames) {
  const physical = physicalTools.get(tool);
  if (!physical) {
    lineageRows.push({tool, present: 'no', source: 'none', version: '-', sha256: '-'});
    continue;
  }
  const packagedTool = path.join(packagedLlvmBin, physical);
  const digest = await sha256File(packagedTool);
  let source;
  if (tupleToolFields.has(tool)) {
    const field = tupleToolFields.get(tool);
    const expected = inputLlvmManifest.values.get(`${field}_SHA256`);
    if (digest !== expected) {
      throw new Error(`${tool}: packaged sha256 ${digest} does not match tuple manifest ${expected || '<missing>'}`);
    }
    source = `tuple:${tupleSha}`;
  } else {
    const baseTool = path.join(baseLlvmBin, physical);
    if (!await exists(baseTool)) throw new Error(`${tool}: inherited tool is absent from base SDK: ${baseTool}`);
    const baseDigest = await sha256File(baseTool);
    if (digest !== baseDigest) {
      throw new Error(`${tool}: packaged sha256 ${digest} does not match base SDK ${baseDigest}`);
    }
    source = `base-sdk:${baseSdkSha256}`;
  }
  const version = versionLine(packagedTool);
  if (tupleToolFields.has(tool)) {
    const expectedVersion = inputLlvmManifest.values.get(`${tupleToolFields.get(tool)}_VERSION`);
    if (version.probe.status !== 0 || version.version !== expectedVersion) {
      throw new Error(`${tool}: packaged version ${version.version} does not match tuple manifest ${expectedVersion}`);
    }
  }
  lineageRows.push({tool, present: 'yes', source, version: version.version, sha256: digest});
}

for (const tool of requiredLlvmTools.get(platform)) {
  const physical = physicalTools.get(tool);
  if (!physical) throw new Error(`${tool}: required by ${platform} driver but absent from package`);
  const evidence = verifyNativeLlvmTool(tool, path.join(packagedLlvmBin, physical));
  console.log(`  ${tool}: file=${evidence.file}; version=${evidence.version}; loader=ok`);
}
const lldTool = expectedTupleLldTool;
const lldPhysical = physicalTools.get(lldTool);
if (lldPhysical) {
  const help = runLineageProbe(path.join(packagedLlvmBin, lldPhysical), ['--help']);
  const requiredOptions = platform.startsWith('darwin-')
    ? ['--visible-pkgs']
    : ['--export-bc', '--lto-newpm-passes', '--mllvm', '--visible-pkgs'];
  const missingOptions = requiredOptions.filter(option => !help.output.includes(option));
  if (help.status !== 0 || missingOptions.length) {
    throw new Error(`${lldTool}: missing Cangjie LTO capabilities: ${missingOptions.join(',') || oneLine(help.output)}`);
  }
  console.log(`  ${lldTool}: Cangjie LTO options=${requiredOptions.join(',')}`);
}

const packagedLlvmManifest = path.join(stage, 'llvm-tools.manifest');
await fs.writeFile(packagedLlvmManifest, formatPackagedLlvmToolsManifest({
  llvmSha: tupleSha,
  baseSdkSha256,
  tools: lineageRows,
}));
const recordedLineage = parsePackagedLlvmToolsManifest(await fs.readFile(packagedLlvmManifest, 'utf8'), {
  label: packagedLlvmManifest,
});
for (const row of recordedLineage.tools.filter(row => row.present === 'yes')) {
  const physical = physicalTools.get(row.tool);
  const actualSha = await sha256File(path.join(packagedLlvmBin, physical));
  const actualVersion = versionLine(path.join(packagedLlvmBin, physical)).version;
  if (row.sha256 !== actualSha || row.version !== actualVersion) {
    throw new Error(`${row.tool}: packaged manifest does not match final payload`);
  }
}
console.log(`LLVM_TOOL_LINEAGE_OK total=${lineageRows.length} present=${physicalTools.size} required=${requiredLlvmTools.get(platform).length}`);

console.log('[7b/9] write release provenance manifest');
const {destination: releaseManifest} = await writeReleaseManifest({
  stage,
  platform,
  exeSuffix,
  runtimeArtifact: packagedRuntime,
  stdProvenance,
  llvmManifest,
  baseSdkId,
  baseSdkProvenance: verifiedBaseSdkProvenance,
  gateApparatusArtifact: path.join(stage, GATE_APPARATUS_PROVENANCE),
  cjcjRepository: cjcjSourceRepository || undefined,
  cjcjCommit: cjcjSourceCommit,
  runtimeRepository: runtimeSourceRepository || undefined,
  runtimeCommit: runtimeSourceCommit,
  llvmRepository: llvmSourceRepository || undefined,
  stdRepository: stdSourceRepository,
  cjpmRepository: cjpmSourceRepository,
  cjpmCommit: cjpmSourceCommit,
  pythonArtifact: packagedPython.artifact,
  pythonMetadata: packagedPython.metadata,
  pythonMetadataArtifact: packagedPython.metadataArtifact,
  pythonRepository: RELEASE_PYTHON_SOURCE,
  pythonVersion: packagedPython.version,
});
const exportedManifest = path.join(outputRoot, `${packageName}.${RELEASE_MANIFEST}`);
await fs.copyFile(releaseManifest, exportedManifest);
console.log(`  archive: ${releaseManifest}`);
console.log(`  release metadata: ${exportedManifest}`);

console.log('[8/9] archive');
const archivePath = path.join(outdir, `${packageName}.${archiveType === 'tar' ? 'tar.gz' : 'zip'}`);
if (archiveType === 'tar') await $({stdio: 'inherit'})`tar -C ${outdir} -czf ${archivePath} ${packageName}`;
else {
  // Forward slashes: zx quotes argv for bash as $'…', where a backslash before
  // some letters is an ANSI-C escape — \c in "…\cjcj-…" swallowed the rest of
  // the path on release R4. PowerShell accepts forward-slash paths.
  const psQuote = value => `'${path.resolve(value).replaceAll('\\', '/').replaceAll("'", "''")}'`;
  const command = `Compress-Archive -LiteralPath ${psQuote(stage)} -DestinationPath ${psQuote(archivePath)} -Force`;
  await $({stdio: 'inherit'})`pwsh -NoLogo -NoProfile -Command ${command}`;
}

console.log('[9/9] sha256');
const archiveDigest = crypto.createHash('sha256').update(await fs.readFile(archivePath)).digest('hex');
const digest = `${archiveDigest}  ${path.basename(archivePath)}\n`;
await fs.writeFile(`${archivePath}.sha256`, digest);
console.log(`DONE: ${archivePath}`);
console.log(`SHA256: ${digest.replace(/\n+$/, '')}`);
