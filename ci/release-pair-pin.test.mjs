import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const pins = file => Object.fromEntries(read(file).trim().split('\n').map(line => {
  const i = line.indexOf('=');
  return [line.slice(0, i), line.slice(i + 1)];
}));
const llvm = pins('ci/llvm_pin.env');
const input = JSON.parse(read('ci/bootstrap_inputs_pin.json'));

test('release runtime loader selects the return-poll runtime paired with LLVM', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-pair-'));
  try {
    const output = path.join(dir, 'github-env');
    const env = {...process.env, GITHUB_ENV: output};
    for (const key of ['RUNTIME_REF', 'RUNTIME_SRC_URL', 'CJCJ_RUNTIME_REF_OVERRIDE', 'CJCJ_ALLOW_RUNTIME_OVERRIDE']) delete env[key];
    const result = spawnSync(process.execPath, [new URL('ci/load_runtime_pin.mjs', root).pathname], {env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const selected = /^RUNTIME_REF=(.*)$/m.exec(fs.readFileSync(output, 'utf8'))?.[1];
    assert.equal(selected, 'a891df782f6132909c81afb9ecb4c05a73278d03', 'release runtime must provide the paired return-poll handler');
    console.log(`ASSERT release-runtime-selected=${selected}`);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('release LLVM source and both dylib provenance pins use the return-poll producer', () => {
  assert.equal(llvm.LLVM_SHA, '47af16885ca321ade18fa97dfa00725930685ca0');
  for (const platform of ['linux_x86_64', 'linux_aarch64']) {
    const dylib = pins(`ci/llvm-dylib/${platform}.env`);
    assert.equal(dylib.LLVM_DYLIB_SOURCE_SHA, llvm.LLVM_SHA, platform);
    assert.equal(dylib.LLVM_DYLIB_RUN_ID, llvm.LLVM_TUPLE_RUN_ID, platform);
    assert.equal(dylib.LLVM_DYLIB_RUN_ATTEMPT, llvm.LLVM_TUPLE_RUN_ATTEMPT, platform);
  }
  console.log('ASSERT release-llvm-dylib-pair executed');
});

test('release tuple sums digest equals the reviewed LLVM pin and immutable input', () => {
  const digest = createHash('sha256').update(read('ci/llvm_tuple_SHA256SUMS')).digest('hex');
  assert.equal(llvm.LLVM_TUPLE_SUMS_SHA, digest, 'reviewed tuple checksum pin');
  const sums = input.files.find(file => file.path === 'SHA256SUMS');
  assert.equal(sums.artifact_sha256, digest);
  assert.equal(sums.release_sha256, digest);
  console.log(`ASSERT release-tuple-digest=${digest}`);
});

test('release immutable bootstrap files belong to the selected tuple', () => {
  assert.equal(String(input.run), llvm.LLVM_TUPLE_RUN_ID);
  assert.equal(String(input.attempt), llvm.LLVM_TUPLE_RUN_ATTEMPT);
  assert.equal(String(input.artifact), llvm.LLVM_TUPLE_ARTIFACT_ID);
  const sums = new Map(read('ci/llvm_tuple_SHA256SUMS').trim().split('\n').map(line => {
    const [, digest, file] = /^(\w{64})\s+\*?(.+)$/.exec(line);
    return [file.replace(/^\.\//, ''), digest];
  }));
  for (const file of input.files.filter(file => file.path !== 'SHA256SUMS')) {
    assert.equal(file.artifact_sha256, sums.get(file.path), file.path);
    assert.equal(file.release_sha256, file.artifact_sha256, file.path);
  }
  console.log('ASSERT release-bootstrap-input-pair executed');
});
