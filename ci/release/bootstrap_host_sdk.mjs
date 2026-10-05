import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export async function prepareHostSdk(platform, work) {
  const identities = process.env.STAGE1_HOST_IDENTITIES
    || new URL('../bootstrap/stage1_host_identities.txt', import.meta.url);
  const records = fs.readFileSync(identities, 'utf8').split('\n')
    .filter(line => line.startsWith('# HOST_SDK_PROVENANCE '))
    .map(line => JSON.parse(line.slice('# HOST_SDK_PROVENANCE '.length)))
    .filter(record => record.platform === platform);
  if (records.length !== 1) throw new Error(`HOST_SDK_PIN_MISSING: ${platform}`);
  const pin = records[0];
  const version = process.env.CJCJ_TOOLCHAIN?.replace(/^nightly-/, '');
  const archivePlatform = {linux_x86_64: 'linux-x64', linux_aarch64: 'linux-aarch64',
    darwin_x86_64: 'mac-x64', darwin_aarch64: 'mac-aarch64'}[platform];
  if (!/^[a-f0-9]{64}$/.test(pin.sha256 || '') || !/^[\w.-]+$/.test(version || '')
      || pin.archive !== `cangjie-sdk-${archivePlatform}-${version}.tar.gz`) {
    throw new Error('HOST_SDK_PIN_INVALID');
  }
  fs.mkdirSync(work, {recursive: true});
  const archive = process.env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE || path.join(work, pin.archive);
  if (!process.env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE && !fs.existsSync(archive)) {
    const response = await fetch(`https://gitcode.com/Cangjie/nightly_build/releases/download/${version}/${pin.archive}`);
    if (!response.ok) throw new Error(`HOST_SDK_DOWNLOAD_FAILED: ${response.status}`);
    fs.writeFileSync(archive, Buffer.from(await response.arrayBuffer()));
  }
  const actual = crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  if (actual !== pin.sha256) throw new Error(`HOST_SDK_SHA256_MISMATCH expected=${pin.sha256} actual=${actual}`);
  const destination = fs.mkdtempSync(path.join(work, 'host-sdk-'));
  const extracted = spawnSync('tar', ['-xzf', archive, '-C', destination], {stdio: 'inherit'});
  if (extracted.error) throw extracted.error;
  if (extracted.status !== 0) throw new Error('HOST_SDK_EXTRACT_FAILED');
  const sdk = path.join(destination, 'cangjie');
  if (!fs.statSync(path.join(sdk, 'bin/cjc')).isFile()) throw new Error('HOST_SDK_LAYOUT_INVALID');
  console.log(`HOST_SDK_VERIFIED platform=${platform} sha256=${actual} path=${sdk}`);
  return {path: path.resolve(sdk), sha256: actual};
}
