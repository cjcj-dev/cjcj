#!/usr/bin/env zx
// Repackage an official SDK with the self-host compiler and optional patched runtime into a relocatable release archive.

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
const runtimeSo = typeof argv['runtime-so'] === 'string' ? argv['runtime-so'] : '';

async function exists(file, kind = 'file') {
  try { const stat = await fs.stat(file); return kind === 'dir' ? stat.isDirectory() : stat.isFile(); } catch { return false; }
}
if (!await exists(sdk, 'dir')) { console.error(`SDK dir not found: ${sdk}`); process.exit(2); }
if (!await exists(binary)) { console.error(`cjc binary not found: ${binary}`); process.exit(2); }
if (runtimeSo && !await exists(runtimeSo)) { console.error(`runtime .so not found: ${runtimeSo}`); process.exit(2); }

const platforms = {
  'linux-x64': ['linux_x86_64_cjnative', 'tar', ''],
  'linux-aarch64': ['linux_aarch64_cjnative', 'tar', ''],
  'mac-aarch64': ['darwin_aarch64_cjnative', 'tar', ''],
  'mac-x64': ['darwin_x86_64_cjnative', 'tar', ''],
  'windows-x64': ['windows_x86_64_cjnative', 'zip', '.exe'],
};
if (!platforms[platform]) { console.error(`unsupported --platform: ${platform}`); process.exit(2); }
const [runtimeDir, archiveType, exeSuffix] = platforms[platform];
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
if (runtimeSo) {
  const destination = path.join(stage, `runtime/lib/${runtimeDir}/libcangjie-runtime.so`);
  if (!await exists(destination)) { console.error(`  ERROR: ${destination} missing in SDK tree`); process.exit(3); }
  await fs.copyFile(runtimeSo, destination);
  console.log(`  replaced ${destination}`);
} else {
  console.log('  skip: no --runtime-so (stock runtime; only safe if cjc name exclusion is inapplicable)');
}

console.log('[4/6] set RUNPATH to $ORIGIN-relative');
if (platform.startsWith('linux-')) {
  const available = await $({nothrow: true, quiet: true})`command -v patchelf`;
  if (available.exitCode !== 0) { console.error('  ERROR: patchelf not found'); process.exit(3); }
  await $({stdio: 'inherit'})`patchelf --set-rpath ${`$ORIGIN/../runtime/lib/${runtimeDir}:$ORIGIN/../third_party/llvm/lib:$ORIGIN/../tools/lib`} ${path.join(stage, 'bin/cjc')}`;
  const dynamic = await $({nothrow: true, quiet: true})`readelf -d ${path.join(stage, 'bin/cjc')}`;
  const runpath = dynamic.stdout.split('\n').find(line => line.includes('RUNPATH'))?.match(/\[(.*)\]/)?.[1] || '';
  process.stdout.write(`  RUNPATH: ${runpath}\n`);
} else if (platform.startsWith('mac-')) {
  console.log('  skip: macOS needs install_name_tool (no mac build yet)');
} else {
  console.log('  skip: Windows resolves DLLs by dir/PATH (no win build yet)');
}

console.log('[5/6] archive');
const archivePath = path.join(outdir, `${packageName}.${archiveType === 'tar' ? 'tar.gz' : 'zip'}`);
if (archiveType === 'tar') await $({stdio: 'inherit'})`tar -C ${outdir} -czf ${archivePath} ${packageName}`;
else await $({cwd: outdir, stdio: 'inherit'})`zip -qr ${`${packageName}.zip`} ${packageName}`;

console.log('[6/6] sha256');
const digest = await $({cwd: outdir, quiet: true})`sha256sum ${path.basename(archivePath)}`;
await fs.writeFile(`${archivePath}.sha256`, digest.stdout);
console.log(`DONE: ${archivePath}`);
console.log(`SHA256: ${digest.stdout.replace(/\n+$/, '')}`);
