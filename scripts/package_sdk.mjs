#!/usr/bin/env zx
// Repackage an official SDK with the self-host compiler and optional patched runtime into a relocatable release archive.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {stickyPreflight} from '../build/lib/std-variants.mjs';

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
const runtimeLib = typeof argv['runtime-lib'] === 'string' ? argv['runtime-lib'] : '';
const runtimeRoot = typeof argv['runtime-root'] === 'string' ? argv['runtime-root'] : '';
const stickyStd = typeof argv['sticky-std'] === 'string' ? argv['sticky-std'] : '';

async function exists(file, kind = 'file') {
  try { const stat = await fs.stat(file); return kind === 'dir' ? stat.isDirectory() : stat.isFile(); } catch { return false; }
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
}

async function matchingFiles(directory, pattern) {
  if (!await exists(directory, 'dir')) return [];
  return (await fs.readdir(directory)).filter(name => pattern.test(name)).sort();
}

function requireSameFiles(label, actual, expected) {
  if (actual.join('\n') !== expected.join('\n')) {
    throw new Error(`${label} file set mismatch: actual=${actual.join(',')} expected=${expected.join(',')}`);
  }
}
if (!await exists(sdk, 'dir')) { console.error(`SDK dir not found: ${sdk}`); process.exit(2); }
if (!await exists(binary)) { console.error(`cjc binary not found: ${binary}`); process.exit(2); }
if (runtimeLib && !await exists(runtimeLib)) { console.error(`runtime library not found: ${runtimeLib}`); process.exit(2); }
if (runtimeRoot && !await exists(runtimeRoot, 'dir')) { console.error(`runtime root not found: ${runtimeRoot}`); process.exit(2); }

const platforms = {
  'linux-x64': ['linux_x86_64_cjnative', 'tar', ''],
  'linux-aarch64': ['linux_aarch64_cjnative', 'tar', ''],
  'darwin-arm64': ['darwin_aarch64_cjnative', 'tar', ''],
  'darwin-x64': ['darwin_x86_64_cjnative', 'tar', ''],
  'windows-x64': ['windows_x86_64_cjnative', 'zip', '.exe'],
};
if (!platforms[platform]) { console.error(`unsupported --platform: ${platform}`); process.exit(2); }
const [runtimeDir, archiveType, exeSuffix] = platforms[platform];
if (platform === 'linux-x64' && !stickyStd) {
  console.error('Linux x64 packaging requires --sticky-std');
  process.exit(2);
}
if (stickyStd && !await exists(stickyStd, 'dir')) {
  console.error(`sticky std directory not found: ${stickyStd}`);
  process.exit(2);
}
const runtimeLibrary = platform.startsWith('darwin-') ? 'libcangjie-runtime.dylib' : 'libcangjie-runtime.so';
const isWindows = platform === 'windows-x64';
const packageName = `cjcj-${version}-${platform}`;
const stage = path.join(outdir, packageName);
await fs.mkdir(outdir, {recursive: true});
await fs.rm(stage, {recursive: true, force: true});

console.log(`[1/7] copy SDK tree -> ${stage}`);
if (isWindows) await fs.cp(sdk, stage, {recursive: true});
else {
  await $({stdio: 'inherit'})`cp -a ${sdk} ${stage}`;
  await $({stdio: 'inherit'})`chmod -R u+rwX,go+rX ${stage}`;
}
await fs.rm(path.join(stage, '.cjv'), {recursive: true, force: true});

