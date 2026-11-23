import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {verifyLayout, runtimeLibrary} from '../verify.mjs';
import {checkArchive, packArchive, relocateAndVerify, unpackArchive, writeSums} from '../archive.mjs';
import {makeSdk} from './fixture.mjs';

const V = '1.2.0-test';

test('layout: the three runtime roles pass when the official host runtime differs from ours', () => {
  const {sdk} = makeSdk();
  const facts = verifyLayout(sdk, 'linux-x64');
  assert.equal(facts.tuple, 'linux_x86_64_cjnative');
  assert.notEqual(facts.productSha, facts.hostSha);
});

test('layout: missing .host is refused', () => {
  const {sdk} = makeSdk({host: null});
  assert.throws(() => verifyLayout(sdk, 'linux-x64'), /^Error: SDK_MISSING_HOST_RUNTIME$/);
});

test('layout: a .host with the same bytes as the coloured runtime is refused', () => {
  const {sdk} = makeSdk({host: 'coloured-runtime'});
  assert.throws(() => verifyLayout(sdk, 'linux-x64'), /^Error: SDK_HOST_SAME_BYTES$/);
});

test('layout: .compiler-exec posing as .host is refused', () => {
  const {sdk} = makeSdk({product: 'coloured-runtime', exec: 'exec-runtime', host: 'exec-runtime'});
  assert.throws(() => verifyLayout(sdk, 'linux-x64'), /^Error: SDK_HOST_IS_COMPILER_EXEC$/);
});

test('layout: a wrong tuple is refused (directory and ELF machine)', () => {
  assert.throws(() => verifyLayout(makeSdk({tuple: 'linux_aarch64_cjnative', machine: 183}).sdk, 'linux-x64'), /^Error: SDK_WRONG_TUPLE missing runtime\/lib\/linux_x86_64_cjnative/);
  assert.throws(() => verifyLayout(makeSdk({machine: 183}).sdk, 'linux-x64'), /^Error: SDK_WRONG_TUPLE elf machine 183/);
  const {sdk} = makeSdk();
  fs.mkdirSync(path.join(sdk, 'runtime/lib/linux_ohos_aarch64_cjnative'));
  assert.throws(() => verifyLayout(sdk, 'linux-x64'), /^Error: SDK_WRONG_TUPLE unexpected runtime\/lib\/linux_ohos_aarch64_cjnative/);
});

test('archive: pack, move the original away, unpack fresh and verify there, then restore', async () => {
  const {root, sdk} = makeSdk();
  const out = path.join(root, 'release');
  const archive = packArchive({sdk, asset: 'linux-x64', version: V, output: out});
  assert.equal(archive.name, `cangjie-sdk-linux-x64-${V}.tar.gz`);
  assert.match(writeSums(out, [archive]), new RegExp(`^${archive.sha256}  ${archive.name}\n$`));
  let seenOriginal;
  const {root: unpacked, result} = await relocateAndVerify({file: archive.file, asset: 'linux-x64', version: V, sdk, work: path.join(root, 'relocate'),
    verify: async dir => { seenOriginal = fs.existsSync(sdk); return verifyLayout(dir, 'linux-x64'); }});
  assert.equal(seenOriginal, false, 'original install must be hidden during relocated verification');
  assert.ok(fs.existsSync(sdk), 'original install restored');
  assert.equal(result.productSha, verifyLayout(sdk, 'linux-x64').productSha);
  assert.notEqual(path.resolve(unpacked), path.resolve(sdk));
});

test('archive: corrupted bytes, wrong sha record, truncated archive and wrong asset are refused', () => {
  const {root, sdk} = makeSdk();
  const out = path.join(root, 'release');
  const archive = packArchive({sdk, asset: 'linux-x64', version: V, output: out});
  assert.equal(checkArchive({file: archive.file, asset: 'linux-x64', version: V}), archive.sha256);
  assert.throws(() => checkArchive({file: archive.file, asset: 'linux-x64', version: V, expectedSha256: '0'.repeat(64)}), /^Error: ARCHIVE_SHA_MISMATCH/);
  assert.throws(() => checkArchive({file: archive.file, asset: 'linux-x64-ohos', version: V}), /^Error: ARCHIVE_WRONG_ASSET/);
  const bytes = fs.readFileSync(archive.file); bytes[bytes.length >> 1] ^= 0xff; fs.writeFileSync(archive.file, bytes);
  assert.throws(() => checkArchive({file: archive.file, asset: 'linux-x64', version: V}), /^Error: ARCHIVE_SHA_MISMATCH/);
  fs.writeFileSync(archive.file, bytes.subarray(0, 40));
  assert.throws(() => unpackArchive({file: archive.file, destination: path.join(root, 'u')}), /^Error: ARCHIVE_EXTRACT_FAILED/);
});

test('archive: the original install is restored even when relocated verification fails', async () => {
  const {root, sdk} = makeSdk();
  const archive = packArchive({sdk, asset: 'linux-x64', version: V, output: path.join(root, 'release')});
  await assert.rejects(relocateAndVerify({file: archive.file, asset: 'linux-x64', version: V, sdk, work: path.join(root, 'r'),
    verify: async dir => { fs.rmSync(runtimeLibrary(dir, 'linux_x86_64_cjnative', 'host')); return verifyLayout(dir, 'linux-x64'); }}), /^Error: SDK_MISSING_HOST_RUNTIME$/);
  assert.ok(fs.existsSync(runtimeLibrary(sdk, 'linux_x86_64_cjnative', 'host')));
});
