import {createHash} from 'node:crypto';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';

// Optional integration arm: the tuple and its pin are real immutable release
// inputs; unrelated host/runtime dependencies still use the script fixture.
if (process.env.REAL_BOOTSTRAP_TUPLE_DIR) {
  test('platform tuple consumes real pinned payloads, rejects swapped pin, and restores', () => {
    const target = process.env.REAL_BOOTSTRAP_TARGET;
    const platform = {'linux-x64': 'linux_x86_64', 'linux-aarch64': 'linux_aarch64'}[target];
    assert.ok(platform, 'REAL_BOOTSTRAP_TARGET must select a Linux tuple');
    const pins = JSON.parse(fs.readFileSync(new URL('../bootstrap_inputs_pin.json', import.meta.url)));
    const other = platform === 'linux_x86_64' ? 'linux_aarch64' : 'linux_x86_64';
    const original = JSON.stringify(pins);
    fixture(({env, pinFile, run}) => {
      env.CJCJ_BOOTSTRAP_COLOUR_TUPLE = path.resolve(process.env.REAL_BOOTSTRAP_TUPLE_DIR);
      env.CJCJ_BOOTSTRAP_SOURCE_REASON = 'real immutable tuple integration arm';
      fs.writeFileSync(pinFile, original);
      const checkAccepted = label => {
        const result = run();
        assert.equal(result.status, 0, result.stderr);
        const exported = /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=(.+)$/m.exec(result.stdout)?.[1];
        assert.ok(exported, result.stdout);
        assert.match(fs.readFileSync(path.join(exported, 'MANIFEST'), 'utf8'),
          new RegExp(`^PLATFORM=${platform}$`, 'm'));
        for (const file of pins.platforms[platform].files) {
          assert.equal(createHash('sha256').update(fs.readFileSync(path.join(exported, file.path))).digest('hex'),
            file.release_sha256, file.path);
        }
        console.log(`ASSERT real-tuple ${platform} ${label} rc=${result.status} run=${pins.platforms[platform].run}`);
      };
      checkAccepted('green');
      pins.platforms[platform] = pins.platforms[other];
      fs.writeFileSync(pinFile, JSON.stringify(pins));
      const rejected = run();
      assert.equal(rejected.status, 65, rejected.stderr);
      assert.match(rejected.stderr, new RegExp(`BOOTSTRAP_TUPLE_PLATFORM_MISMATCH expected=${platform} actual=${other}`));
      assert.doesNotMatch(rejected.stdout, /BOOTSTRAP_SOURCE|^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
      console.log(`ASSERT real-tuple ${platform} swapped-pin rc=65 before acquisition`);
      Object.assign(pins, JSON.parse(original));
      fs.writeFileSync(pinFile, original);
      checkAccepted('restored');
    }, target);
  });
}

test('reviewed sums pin rejects altered tuple bytes', () => fixture(({env, fallback, run}) => {
  // Isolate the digest contract from artifact-selection policy.
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  fs.writeFileSync(path.join(fallback, 'SHA256SUMS'), 'altered');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: SHA256SUMS/);
  console.log('ASSERT reviewed-pin rejection executed');
}));

test('explicit tuple fallback remains usable with the same reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED SHA256SUMS/);
  console.log('ASSERT fallback executed');
}));

test('nested kkk2 depot remains a fallback under the same reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  delete env.CJCJ_BOOTSTRAP_COLOUR_TUPLE;
  env.CJCJ_LLVM_DEPOT_ROOT = path.join(path.dirname(fallback), 'depot');
  env.CANGJIE_COMPILER_SHA = 'c'.repeat(40);
  const nested = path.join(env.CJCJ_LLVM_DEPOT_ROOT, env.LLVM_SHA, env.CANGJIE_COMPILER_SHA);
  fs.mkdirSync(nested, {recursive: true});
  for (const file of ['SHA256SUMS', 'MANIFEST']) fs.copyFileSync(path.join(fallback, file), path.join(nested, file));
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED SHA256SUMS/);
  console.log('ASSERT nested-depot fallback executed');
}));


test('prepare defaults to persistent source despite unavailable artifact run', () => fixture(({env, pinFile, run}) => {
  delete env.CJCJ_BOOTSTRAP_SOURCE;
  delete env.CJCJ_BOOTSTRAP_SOURCE_REASON;
  const pin = JSON.parse(fs.readFileSync(pinFile));
  pin.platforms.linux_x86_64.run = 999999999;
  fs.writeFileSync(pinFile, JSON.stringify(pin));
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_SOURCE mode=release/);
  const output = /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=(.+)$/m.exec(result.stdout)?.[1];
  assert.ok(output, result.stdout);
  assert.equal(fs.readFileSync(path.join(output, 'SHA256SUMS'), 'utf8'), 'reviewed fixture sums');
  console.log('ASSERT prepare persistent bytes exported with unavailable artifact run');
}));

