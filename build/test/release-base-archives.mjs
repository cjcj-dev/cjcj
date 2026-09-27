// Integration entry: node build/test/release-base-archives.mjs <output directory>
// Runs the release downloader against all five real official archives.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const out = process.argv[2];
if (!out) throw new Error('usage: node build/test/release-base-archives.mjs <output directory>');
const pin = await fs.readFile(path.join(repo, 'ci/host_sdk_pin.env'), 'utf8');
const toolchain = pin.match(/^CJCJ_TOOLCHAIN=(\S+)$/m)?.[1];
assert.ok(toolchain);
const platforms = ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64'];
await fs.mkdir(out, {recursive: true});
async function run(platform) {
  const directory = path.resolve(out, platform);
  const started = Date.now();
  const log = await fs.open(path.join(out, `${platform}.log`), 'w');
  const child = spawn(process.execPath, [path.join(repo, 'ci/release/prepare_base_sdk.mjs'),
    '--platform', platform, '--toolchain', toolchain, '--outdir', directory],
  {cwd: repo, stdio: ['ignore', log.fd, log.fd]});
  const rc = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve(signal || code));
  });
  await log.close();
  const result = {platform, rc, wall: (Date.now() - started) / 1000};
  try {
    assert.equal(rc, 0, `real downloader ${platform}`);
    const value = JSON.parse(await fs.readFile(path.join(directory, 'BASE-SDK-PROVENANCE.json'), 'utf8'));
    const archive = path.join(directory, value.artifact.path);
    const h = crypto.createHash('sha256');
    const handle = await fs.open(archive, 'r');
    for await (const chunk of handle.createReadStream()) h.update(chunk);
    const actual = h.digest('hex');
    const size = (await fs.stat(archive)).size;
    console.log(`BASE_ARCHIVE_IDENTITY_ASSERT_REACHED platform=${platform} sha256=${actual} size=${size}`);
    assert.equal(value.artifact.sha256, actual, `${platform} emitted digest must identify downloaded bytes`);
    assert.equal(value.artifact.size, size, `${platform} emitted size must identify downloaded bytes`);
    assert.equal(`nightly-${value.release.version}`, toolchain, `${platform} release must match the host pin`);
    assert.equal(value.platform, platform);
    result.sha256 = actual;
    result.status = 'pass';
  } catch (error) {
    result.status = 'fail';
    result.error = error.message;
  }
  console.log(JSON.stringify(result));
  return result;
}
const results = await Promise.all(platforms.map(run));
await fs.writeFile(path.join(out, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
process.exitCode = results.some(result => result.status !== 'pass') ? 1 : 0;
