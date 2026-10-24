import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {readHostToolchainPin, requireHostToolchain} from '../host-toolchain-pin.mjs';
import {allTargets, getTarget} from '../../build/lib/targets.mjs';
import {sdkPlatform} from '../bootstrap/sdk-platform.mjs';
import {baseSdkDownload} from '../../build/lib/release-component-provenance.mjs';

export async function prepareHostSdk(platform, work) {
  const identities = process.env.STAGE1_HOST_IDENTITIES
    || new URL('../bootstrap/stage1_host_identities.txt', import.meta.url);
  const records = fs.readFileSync(identities, 'utf8').split('\n')
    .filter(line => line.startsWith('# HOST_SDK_PROVENANCE '))
    .map(line => JSON.parse(line.slice('# HOST_SDK_PROVENANCE '.length)))
    .filter(record => record.platform === platform);
  if (records.length !== 1) throw new Error(`HOST_SDK_PIN_MISSING: ${platform}`);
  const pin = records[0];
  const explicitToolchain = process.env.CJCJ_TOOLCHAIN !== undefined
    || process.env[`CJCJ_TOOLCHAIN_${platform.toUpperCase()}`] !== undefined;
  const toolchain = explicitToolchain ? requireHostToolchain(process.env, platform)
    : readHostToolchainPin(platform);
  const version = toolchain.replace(/^nightly-/, '');
  const target = allTargets().map(getTarget).find(({spec}) => spec.llvmPlatform === platform);
  const archivePlatform = target?.spec.sdkName;
  const native = sdkPlatform(platform), extension = native.os === 'win32' ? '.zip' : '.tar.gz';
  if (!/^[a-f0-9]{64}$/.test(pin.sha256 || '') || !/^[\w.-]+$/.test(version || '')
      || !target || pin.archive !== `cangjie-sdk-${archivePlatform}-${version}${extension}`
      || (pin.version !== undefined && pin.version !== version)
      || (pin.url !== undefined && pin.url !== `https://gitcode.com/Cangjie/nightly_build/releases/download/${version}/${pin.archive}`)
      || (pin.size !== undefined && (!Number.isSafeInteger(pin.size) || pin.size <= 0))) {
    throw new Error('HOST_SDK_PIN_INVALID');
  }
  // Explicit paired declarations retain the existing caller-owned contract.
  // The checked-in default must also agree with the authenticated release catalog.
  let download;
  if (!process.env.STAGE1_HOST_IDENTITIES) {
    download = baseSdkDownload(target.spec.key, toolchain);
    if (['archive', 'version', 'url', 'size', 'sha256'].some(field => pin[field] !== download[field])) {
      throw new Error('HOST_SDK_PIN_INVALID');
    }
  }
  fs.mkdirSync(work, {recursive: true});
  const archive = process.env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE || path.join(work, pin.archive);
  if (!process.env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE && !fs.existsSync(archive)) {
    const response = await fetch(download?.url
      || `https://gitcode.com/Cangjie/nightly_build/releases/download/${version}/${pin.archive}`);
    if (!response.ok) throw new Error(`HOST_SDK_DOWNLOAD_FAILED: ${response.status}`);
    fs.writeFileSync(archive, Buffer.from(await response.arrayBuffer()));
  }
  if (pin.size !== undefined && fs.statSync(archive).size !== pin.size) {
    throw new Error(`HOST_SDK_SIZE_MISMATCH expected=${pin.size} actual=${fs.statSync(archive).size}`);
  }
  const actual = crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  if (actual !== pin.sha256) throw new Error(`HOST_SDK_SHA256_MISMATCH expected=${pin.sha256} actual=${actual}`);
  const destination = fs.mkdtempSync(path.join(work, 'host-sdk-'));
  const extracted = spawnSync('tar', [native.os === 'win32' ? '-xf' : '-xzf', archive, '-C', destination], {stdio: 'inherit'});
  if (extracted.error) throw extracted.error;
  if (extracted.status !== 0) throw new Error('HOST_SDK_EXTRACT_FAILED');
  const sdk = path.join(destination, 'cangjie');
  if (!fs.statSync(path.join(sdk, 'bin/cjc' + native.exe)).isFile()) throw new Error('HOST_SDK_LAYOUT_INVALID');
  console.log(`HOST_SDK_VERIFIED platform=${platform} sha256=${actual} path=${sdk}`);
  return {path: path.resolve(sdk), sha256: actual, archive:path.resolve(archive)};
}
