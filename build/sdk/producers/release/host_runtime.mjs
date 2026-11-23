// Extract the official host pair; coloured std/runtime are separate inputs.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const [mode, sdk, output, platform] = process.argv.slice(2);
assert.ok(['prepare', 'verify'].includes(mode), 'HOST_RT_MODE');
assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform), 'HOST_RT_PLATFORM');
const toolchain = process.env.CJCJ_TOOLCHAIN;
assert.ok(toolchain && toolchain === process.env.CJCJ_ACTUAL_HOST_TOOLCHAIN, 'HOST_RT_TOOLCHAIN');
const files = ['libcangjie-runtime.dylib', 'libboundscheck.dylib']
  .map(name => `runtime/lib/${platform}_cjnative/${name}`);
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const manifestFile = path.join(output, 'manifest.json');
if (mode === 'prepare') {
  const hashes = {};
  for (const relative of files) {
    const source = path.join(sdk, relative);
    const destination = path.join(output, relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.copyFileSync(source, destination);
    hashes[relative] = digest(source);
  }
  fs.writeFileSync(manifestFile, JSON.stringify({
    role: 'official-host-runtime', platform, toolchain,
    producer_sha: process.env.GITHUB_SHA,
    run_id: process.env.GITHUB_RUN_ID, run_attempt: process.env.GITHUB_RUN_ATTEMPT,
    files: hashes,
  }, null, 2) + '\n');
} else {
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  assert.equal(manifest.role, 'official-host-runtime');
  assert.equal(manifest.platform, platform);
  assert.equal(manifest.toolchain, toolchain);
  for (const relative of files) {
    const expected = digest(path.join(sdk, relative));
    assert.equal(manifest.files[relative], expected, `HOST_RT_SOURCE_SHA256: ${relative}`);
    assert.equal(digest(path.join(output, relative)), expected, `HOST_RT_COPY_SHA256: ${relative}`);
    console.log(`HOST_RT_COPY_VERIFIED ${relative} ${expected}`);
  }
}
