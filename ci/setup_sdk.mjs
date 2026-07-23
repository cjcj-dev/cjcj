#!/usr/bin/env zx
// Install the Cangjie bootstrap SDK and export the build environment.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

$.stdio = 'inherit';

const repoRoot = process.env.REPO_ROOT || path.resolve(import.meta.dirname, '..');
const toolchain = process.env.CJCJ_TOOLCHAIN || 'nightly-1.2.0-alpha.20260721165458';
const cjvVersion = process.env.CJV_VERSION || 'v0.2.20';
const heapSize = process.env.CJ_HEAP_SIZE || '12GB';
const home = process.env.HOME;
if (!home) throw new Error('HOME is required');
const log = (message) => console.log(`[sdk] ${message}`);

async function isDirectory(target) {
  try { return (await fs.stat(target)).isDirectory(); } catch { return false; }
}

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}

async function commandExists(command) {
  return (await $({nothrow: true, stdio: 'pipe'})`command -v ${command}`).exitCode === 0;
}

// Host -> cjv asset name and runtime lib dir.
const hostOs = (await $({stdio: 'pipe'})`uname -s`).stdout.trim();
const hostArch = (await $({stdio: 'pipe'})`uname -m`).stdout.trim();
const hosts = {
  'Linux/x86_64': ['cjv_linux_amd64.tar.gz', 'linux_x86_64_cjnative'],
  'Linux/aarch64': ['cjv_linux_arm64.tar.gz', 'linux_aarch64_cjnative'],
  'Darwin/arm64': ['cjv_darwin_arm64.tar.gz', 'darwin_aarch64_cjnative'],
  'Darwin/x86_64': ['cjv_darwin_amd64.tar.gz', 'darwin_x86_64_cjnative'],
};
const host = hosts[`${hostOs}/${hostArch}`];
if (!host) {
  log(`unsupported host ${hostOs}/${hostArch}`);
  process.exit(2);
}
const [cjvAsset, runtimeDir] = host;

// 1. Bootstrap cjv.
if (!(await commandExists('cjv'))) {
  log(`install cjv ${cjvVersion}`);
  const tools = `${home}/.local/bin`;
  await fs.mkdir(tools, {recursive: true});
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cjv-'));
  await $`curl -fsSL -o ${tmp}/cjv.tar.gz https://github.com/Zxilly/cjv/releases/download/${cjvVersion}/${cjvAsset}`;
  await $`tar -C ${tmp} -xzf ${tmp}/cjv.tar.gz`;
  const found = await $({stdio: 'pipe'})`find ${tmp} -type f -name cjv`;
  const cjv = found.stdout.split('\n').find(Boolean);
  if (!cjv) throw new Error('downloaded cjv archive contains no cjv executable');
  await $`install -m0755 ${cjv} ${tools}/cjv`;
  process.env.PATH = `${tools}:${process.env.PATH || ''}`;
}
const cjvResult = await $({nothrow: true, stdio: 'pipe'})`cjv --version`;
log(`cjv ${cjvResult.stdout.trim()}`);

// 2. Install toolchain and stdx. The GitCode key is an optional accelerator.
if (process.env.GITCODE_API_KEY) {
  await $({nothrow: true, stdio: 'pipe'})`cjv set gitcode-api-key ${process.env.GITCODE_API_KEY}`;
  log('gitcode-api-key set');
}
log(`cjv install ${toolchain} -c stdx`);
await $`cjv install ${toolchain} -c stdx`;

const cangjieHome = `${home}/.cjv/toolchains/${toolchain}`;
if (!(await isDirectory(cangjieHome))) {
  log(`toolchain dir missing: ${cangjieHome}`);
  process.exit(3);
}
const stdxPath = `${home}/.cjv/stdx/${toolchain}/static/stdx`;

