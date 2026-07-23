#!/usr/bin/env zx
// Repackage an official SDK with the self-host compiler and optional patched runtime into a relocatable release archive.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

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

async function exists(file, kind = 'file') {
  try { const stat = await fs.stat(file); return kind === 'dir' ? stat.isDirectory() : stat.isFile(); } catch { return false; }
}
if (!await exists(sdk, 'dir')) { console.error(`SDK dir not found: ${sdk}`); process.exit(2); }
if (!await exists(binary)) { console.error(`cjc binary not found: ${binary}`); process.exit(2); }
if (runtimeLib && !await exists(runtimeLib)) { console.error(`runtime library not found: ${runtimeLib}`); process.exit(2); }

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
const packageName = `cjcj-${version}-${platform}`;
const stage = path.join(outdir, packageName);
await fs.mkdir(outdir, {recursive: true});
await fs.rm(stage, {recursive: true, force: true});

console.log(`[1/6] copy SDK tree -> ${stage}`);
await $({stdio: 'inherit'})`cp -a ${sdk} ${stage}`;
await $({stdio: 'inherit'})`chmod -R u+rwX,go+rX ${stage}`;
await fs.rm(path.join(stage, '.cjv'), {recursive: true, force: true});

console.log('[2/6] install our compiler as bin/cjc');
const installed = path.join(stage, `bin/cjc${exeSuffix}`);
await fs.copyFile(binary, installed);
await fs.chmod(installed, 0o755);

console.log('[3/6] swap in patched runtime');
if (runtimeLib) {
  const destination = path.join(stage, 'runtime', 'lib', runtimeDir, runtimeLibrary);
  if (!await exists(destination)) { console.error(`  ERROR: ${destination} missing in SDK tree`); process.exit(3); }
  await fs.copyFile(runtimeLib, destination);
  console.log(`  replaced ${destination}`);
} else {
  console.log('  skip: no --runtime-lib (stock runtime; only safe if cjc name exclusion is inapplicable)');
}

console.log('[4/6] set relative runtime lookup paths');
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
  console.log('  skip: Windows resolves DLLs by dir/PATH (no win build yet)');
}

console.log('[5/6] archive');
const archivePath = path.join(outdir, `${packageName}.${archiveType === 'tar' ? 'tar.gz' : 'zip'}`);
if (archiveType === 'tar') await $({stdio: 'inherit'})`tar -C ${outdir} -czf ${archivePath} ${packageName}`;
else await $({cwd: outdir, stdio: 'inherit'})`zip -qr ${`${packageName}.zip`} ${packageName}`;

console.log('[6/6] sha256');
const archiveDigest = crypto.createHash('sha256').update(await fs.readFile(archivePath)).digest('hex');
const digest = `${archiveDigest}  ${path.basename(archivePath)}\n`;
await fs.writeFile(`${archivePath}.sha256`, digest);
console.log(`DONE: ${archivePath}`);
console.log(`SHA256: ${digest.replace(/\n+$/, '')}`);
