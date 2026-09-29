import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {digest} from './bootstrap_store.mjs';

function fixture(check, platform = 'linux_x86_64') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fixed-acquire-'));
  try {
    // Use the repository's actual platform set and provenance shape, replacing
    // payload identities only in this isolated transport fixture.
    const pins = JSON.parse(fs.readFileSync(new URL('../bootstrap_inputs_pin.json', import.meta.url)));
    const pin = pins.platforms[platform];
    const payloads = {'MANIFEST': `PLATFORM=${platform}\n`, 'bin/llc': `native fixture ${platform}\n`};
    const reseal = () => {
      payloads.SHA256SUMS = ['MANIFEST', 'bin/llc'].map(name => `${digest(payloads[name])}  ${name}\n`).join('');
      pin.tuple_sums_sha256 = digest(payloads.SHA256SUMS);
      pin.files = Object.entries(payloads).map(([name, bytes], i) => ({path: name, mode: name === 'bin/llc' ? 0o755 : 0o644,
        asset: 100 + i, artifact_sha256: digest(bytes), release_sha256: digest(bytes)}));
    };
    reseal();
    const pinFile = path.join(dir, 'pin.json');
    const transport = path.join(dir, 'transport.mjs');
    const sourceFile = path.join(dir, 'transport.json');
    const destination = path.join(dir, 'out');
    fs.writeFileSync(transport, `import fs from 'node:fs';
      const sources = JSON.parse(fs.readFileSync(process.env.FIXED_TRANSPORT));
      globalThis.fetch = async url => {
        console.log('FIXTURE_RELEASE_REQUEST ' + url);
        if (!(url in sources)) throw new Error('unexpected release request: ' + url);
        return new Response(sources[url]);
      };`);
    const run = (sums = pin.tuple_sums_sha256) => {
      fs.writeFileSync(pinFile, JSON.stringify(pins));
      fs.writeFileSync(sourceFile, JSON.stringify(Object.fromEntries(pin.files.map(file =>
        [`https://api.github.com/repos/${pin.repository}/releases/assets/${file.asset}`, payloads[file.path]]))));
      return spawnSync(process.execPath, ['--import', transport,
        new URL('./acquire_fixed_tuple.mjs', import.meta.url).pathname, pinFile, destination, sums, platform],
      {env: {...process.env, FIXED_TRANSPORT: sourceFile}, encoding: 'utf8'});
    };
    check({pins, pin, payloads, reseal, run, destination});
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

for (const platform of ['linux_x86_64', 'linux_aarch64']) {
  test(`fixed release CLI publishes selected ${platform} bytes`, () => fixture(({run, destination, payloads}) => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(path.join(destination, 'MANIFEST'), 'utf8'), payloads.MANIFEST);
    assert.equal(fs.readFileSync(path.join(destination, 'bin/llc'), 'utf8'), payloads['bin/llc']);
    assert.match(result.stdout, /FIXED_LLVM_RELEASE_VERIFIED/);
    console.log(`ASSERT fixed-release-platform ${platform} rc=0 verified bytes`);
  }, platform));
}

test('fixed release CLI rejects wrong-platform pin before download', () => fixture(({pin, run, destination}) => {
  pin.platform = 'linux_aarch64';
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_MISMATCH expected=linux_x86_64 actual=linux_aarch64/);
  assert.doesNotMatch(result.stdout, /BOOTSTRAP_SOURCE|FIXTURE_RELEASE_REQUEST|FIXED_LLVM_RELEASE_VERIFIED/);
  assert.equal(fs.existsSync(destination), false);
  console.log('ASSERT fixed-release-pin-mismatch rc=65 before download');
}));

test('fixed release CLI rejects missing platform without fallback', () => fixture(({pins, run}) => {
  delete pins.platforms.linux_x86_64;
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_PIN_MISSING/);
  assert.doesNotMatch(result.stdout, /BOOTSTRAP_SOURCE/);
}));