console.log('[2/7] install the single sticky std closure');
if (stickyStd) {
  const stickyManifestPath = path.join(stickyStd, 'STICKY_STD.json');
  if (!await exists(stickyManifestPath)) throw new Error(`sticky std manifest missing: ${stickyManifestPath}`);
  const stickyManifest = JSON.parse(await fs.readFile(stickyManifestPath, 'utf8'));
  if (stickyManifest.closure !== 'single-sticky' || stickyManifest.role !== 'final' ||
      stickyManifest.provenance !== 'official-cjc-sticky-lowering') {
    throw new Error(`sticky std manifest role mismatch: closure=${stickyManifest.closure || '<missing>'} `
      + `role=${stickyManifest.role || '<missing>'} provenance=${stickyManifest.provenance || '<missing>'}`);
  }
  const runtimeSourceSha = path.join(path.dirname(runtimeLib), 'SOURCE_SHA');
  if (!runtimeLib || !await exists(runtimeSourceSha)) {
    throw new Error('Linux x64 sticky packaging requires runtime-lib with adjacent SOURCE_SHA');
  }
  const runtimeRef = (await fs.readFile(runtimeSourceSha, 'utf8')).trim();
  if (runtimeRef !== stickyManifest.sourceRef) {
    throw new Error(`runtime/std source mismatch: runtime=${runtimeRef} std=${stickyManifest.sourceRef}`);
  }

  const optimizedLibraries = path.join(stage, 'lib', 'cjcj-optimization', runtimeDir);
  const standardLibraries = path.join(stage, 'lib', runtimeDir);
  const runtimeLibraries = path.join(stage, 'runtime', 'lib', runtimeDir);
  const stdModules = path.join(stage, 'modules', runtimeDir, 'std');
  const libraryPattern = /^libcangjie-std.*\.(?:a|so|dylib)$/;
  const seedArtifacts = [];
  for (const directory of [standardLibraries, runtimeLibraries, optimizedLibraries]) {
    for (const name of await matchingFiles(directory, libraryPattern)) {
      const file = path.join(directory, name);
      seedArtifacts.push({file: path.relative(stage, file), sha256: await sha256(file)});
    }
  }
  for (const name of await matchingFiles(stdModules, /\.cjo$/)) {
    const file = path.join(stdModules, name);
    seedArtifacts.push({file: path.relative(stage, file), sha256: await sha256(file)});
  }

  await fs.rm(path.join(stage, 'lib', 'cjcj-optimization'), {recursive: true, force: true});
  for (const directory of [standardLibraries, runtimeLibraries]) {
    for (const name of await matchingFiles(directory, libraryPattern)) {
      await fs.rm(path.join(directory, name), {force: true});
    }
  }
  await fs.rm(stdModules, {recursive: true, force: true});
  await fs.cp(stickyStd, stage, {recursive: true, force: true});
  const finalLibraries = [...stickyManifest.sticky.files].sort();
  const finalSharedLibraries = finalLibraries.filter(name => name.endsWith('.so'));
  const finalCjos = [...stickyManifest.cjo.files].sort();
  for (const name of finalSharedLibraries) {
      await fs.copyFile(path.join(standardLibraries, name), path.join(runtimeLibraries, name));
  }

  requireSameFiles('packaged std libraries', await matchingFiles(standardLibraries, libraryPattern), finalLibraries);
  requireSameFiles('packaged runtime std libraries',
    await matchingFiles(runtimeLibraries, libraryPattern), finalSharedLibraries);
  requireSameFiles('packaged std CJO', await matchingFiles(stdModules, /\.cjo$/), finalCjos);
  const shippedHashes = [];
  for (const name of finalLibraries) {
    const digest = await sha256(path.join(standardLibraries, name));
    if (digest !== stickyManifest.sticky.sha256[name]) {
      throw new Error(`packaged std SHA mismatch: ${name} ${digest} != ${stickyManifest.sticky.sha256[name]}`);
    }
    shippedHashes.push(digest);
  }
  for (const name of finalSharedLibraries) {
    const digest = await sha256(path.join(runtimeLibraries, name));
    if (digest !== stickyManifest.sticky.sha256[name]) {
      throw new Error(`packaged runtime std SHA mismatch: ${name}`);
    }
    shippedHashes.push(digest);
  }
  for (const name of finalCjos) {
    const digest = await sha256(path.join(stdModules, name));
    if (digest !== stickyManifest.cjo.sha256[name]) {
      throw new Error(`packaged std CJO SHA mismatch: ${name}`);
    }
    shippedHashes.push(digest);
  }
  const finalHashes = new Set([
    ...Object.values(stickyManifest.sticky.sha256), ...Object.values(stickyManifest.cjo.sha256),
  ]);
  const seedOnlyHashes = new Set(seedArtifacts.map(item => item.sha256).filter(hash => !finalHashes.has(hash)));
  const seedShaResiduals = shippedHashes.filter(hash => seedOnlyHashes.has(hash));
  if (seedShaResiduals.length !== 0) {
    throw new Error(`stock SDK std seed SHA survived purge: ${seedShaResiduals.join(',')}`);
  }
  const libPreflight = stickyPreflight(standardLibraries);
  const runtimePreflight = stickyPreflight(runtimeLibraries);
  console.log(`  sticky std: lib=${libPreflight.loggedBaseSymbols}/${libPreflight.stickyRelocations} `
    + `runtime=${runtimePreflight.loggedBaseSymbols}/${runtimePreflight.stickyRelocations}`);
  console.log(`  stock SDK std seed: artifacts=${seedArtifacts.length} unique_sha=${seedOnlyHashes.size} residual=0`);
  await fs.writeFile(path.join(stage, 'CJCJ_RELEASE.json'), `${JSON.stringify({
    runtimeRef,
    stickyStd: {
      closure: stickyManifest.closure,
      role: stickyManifest.role,
      provenance: stickyManifest.provenance,
      cjcSha256: stickyManifest.cjcSha256,
      libraries: finalLibraries.length,
      cjos: finalCjos.length,
    },
    stockSdkStdSeed: {artifactsPurged: seedArtifacts.length, uniqueSha256: seedOnlyHashes.size, residual: 0},
  }, null, 2)}\n`);
} else {
  console.log('  skip: this target has no sticky std variant');
}