test('prepare refuses changed persistent input before exporting bootstrap environment', () => fixture(({env, artifact, run}) => {
  delete env.CJCJ_BOOTSTRAP_SOURCE;
  fs.writeFileSync(path.join(artifact, 'SHA256SUMS'), 'replaced persistent sums');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bootstrap digest mismatch: SHA256SUMS/);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT prepare persistent digest rejection executed');
}));

// Separate assertions make selection and integrity cuts independently visible.
test('ast artifact wins over an available fallback archive', () => fixture(({env, artifact, run}) => {
  const ast = path.join(artifact, 'libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  env.CJCJ_BOOTSTRAP_AST_ARTIFACT = ast;
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT=${ast}\n`));
  console.log('ASSERT ast artifact-precedence executed');
}));

test('ast reviewed pin rejects changed bytes while tuple stays valid', () => fixture(({env, run}) => {
  fs.writeFileSync(env.CJCJ_BOOTSTRAP_AST_SUPPORT, 'wrong archive');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ast-support archive SHA256 disagrees/);
  console.log('ASSERT ast reviewed-pin rejection executed');
}));

test('missing selected ast artifact cannot fall back', () => fixture(({env, artifact, run}) => {
  env.CJCJ_BOOTSTRAP_AST_ARTIFACT = path.join(artifact, 'missing.a');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ENOENT/);
}));

test('kkk2 ast build directory fallback uses the reviewed pin', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_AST_SUPPORT;
  env.CANGJIE_BUILD_ROOT = fallback;
  fs.mkdirSync(path.join(fallback, 'lib'));
  const ast = path.join(fallback, 'lib/libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT=${ast}\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256=${env.AST_SUPPORT_SHA256}\n`));
  console.log('ASSERT ast kkk2 fallback and reviewed digest executed');
}));

// Independent pins: store integrity must not replace the reviewed tuple manifest pin.
test('reviewed tuple manifest pin rejects valid stored bytes from a different tuple', () => fixture(({env, run}) => {
  env.LLVM_TUPLE_SUMS_SHA_linux_x86_64 = 'f'.repeat(64);
  const result = run();
  assert.match(result.stderr, /colour tuple SHA256SUMS disagrees with platform pin/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT independent reviewed tuple manifest pin executed');
}));

for (const target of ['linux-x64', 'linux-aarch64']) {
  test(`platform tuple selects and exports ${target}`, () => fixture(({env, run}) => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
    const output = /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=(.+)$/m.exec(result.stdout)?.[1];
    assert.ok(output, result.stdout);
    const expected = target === 'linux-x64' ? 'linux_x86_64' : 'linux_aarch64';
    assert.equal(fs.readFileSync(path.join(output, 'MANIFEST'), 'utf8'), `PLATFORM=${expected}\n`);
    console.log(`ASSERT tuple-platform-export ${expected}`);
  }, target));
}

test('platform tuple rejects wrong-platform pin with rc 65 before acquisition', () => fixture(({pinFile, run}) => {
  const pins = JSON.parse(fs.readFileSync(pinFile));
  pins.platforms.linux_x86_64.platform = 'linux_aarch64';
  fs.writeFileSync(pinFile, JSON.stringify(pins));
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_MISMATCH expected=linux_x86_64 actual=linux_aarch64/);
  assert.doesNotMatch(result.stdout, /BOOTSTRAP_SOURCE|^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT tuple-platform-pin-mismatch rc=65 before acquisition');
}));

test('platform tuple refuses absent platform instead of selecting x86 pin', () => fixture(({pinFile, run}) => {
  const pins = JSON.parse(fs.readFileSync(pinFile));
  pins.platforms.linux_x86_64 = pins.platforms.linux_aarch64;
  delete pins.platforms.linux_aarch64;
  fs.writeFileSync(pinFile, JSON.stringify(pins));
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_PIN_MISSING expected=linux_aarch64/);
  assert.doesNotMatch(result.stdout, /BOOTSTRAP_SOURCE/);
  console.log('ASSERT tuple-platform-missing rc=65 no fallback');
}, 'linux-aarch64'));

test('platform tuple rejects digest-valid wrong-platform manifest with rc 65', () => fixture(({pinFile, fallback, run}) => {
  const pins = JSON.parse(fs.readFileSync(pinFile));
  const manifest = 'PLATFORM=linux_aarch64\n';
  fs.writeFileSync(path.join(fallback, 'MANIFEST'), manifest);
  const file = pins.platforms.linux_x86_64.files.find(file => file.path === 'MANIFEST');
  file.artifact_sha256 = file.release_sha256 = createHash('sha256').update(manifest).digest('hex');
  fs.writeFileSync(pinFile, JSON.stringify(pins));
  const result = run();
  assert.equal(result.status, 65, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED MANIFEST/);
  assert.match(result.stderr, /BOOTSTRAP_TUPLE_PLATFORM_MISMATCH expected=linux_x86_64 actual=linux_aarch64/);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT tuple-platform-manifest-mismatch rc=65 after digest verification');
}));
