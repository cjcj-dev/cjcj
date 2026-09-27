// Independent native libraries. This manifest does not certify coloured std.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {digest} from './colour_runtime.mjs';
import {fileURLToPath} from 'node:url';
import {verifyDarwinStd} from './darwin_std.mjs';

export function darwinRuntime(mode, root, platform, source) {
assert.ok(['prepare', 'verify', 'source'].includes(mode), 'COLOUR_RT_MODE');
assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform), 'COLOUR_RT_PLATFORM');
const tuple = `${platform}_cjnative`;
const files = [`runtime/lib/${tuple}/libcangjie-runtime.dylib`,
  `runtime/lib/${tuple}/libboundscheck.dylib`, `lib/${tuple}/libcangjie-runtime.a`];
const manifestFile = path.join(root, 'manifest.json');
if (mode === 'prepare') {
  assert.match(process.env.RUNTIME_REF || '', /^[a-f0-9]{40}$/, 'COLOUR_RT_SOURCE_PIN');
  assert.equal(fs.readFileSync(path.join(source, 'SOURCE_SHA'), 'utf8').trim(), process.env.RUNTIME_REF,
    'COLOUR_RT_SOURCE_MISMATCH');
  assert.match(process.env.GITHUB_RUN_ID || '', /^\d+$/, 'COLOUR_RT_RUN_MISSING');
  assert.match(process.env.GITHUB_RUN_ATTEMPT || '', /^\d+$/, 'COLOUR_RT_RUN_MISSING');
  const hashes = {};
  for (const relative of files) {
    const input = path.join(source, relative);
    const output = path.join(root, relative);
    assert.ok(fs.lstatSync(input).isFile(), `COLOUR_RT_FILE: ${relative}`);
    fs.mkdirSync(path.dirname(output), {recursive: true});
    fs.copyFileSync(input, output);
    hashes[relative] = digest(input);
  }
  fs.writeFileSync(manifestFile, JSON.stringify({role: 'colour-runtime-libraries',
    runtime_sha: process.env.RUNTIME_REF, platform, producer_sha: process.env.GITHUB_SHA,
    run_id: process.env.GITHUB_RUN_ID, run_attempt: process.env.GITHUB_RUN_ATTEMPT,
    files: hashes}, null, 2) + '\n');
  console.log(`COLOUR_RT_MANIFEST_SHA256=${digest(manifestFile)}`);
} else {
  assert.match(process.env.COLOUR_RT_MANIFEST_SHA256 || '', /^[a-f0-9]{64}$/, 'COLOUR_RT_PIN_MISSING');
  assert.equal(digest(manifestFile), process.env.COLOUR_RT_MANIFEST_SHA256, 'COLOUR_RT_SHA256_MISMATCH');
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  assert.equal(manifest.role, 'colour-runtime-libraries', 'COLOUR_RT_ROLE_MISMATCH');
  assert.equal(manifest.platform, platform, 'COLOUR_RT_PLATFORM_MISMATCH');
  assert.equal(manifest.runtime_sha, process.env.RUNTIME_REF, 'COLOUR_RT_SOURCE_MISMATCH');
  assert.equal(manifest.run_id, process.env.COLOUR_RT_RUN_ID, 'COLOUR_RT_RUN_MISMATCH');
  assert.equal(manifest.run_attempt, process.env.COLOUR_RT_RUN_ATTEMPT, 'COLOUR_RT_RUN_MISMATCH');
  for (const relative of files) {
    assert.ok(fs.lstatSync(path.join(root, relative)).isFile(), `COLOUR_RT_FILE: ${relative}`);
    assert.equal(digest(path.join(root, relative)), manifest.files[relative], `COLOUR_RT_FILE_SHA256_MISMATCH: ${relative}`);
    if (source) assert.equal(digest(path.join(root, relative)), digest(path.join(source, relative)),
      `COLOUR_RT_COPY_SHA256_MISMATCH: ${relative}`);
    console.log(`COLOUR_RT_LIBRARY_VERIFIED ${relative} ${manifest.files[relative]}`);
  }
  if (mode === 'source') {
    // #473 must register a complete, separately verified std input before bootstrap.
    assert.ok(fs.existsSync(path.join(root, `lib/${tuple}/libcangjie-std-core.a`))
      && fs.existsSync(path.join(root, 'modules', tuple)), `COLOUR_RT_STD_MISSING: ${platform}`);
    const release = JSON.parse(fs.readFileSync(process.env.CJCJ_COLOUR_RUNTIME_RELEASE_PIN
      || new URL('../colour-runtime/release.json', import.meta.url)));
    verifyDarwinStd(root, platform, release.platforms?.[platform]?.std, digest(manifestFile));
  }
}

return root;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  darwinRuntime(...process.argv.slice(2));
}
