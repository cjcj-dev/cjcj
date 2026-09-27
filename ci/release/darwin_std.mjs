// Complete std identity is separate from the independently pinned three libraries.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
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
export function prepareDarwinStd(prefix, runtime, hostRuntime, compiler, platform, output) {
  assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform));
  const tuple = `${platform}_cjnative`;
  for (const relative of required(platform)) regular(prefix, relative);
  const compilerSha = digest(compiler);
  assert.equal(JSON.parse(fs.readFileSync(path.join(prefix, 'std-producer.json'))).compiler_sha256,
    compilerSha, 'COLOUR_RT_STD_COMPILER_LINEAGE');
  const colour = spawnSync('python3', [fileURLToPath(new URL('../bootstrap/std_runtime_colour.py', import.meta.url)),
    '--colour-runtime', path.join(runtime, `runtime/lib/${tuple}/libcangjie-runtime.dylib`),
    '--host-runtime', path.join(hostRuntime, `runtime/lib/${tuple}/libcangjie-runtime.dylib`),
    '--runtime', path.join(runtime, `runtime/lib/${tuple}/libcangjie-runtime.dylib`),
    '--std', path.join(prefix, `lib/${tuple}/libcangjie-std-core.a`), '--source', prefix], {stdio: 'inherit'});
  assert.equal(colour.status, 0, 'COLOUR_RT_STD_COLOUR');
  function walk(directory) {
    return fs.readdirSync(path.join(prefix, directory), {withFileTypes: true}).flatMap(entry => {
      const relative = path.posix.join(directory, entry.name);
      return entry.isDirectory() ? walk(relative) : [relative];
    });
  }
  const names = [`std-producer.json`, ...walk(`modules/${tuple}`), ...walk(`lib/${tuple}`),
    ...walk(`runtime/lib/${tuple}`), 'lib/libstdFFI.dylib'];
  const files = {};
  for (const relative of names) {
    assert.ok(!/^libcangjie-runtime|^libboundscheck/.test(path.basename(relative)), 'COLOUR_RT_STD_CORE_LIBRARY');
    const source = regular(prefix, relative);
    const dest = path.join(output, relative);
    fs.mkdirSync(path.dirname(dest), {recursive: true});
    fs.copyFileSync(source, dest);
    files[relative] = digest(dest);
  }
  const manifest = {role: 'colour-std', platform, compiler_sha256: compilerSha,
    runtime_manifest_sha256: digest(path.join(runtime, 'manifest.json')),
    producer_sha: process.env.GITHUB_SHA, run_id: process.env.GITHUB_RUN_ID,
    run_attempt: process.env.GITHUB_RUN_ATTEMPT, files};
  assert.match(manifest.producer_sha || '', /^[a-f0-9]{40}$/);
  assert.match(manifest.run_id || '', /^\d+$/);
  assert.match(manifest.run_attempt || '', /^\d+$/);
  fs.writeFileSync(path.join(output, 'std-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  const pin = {manifest_sha256: digest(path.join(output, 'std-manifest.json')),
    compiler_sha256: compilerSha, producer_sha: manifest.producer_sha,
    run_id: manifest.run_id, run_attempt: manifest.run_attempt};
  verifyDarwinStd(output, platform, pin, manifest.runtime_manifest_sha256);
  return pin;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const pin = prepareDarwinStd(...process.argv.slice(2));
  fs.writeFileSync(path.join(process.env.RUNNER_TEMP, 'darwin-std-identity.json'), JSON.stringify(pin, null, 2) + '\n');
}
