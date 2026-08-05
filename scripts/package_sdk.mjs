#!/usr/bin/env zx
// Repackage an official SDK with the self-host compiler and optional patched runtime into a relocatable release archive.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {requirePrivateStage} from '../build/lib/package-safety.mjs';

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
const stdDir = typeof argv['std-dir'] === 'string' ? argv['std-dir'] : '';
async function exists(file, kind = 'file') {
  try { const stat = await fs.stat(file); return kind === 'dir' ? stat.isDirectory() : stat.isFile(); } catch { return false; }
}

if (!await exists(sdk, 'dir')) { console.error(`SDK dir not found: ${sdk}`); process.exit(2); }
if (!await exists(binary)) { console.error(`cjc binary not found: ${binary}`); process.exit(2); }
if (runtimeLib && !await exists(runtimeLib)) { console.error(`runtime library not found: ${runtimeLib}`); process.exit(2); }
if (runtimeRoot && !await exists(runtimeRoot, 'dir')) { console.error(`runtime root not found: ${runtimeRoot}`); process.exit(2); }
if (stdDir && !await exists(stdDir, 'dir')) { console.error(`std dir not found: ${stdDir}`); process.exit(2); }

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
const outputRoot = path.resolve(outdir);
if (outputRoot === path.parse(outputRoot).root) throw new Error('package output root must not be a filesystem root');
const stage = path.join(outputRoot, packageName);
await fs.mkdir(outputRoot, {recursive: true});
await fs.rm(stage, {recursive: true, force: true});

console.log(`[1/7] copy SDK tree -> ${stage}`);
const sdkSource = await fs.realpath(sdk);
if (isWindows) await fs.cp(sdkSource, stage, {recursive: true, dereference: true});
else {
  await $({stdio: 'inherit'})`cp -a ${sdkSource} ${stage}`;
  await $({stdio: 'inherit'})`chmod -R u+rwX,go+rX ${stage}`;
}
await requirePrivateStage(stage, outputRoot, sdkSource);
await fs.rm(path.join(stage, '.cjv'), {recursive: true, force: true});

console.log('[2/7] install our compiler as bin/cjc');
const installed = path.join(stage, `bin/cjc${exeSuffix}`);
await Promise.all([
  fs.rm(path.join(stage, 'bin', 'cjc'), {force: true}),
  fs.rm(path.join(stage, 'bin', 'cjc.exe'), {force: true}),
]);
await fs.copyFile(binary, installed);
await fs.chmod(installed, 0o755);

console.log('[3/7] swap in patched runtime');
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

// Overlay rebuilt std (.a/.cjo + lib/libcangjie-std-*.a). --std-dir may be:
//   (a) SDK root with modules/<tuple>/std + lib/<tuple>
//   (b) modules tree root containing <tuple>/std
//   (c) the std package dir itself (…/std with std.core.a …)
console.log('[4/7] overlay rebuilt std');
if (stdDir) {
  const stdSource = await fs.realpath(stdDir);
  async function resolveStdLayout(root) {
    const candidates = [
      {
        modulesStd: path.join(root, 'modules', runtimeDir, 'std'),
        modulesTop: path.join(root, 'modules', runtimeDir),
        libDir: path.join(root, 'lib', runtimeDir),
      },
      {
        modulesStd: path.join(root, runtimeDir, 'std'),
        modulesTop: path.join(root, runtimeDir),
        libDir: path.join(root, 'lib', runtimeDir),
      },
      {
        modulesStd: root,
        modulesTop: path.dirname(root),
        libDir: path.join(root, '..', '..', 'lib', runtimeDir),
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
  const stageModulesStd = path.join(stage, 'modules', runtimeDir, 'std');
  const stageModulesTop = path.join(stage, 'modules', runtimeDir);
  const stageLib = path.join(stage, 'lib', runtimeDir);
  await fs.mkdir(stageModulesStd, {recursive: true});
  await fs.mkdir(stageLib, {recursive: true});

  const skipName = name => name === '.cached' || name.endsWith('-temp-files')
    || /\.O[01]\.a$/.test(name) || name.endsWith('.bc') || name === 'core.o';
  const entries = await fs.readdir(layout.modulesStd, {withFileTypes: true});
  let copiedA = 0;
  let copiedCjo = 0;
  for (const entry of entries) {
    if (!entry.isFile() || skipName(entry.name)) continue;
    if (!entry.name.endsWith('.a') && !entry.name.endsWith('.cjo')) continue;
    await fs.copyFile(path.join(layout.modulesStd, entry.name), path.join(stageModulesStd, entry.name));
    if (entry.name.endsWith('.a')) copiedA += 1;
    else copiedCjo += 1;
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
  if (copiedA === 0) {
    console.error(`  ERROR: --std-dir produced zero std.*.a under ${layout.modulesStd}`);
    process.exit(3);
  }
  const coreA = path.join(stageModulesStd, 'std.core.a');
  const coreLib = path.join(stageLib, 'libcangjie-std-core.a');
  if (!await exists(coreA) || !await exists(coreLib)) {
    console.error('  ERROR: overlay missing std.core.a or libcangjie-std-core.a');
    process.exit(3);
  }
  console.log(`  modules/${runtimeDir}/std: ${copiedA} .a + ${copiedCjo} .cjo`);
  console.log(`  lib/${runtimeDir}: ${copiedLib} libcangjie-std-*.a`);
} else {
  console.log('  skip: no --std-dir (stock nightly std retained)');
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