// 2.5 Swap the SDK's llc with the source-built -O2-fixed static llc.
// The stock nightly backend materializes relocate-of-undef as a phantom GC root.
// This static llc contains the backend fix and has no libLLVM dependency. Keep the
// true original once, and break a possible hardlink before replacing the binary.
const llcPlatform = `${hostOs}/${hostArch}` === 'Linux/x86_64' ? 'linux_x86_64' : '';
const fixedLlcGz = process.env.FIXED_LLC_GZ || '';
const sdkLlc = `${cangjieHome}/third_party/llvm/bin/llc`;
if (llcPlatform && fixedLlcGz) {
  if (!(await isFile(fixedLlcGz))) {
    log(`FATAL: fixed llc artifact missing: ${fixedLlcGz}`);
    process.exit(4);
  }
  if (!(await isFile(sdkLlc))) {
    log(`FATAL: SDK llc missing: ${sdkLlc}`);
    process.exit(4);
  }
  const fixedLlcSha = (await $({stdio: 'pipe'})`gunzip -c ${fixedLlcGz} | sha256sum`).stdout.trim().split(/\s+/)[0];
  const currentSha = (await $({stdio: 'pipe'})`sha256sum ${sdkLlc}`).stdout.trim().split(/\s+/)[0];
  if (currentSha !== fixedLlcSha) {
    if (!(await isFile(`${sdkLlc}.orig`))) await $`cp -f ${sdkLlc} ${sdkLlc}.orig`;
    await fs.rm(sdkLlc, {force: true});
    await $`gunzip -c ${fixedLlcGz} > ${sdkLlc}`;
    await $`chmod 0755 ${sdkLlc}`;
    const gotSha = (await $({stdio: 'pipe'})`sha256sum ${sdkLlc}`).stdout.trim().split(/\s+/)[0];
    if (gotSha !== fixedLlcSha) {
      log(`FATAL: fixed llc artifact sha mismatch (${gotSha})`);
      process.exit(4);
    }
    log(`swapped SDK llc -> source-built -O2-fixed (${fixedLlcSha})`);
  } else {
    log('SDK llc already -O2-fixed; skip');
  }
} else if (llcPlatform && process.env.CI) {
  log('FATAL: FIXED_LLC_GZ is required for Linux x86_64 CI');
  process.exit(4);
} else {
  log(`no source-built fixed llc artifact for ${hostOs}/${hostArch}; keeping stock llc`);
}

// 3. In CI only, repoint the checkout's hard-coded libLLVM path at this SDK.
if (`${process.env.GITHUB_ENV || ''}${process.env.CI || ''}`) {
  const cjpmToml = `${repoRoot}/packages/cjc/cjpm.toml`;
  const sdkLlvmDir = `${cangjieHome}/third_party/llvm/lib`;
  const grep = await $({nothrow: true, stdio: 'pipe'})`grep -oE "/[^ '\\"]*/third_party/llvm/lib" ${cjpmToml} | head -1`;
  const hardDir = grep.stdout.trim();
  if (hardDir && hardDir !== sdkLlvmDir) {
    await $`sed ${`s#${hardDir}#${sdkLlvmDir}#g`} ${cjpmToml} > ${cjpmToml}.tmp`;
    await $`mv ${cjpmToml}.tmp ${cjpmToml}`;
    log(`repoint cjpm.toml LLVM dir -> ${sdkLlvmDir}`);
  }
}

// 4. Export environment. GitHub command files are append-only.
const ldVar = hostOs === 'Darwin' ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH';
const ldPath = `${cangjieHome}/third_party/llvm/lib:${cangjieHome}/runtime/lib/${runtimeDir}:${cangjieHome}/tools/lib`;
if (process.env.GITHUB_ENV) {
  if (!process.env.GITHUB_PATH) throw new Error('GITHUB_PATH is required when GITHUB_ENV is set');
  await fs.appendFile(process.env.GITHUB_ENV, [
    `CANGJIE_HOME=${cangjieHome}`,
    `CANGJIE_STDX_PATH=${stdxPath}`,
    `${ldVar}=${ldPath}`,
    `cjHeapSize=${heapSize}`,
    '',
  ].join('\n'));
  await fs.appendFile(process.env.GITHUB_PATH, `${cangjieHome}/bin\n${cangjieHome}/tools/bin\n${home}/.local/bin\n`);
  log(`env -> $GITHUB_ENV (${ldVar})`);
} else {
  console.log(`export CANGJIE_HOME=${cangjieHome}`);
  console.log(`export PATH=${cangjieHome}/bin:${cangjieHome}/tools/bin:$PATH`);
  console.log(`export ${ldVar}=${ldPath}`);
  console.log(`export CANGJIE_STDX_PATH=${stdxPath}`);
  console.log(`export cjHeapSize=${heapSize}`);
}
log(`CANGJIE_HOME=${cangjieHome}`);
