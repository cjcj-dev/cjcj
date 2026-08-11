#!/usr/bin/env zx
// Install the Cangjie bootstrap SDK and export the build environment.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {runGrepProbe} from '../build/lib/fail-closed-probes.mjs';
import {parseLlvmToolsManifest} from './llvm-tools-manifest.mjs';
import {
  persistBaseSdkProvenance,
  verifyBaseSdkProvenance,
} from '../build/lib/release-component-provenance.mjs';

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
const baseSdkArchive = process.env.BASE_SDK_ARCHIVE || '';
const baseSdkProvenance = process.env.BASE_SDK_PROVENANCE || '';
const releasePlatform = process.env.RELEASE_PLATFORM || '';
if (baseSdkArchive || baseSdkProvenance || releasePlatform) {
  if (!baseSdkArchive || !baseSdkProvenance || !releasePlatform) {
    throw new Error('BASE_SDK_ARCHIVE, BASE_SDK_PROVENANCE and RELEASE_PLATFORM must be supplied together');
  }
  const provenance = await verifyBaseSdkProvenance({
    archive: baseSdkArchive,
    sidecar: baseSdkProvenance,
    platform: releasePlatform,
    toolchain,
  });
  log(`cjv toolchain link ${toolchain} ${baseSdkArchive} --force --sha256 ${provenance.artifact.sha256}`);
  await $`cjv toolchain link ${toolchain} ${baseSdkArchive} --force --sha256 ${provenance.artifact.sha256}`;
  log(`cjv component add stdx --toolchain ${toolchain}`);
  await $`cjv component add stdx --toolchain ${toolchain}`;
} else {
  log(`cjv install ${toolchain} -c stdx`);
  await $`cjv install ${toolchain} -c stdx`;
}

const cangjieHome = `${home}/.cjv/toolchains/${toolchain}`;
if (!(await isDirectory(cangjieHome))) {
  log(`toolchain dir missing: ${cangjieHome}`);
  process.exit(3);
}
if (baseSdkArchive) {
  const retained = await persistBaseSdkProvenance({
    archive: baseSdkArchive,
    sidecar: baseSdkProvenance,
    toolchainDir: cangjieHome,
    platform: releasePlatform,
    toolchain,
  });
  log(`base SDK provenance retained: sidecar=${retained.sidecar} archive=${retained.cachedArchive}`);
}
const stdxPath = `${home}/.cjv/stdx/${toolchain}/static/stdx`;

const installedCjc = path.join(cangjieHome, 'bin', 'cjc');
const baseLibraryPath = `${cangjieHome}/third_party/llvm/lib:${cangjieHome}/runtime/lib/${runtimeDir}:${cangjieHome}/tools/lib`;
const baseEnvironment = {...process.env};
if (hostOs === 'Darwin') baseEnvironment.DYLD_LIBRARY_PATH = baseLibraryPath;
else baseEnvironment.LD_LIBRARY_PATH = baseLibraryPath;
const baseFile = await $({nothrow: true, stdio: 'pipe'})`file ${installedCjc}`;
const baseLinked = hostOs === 'Darwin'
  ? await $({nothrow: true, stdio: 'pipe'})`otool -L ${installedCjc}`
  : await $({nothrow: true, stdio: 'pipe', env: baseEnvironment})`ldd ${installedCjc}`;
const baseVersion = await $({nothrow: true, stdio: 'pipe', env: baseEnvironment})`${installedCjc} --version`;
if (baseFile.exitCode !== 0 || baseLinked.exitCode !== 0 || baseVersion.exitCode !== 0 ||
    /not found/i.test(baseLinked.stdout)) {
  throw new Error(`installed base SDK failed file/link/--version verification: file=${baseFile.exitCode} linked=${baseLinked.exitCode} version=${baseVersion.exitCode}`);
}
log(`base cjc file: ${baseFile.stdout.trim()}`);
log(`base cjc linked libraries: no missing entries`);
log(`base cjc version:\n${baseVersion.stdout.trim()}`);

// 2.5 Swap the SDK's optimizer, backend and (for releases) LTO linker with one
// source-built fixed LLVM tuple.
// The stock nightly backend materializes relocate-of-undef as a phantom GC root.
// These static tools contain the backend fixes and have no libLLVM dependency. Keep
// each true original once, and break a possible hardlink before replacing a binary.
// Jobs that only consume the toolchain's archives and headers as link inputs
// (no Cangjie compilation, e.g. the Windows std-ast relink) opt out of the llc
// requirement with CJCJ_SDK_LINK_INPUTS_ONLY=1. Jobs that never feed cjcj-generated
// IR to llc at all (the non-gating SDK provisioning check, which exercises only the
// official toolchain) keep the stock llc with CJCJ_SDK_STOCK_LLC=1.
const keepStockLlc = process.env.CJCJ_SDK_LINK_INPUTS_ONLY || process.env.CJCJ_SDK_STOCK_LLC;
const llcPlatforms = {
  'Linux/x86_64': 'linux_x86_64',
  'Linux/aarch64': 'linux_aarch64',
  'Darwin/x86_64': 'darwin_x86_64',
  'Darwin/arm64': 'darwin_aarch64',
};
const llcPlatform = keepStockLlc ? '' : llcPlatforms[`${hostOs}/${hostArch}`] || '';
const fixedLlcGz = process.env.FIXED_LLC_GZ || '';
const fixedOptGz = process.env.FIXED_OPT_GZ || '';
const lldTool = hostOs === 'Darwin' ? 'ld64.lld' : 'ld.lld';
const fixedLldGz = process.env.FIXED_LLD_GZ ||
  (fixedLlcGz ? path.join(path.dirname(fixedLlcGz), `${lldTool}.gz`) : '');
