#!/usr/bin/env zx
// Complete std identity is separate from the independently pinned three libraries.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {digest} from './colour_runtime.mjs';

function regular(root, relative) {
  assert.ok(/^[\w.-]+(?:\/[\w.-]+)*$/.test(relative)
    && !relative.split('/').some(p => p === '.' || p === '..'), 'COLOUR_RT_STD_PATH');
  let file = root;
  for (const part of relative.split('/')) {
    file = path.join(file, part);
    assert.ok(!fs.lstatSync(file).isSymbolicLink(), `COLOUR_RT_STD_SYMLINK: ${relative}`);
  }
  assert.ok(fs.statSync(file).isFile(), `COLOUR_RT_STD_FILE: ${relative}`);
  return file;
}
function required(platform) {
  const tuple = `${platform}_cjnative`;
  return [`lib/${tuple}/libcangjie-std-core.a`, `runtime/lib/${tuple}/libcangjie-std-core.dylib`,
    'lib/libstdFFI.dylib', 'std-producer.json'];
}
export function verifyDarwinStd(root, platform, pin, runtimeManifestSha) {
  const tuple = `${platform}_cjnative`;
  assert.ok(fs.existsSync(path.join(root, `lib/${tuple}/libcangjie-std-core.a`))
    && fs.existsSync(path.join(root, 'modules', tuple)), `COLOUR_RT_STD_MISSING: ${platform}`);
  assert.ok(pin && /^[a-f0-9]{64}$/.test(pin.manifest_sha256 || ''), `COLOUR_RT_STD_PROVENANCE_MISSING: ${platform}`);
  const file = regular(root, 'std-manifest.json');
  assert.equal(digest(file), pin.manifest_sha256, 'COLOUR_RT_STD_MANIFEST_SHA256');
  const manifest = JSON.parse(fs.readFileSync(file));
  assert.equal(manifest.role, 'colour-std', 'COLOUR_RT_STD_ROLE');
  assert.equal(manifest.platform, platform, 'COLOUR_RT_STD_PLATFORM');
  assert.equal(manifest.runtime_manifest_sha256, runtimeManifestSha, 'COLOUR_RT_STD_RUNTIME_IDENTITY');
  assert.equal(manifest.compiler_sha256, pin.compiler_sha256, 'COLOUR_RT_STD_COMPILER_IDENTITY');
  assert.equal(manifest.producer_sha, pin.producer_sha, 'COLOUR_RT_STD_PRODUCER_IDENTITY');
  assert.equal(manifest.run_id, pin.run_id, 'COLOUR_RT_STD_RUN_IDENTITY');
  assert.equal(manifest.run_attempt, pin.run_attempt, 'COLOUR_RT_STD_RUN_IDENTITY');
  const files = manifest.files || {};
  for (const relative of required(platform)) assert.ok(files[relative], `COLOUR_RT_STD_REQUIRED: ${relative}`);
  assert.ok(Object.keys(files).some(f => f.startsWith(`modules/${tuple}/`)), 'COLOUR_RT_STD_MODULES');
  for (const [relative, expected] of Object.entries(files)) {
    assert.match(expected, /^[a-f0-9]{64}$/, 'COLOUR_RT_STD_DIGEST');
    assert.equal(digest(regular(root, relative)), expected, `COLOUR_RT_STD_FILE_SHA256: ${relative}`);
  }
  assert.equal(JSON.parse(fs.readFileSync(path.join(root, 'std-producer.json'))).compiler_sha256,
    manifest.compiler_sha256, 'COLOUR_RT_STD_COMPILER_LINEAGE');
  console.log(`COLOUR_RT_STD_VERIFIED platform=${platform} compiler=${manifest.compiler_sha256} files=${Object.keys(files).length}`);
  return root;
}