console.log('[3/7] install our compiler as bin/cjc');
const installed = path.join(stage, `bin/cjc${exeSuffix}`);
await Promise.all([
  fs.rm(path.join(stage, 'bin', 'cjc'), {force: true}),
  fs.rm(path.join(stage, 'bin', 'cjc.exe'), {force: true}),
]);
await fs.copyFile(binary, installed);
await fs.chmod(installed, 0o755);

console.log('[4/7] swap in patched runtime');
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
  console.log(`  replaced ${destination}`);
} else {
  console.log('  skip: no --runtime-lib (stock runtime; only safe if cjc name exclusion is inapplicable)');
}

console.log('[5/7] set relative runtime lookup paths');
if (platform.startsWith('linux-')) {
  const available = await $({nothrow: true, quiet: true})`command -v patchelf`;
  if (available.exitCode !== 0) { console.error('  ERROR: patchelf not found'); process.exit(3); }
  await $({stdio: 'inherit'})`patchelf --set-rpath ${`$ORIGIN/../runtime/lib/${runtimeDir}:$ORIGIN/../third_party/llvm/lib:$ORIGIN/../tools/lib`} ${path.join(stage, 'bin/cjc')}`;
  const dynamic = await $({nothrow: true, quiet: true})`readelf -d ${path.join(stage, 'bin/cjc')}`;
  const runpath = dynamic.stdout.split('\n').find(line => line.includes('RUNPATH'))?.match(/\[(.*)\]/)?.[1] || '';
  process.stdout.write(`  RUNPATH: ${runpath}\n`);
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

console.log('[6/7] archive');
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

console.log('[7/7] sha256');
const archiveDigest = crypto.createHash('sha256').update(await fs.readFile(archivePath)).digest('hex');
const digest = `${archiveDigest}  ${path.basename(archivePath)}\n`;
await fs.writeFile(`${archivePath}.sha256`, digest);
console.log(`DONE: ${archivePath}`);
console.log(`SHA256: ${digest.replace(/\n+$/, '')}`);