const hasFixedLld = Boolean(fixedLldGz && await isFile(fixedLldGz));
const releaseNeedsLld = Boolean(process.env.RELEASE_PLATFORM);
const sdkLlvmBin = `${cangjieHome}/third_party/llvm/bin`;
const fixedTools = [
  {name: 'llc', archive: fixedLlcGz, sdk: `${sdkLlvmBin}/llc`, manifestKey: 'LLC_SHA256', versionKey: 'LLC_VERSION'},
  {name: 'opt', archive: fixedOptGz, sdk: `${sdkLlvmBin}/opt`, manifestKey: 'OPT_SHA256', versionKey: 'OPT_VERSION'},
  {name: lldTool, archive: fixedLldGz, sdk: `${sdkLlvmBin}/${lldTool}`, manifestKey: 'LLD_SHA256', versionKey: 'LLD_VERSION'},
];
if (llcPlatform && fixedLlcGz) {
  if (process.env.CI && (!fixedOptGz || (releaseNeedsLld && !hasFixedLld))) {
    log(`FATAL: llc, opt and native LLD artifacts are required for ${llcPlatform} release CI`);
    process.exit(4);
  }
  const toolsToInstall = fixedOptGz
    ? fixedTools.slice(0, hasFixedLld ? fixedTools.length : 2)
    : fixedTools.slice(0, 1);
  for (const tool of toolsToInstall) {
    if (!(await isFile(tool.archive))) {
      log(`FATAL: fixed ${tool.name} artifact missing: ${tool.archive}`);
      process.exit(4);
    }
    if (!(await isFile(tool.sdk))) {
      log(`FATAL: SDK ${tool.name} missing: ${tool.sdk}`);
      process.exit(4);
    }
  }

  const expectedShas = new Map();
  const expectedVersions = new Map();
  let llvmSourceSha = '';
  if (fixedOptGz) {
    const manifestPath = path.join(path.dirname(fixedLlcGz), 'llvm-tools.manifest');
    if (!(await isFile(manifestPath))) {
      log(`FATAL: fixed LLVM provenance manifest missing: ${manifestPath}`);
      process.exit(4);
    }
    const manifestText = await fs.readFile(manifestPath, 'utf8');
    let manifest;
    try {
      manifest = parseLlvmToolsManifest(manifestText, {label: manifestPath, schema: 'core-or-native'});
    } catch (error) {
      log(`FATAL: malformed fixed LLVM provenance manifest: ${error.message}`);
      process.exit(4);
    }
    const parsedSchema = manifest.schema;
    manifest = manifest.values;
    llvmSourceSha = manifest.get('LLVM_SHA') || '';
    const pinText = await fs.readFile(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
    const expectedFields = [['LLVM_SHA', pinText.match(/^LLVM_SHA=([0-9a-f]{40})$/m)?.[1] || '']];
    if (parsedSchema === 'native') expectedFields.push(
      ['PLATFORM', llcPlatform],
      ['CANGJIE_COMPILER_SHA', pinText.match(/^CANGJIE_COMPILER_SHA=([0-9a-f]{40})$/m)?.[1] || ''],
      ['FLATBUFFERS_SHA', pinText.match(/^FLATBUFFERS_SHA=([0-9a-f]{40})$/m)?.[1] || ''],
    );
    for (const [field, expected] of expectedFields) {
      if (!expected || manifest.get(field) !== expected) {
        log(`FATAL: fixed LLVM ${field} mismatch (manifest=${manifest.get(field) || ''}, expected=${expected})`);
        process.exit(4);
      }
    }
    if (hasFixedLld && (parsedSchema !== 'core-lineage' || manifest.get('LLD_TOOL') !== lldTool)) {
      log(`FATAL: fixed LLVM LLD lineage mismatch (schema=${parsedSchema} tool=${manifest.get('LLD_TOOL') || ''})`);
      process.exit(4);
    }
    if (parsedSchema === 'native') {
      const fixedShim = path.join(path.dirname(fixedLlcGz), 'cjselfhost_llvmshim.o');
      if (!(await isFile(fixedShim))) {
        log(`FATAL: fixed LLVM shim missing: ${fixedShim}`);
        process.exit(4);
      }
      const shimSha = crypto.createHash('sha256').update(await fs.readFile(fixedShim)).digest('hex');
      if (shimSha !== manifest.get('SHIM_SHA256')) {
        log(`FATAL: fixed LLVM shim sha mismatch (${shimSha})`);
        process.exit(4);
      }
    }
    for (const tool of toolsToInstall) {
      const expectedSha = manifest.get(tool.manifestKey) || '';
      if (!/^[0-9a-f]{64}$/.test(expectedSha)) {
        log(`FATAL: ${tool.manifestKey} missing from fixed LLVM provenance manifest`);
        process.exit(4);
      }
      expectedShas.set(tool.name, expectedSha);
      const expectedVersion = manifest.get(tool.versionKey) || '';
      if (expectedVersion) expectedVersions.set(tool.name, expectedVersion);
    }
  } else {
    const llcSha = (await $({stdio: 'pipe'})`gunzip -c ${fixedLlcGz} | sha256sum`).stdout.trim().split(/\s+/)[0];
    expectedShas.set('llc', llcSha);
  }

  // Validate the complete tuple before changing any SDK binary.
  for (const tool of toolsToInstall) {
    const artifactSha = (await $({stdio: 'pipe'})`gunzip -c ${tool.archive} | sha256sum`).stdout.trim().split(/\s+/)[0];
    if (artifactSha !== expectedShas.get(tool.name)) {
      log(`FATAL: fixed ${tool.name} artifact sha mismatch (${artifactSha})`);
      process.exit(4);
    }
  }
  for (const tool of toolsToInstall) {
    const expectedSha = expectedShas.get(tool.name);
    const currentSha = (await $({stdio: 'pipe'})`sha256sum ${tool.sdk}`).stdout.trim().split(/\s+/)[0];
    if (currentSha !== expectedSha) {
      if (!(await isFile(`${tool.sdk}.orig`))) await $`cp -f ${tool.sdk} ${tool.sdk}.orig`;
      await fs.rm(tool.sdk, {force: true});
      await $`gunzip -c ${tool.archive} > ${tool.sdk}`;
      await $`chmod 0755 ${tool.sdk}`;
    }
    const installedSha = (await $({stdio: 'pipe'})`sha256sum ${tool.sdk}`).stdout.trim().split(/\s+/)[0];
    if (installedSha !== expectedSha) {
      log(`FATAL: installed ${tool.name} sha mismatch (${installedSha})`);
      process.exit(4);
    }
    log(`SDK ${tool.name} -> source-built fixed LLVM (${installedSha})`);
  }

  if (fixedOptGz) {
    for (const tool of toolsToInstall) {
      const fileResult = await $({nothrow: true, stdio: 'pipe'})`file ${tool.sdk}`;
      const lddResult = await $({nothrow: true, stdio: 'pipe'})`ldd ${tool.sdk}`;
      const versionResult = await $({nothrow: true, stdio: 'pipe'})`${tool.sdk} --version`;
      if (fileResult.exitCode !== 0 || lddResult.exitCode !== 0 || lddResult.stdout.includes('not found') || versionResult.exitCode !== 0) {
        log(`FATAL: installed ${tool.name} failed file/ldd/--version verification`);
        process.exit(4);
      }
      const reportedVersion = versionResult.stdout.split(/\r?\n/).map(line => line.trim())
        .find(line => /LLVM version |^LLD /.test(line)) || '';
      const expectedVersion = expectedVersions.get(tool.name) || '';
      if (expectedVersion && reportedVersion !== expectedVersion) {
        log(`FATAL: installed ${tool.name} version mismatch (${reportedVersion} != ${expectedVersion})`);
        process.exit(4);
      }
      log(`${tool.name} file: ${fileResult.stdout.trim()}`);
      log(`${tool.name} ldd: no missing libraries`);
      log(`${tool.name} version:\n${versionResult.stdout.trim()}`);
    }
    log(`installed ${toolsToInstall.map(tool => tool.name).join('/')} provenance verified: LLVM ${llvmSourceSha}`);
  }
} else if (llcPlatform && process.env.CI) {
  log(`FATAL: fixed llc/opt tuple is required for ${llcPlatform} CI`);
  process.exit(4);
} else {
  log(`no source-built fixed LLVM tuple for ${hostOs}/${hostArch}; keeping stock tools`);
}

// 3. In CI only, repoint the checkout's hard-coded libLLVM path at this SDK.
if (`${process.env.GITHUB_ENV || ''}${process.env.CI || ''}`) {
  const cjpmToml = `${repoRoot}/packages/cjc/cjpm.toml`;
  const sdkLlvmDir = `${cangjieHome}/third_party/llvm/lib`;
  const hardPathProbe = await runGrepProbe({
    label: 'SDK hard-coded LLVM library path grep',
    run: () => $({nothrow: true, stdio: 'pipe'})`grep -m 1 -oE "/[^ '\\"]*/third_party/llvm/lib" ${cjpmToml}`,
  });
  const hardDir = hardPathProbe.matched ? hardPathProbe.result.stdout.trim() : '';
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