test('fixed release CLI rejects digest-valid foreign MANIFEST before publication', () => fixture(({payloads, reseal, run, destination}) => {
  payloads.MANIFEST = 'PLATFORM=linux_aarch64\n';
  reseal();
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED MANIFEST/);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_MISMATCH expected=linux_x86_64 actual=linux_aarch64/);
  assert.equal(fs.existsSync(destination), false);
  console.log('ASSERT fixed-release-manifest-mismatch rc=65 before publication');
}));

test('fixed release CLI preserves independent sums pin and existing destination on rejection', () => fixture(({run, destination}) => {
  fs.mkdirSync(destination);
  fs.writeFileSync(path.join(destination, 'sentinel'), 'previous tuple');
  const result = run('f'.repeat(64));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: LLVM_TUPLE_SUMS_SHA/);
  assert.equal(fs.readFileSync(path.join(destination, 'sentinel'), 'utf8'), 'previous tuple');
}));

test('fixed release CLI preserves asset digest verification', () => fixture(({payloads, run, destination}) => {
  payloads['bin/llc'] = 'changed bytes';
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: bin\/llc/);
  assert.equal(fs.existsSync(destination), false);
}));

test('fixed release CLI checks the selected platform sums pin', () => fixture(({pin, run, destination}) => {
  const reviewed = pin.tuple_sums_sha256;
  pin.tuple_sums_sha256 = 'f'.repeat(64);
  const result = run(reviewed);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: platform tuple_sums_sha256/);
  assert.equal(fs.existsSync(destination), false);
}));

if (process.env.REAL_BOOTSTRAP_TUPLE_DIR) {
  test('fixed release CLI consumes real platform asset bytes and rejects foreign pin then restores', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fixed-real-'));
    try {
      const platform = {'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64'}[process.env.REAL_BOOTSTRAP_TARGET];
      assert.ok(platform, 'REAL_BOOTSTRAP_TARGET must name the supplied native tuple');
      const pins = JSON.parse(fs.readFileSync(new URL('../bootstrap_inputs_pin.json', import.meta.url)));
      const pin = pins.platforms[platform];
      const pinFile = path.join(dir, 'pin.json');
      const transport = path.join(dir, 'transport.mjs');
      const sources = Object.fromEntries(pin.files.map(file => [
        `https://api.github.com/repos/${pin.repository}/releases/assets/${file.asset}`,
        path.resolve(process.env.REAL_BOOTSTRAP_TUPLE_DIR, file.path)]));
      fs.writeFileSync(transport, `import fs from 'node:fs';
        const sources = ${JSON.stringify(sources)};
        globalThis.fetch = async url => {
          if (!(url in sources)) throw new Error('unexpected release request: ' + url);
          return new Response(fs.readFileSync(sources[url]));
        };`);
      const run = name => spawnSync(process.execPath, ['--import', transport,
        new URL('./acquire_fixed_tuple.mjs', import.meta.url).pathname, pinFile,
        path.join(dir, name), pin.tuple_sums_sha256, platform], {encoding: 'utf8'});
      for (const arm of ['candidate', 'wrong-pin', 'restored']) {
        const input = structuredClone(pins);
        if (arm === 'wrong-pin') input.platforms[platform] = pins.platforms[
          platform === 'linux_x86_64' ? 'linux_aarch64' : 'linux_x86_64'];
        fs.writeFileSync(pinFile, JSON.stringify(input));
        const result = run(arm);
        assert.equal(result.status, arm === 'wrong-pin' ? 65 : 0, result.stderr);
        if (arm === 'wrong-pin') {
          assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_MISMATCH/);
          assert.equal(fs.existsSync(path.join(dir, arm)), false);
        } else {
          for (const file of pin.files) assert.equal(digest(fs.readFileSync(path.join(dir, arm, file.path))), file.release_sha256);
        }
        console.log(`ASSERT fixed-real ${platform} arm=${arm} rc=${result.status} files=${arm === 'wrong-pin' ? 0 : pin.files.length}`);
      }
    } finally { fs.rmSync(dir, {recursive: true, force: true}); }
  });
}
