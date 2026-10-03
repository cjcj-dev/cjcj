import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fixture} from './prepare_bootstrap_fixture.mjs';
import {digest, runtimeFiles, prepareRuntime} from './colour_runtime.mjs';

function localRuntime(env, runtime, runtimeSource) {
  const original = JSON.parse(fs.readFileSync(path.join(runtime, 'manifest.json'), 'utf8'));
  const library = path.join(runtimeSource, runtimeFiles[0]);
  fs.appendFileSync(library, `\nCJRT-COMMIT:${env.RUNTIME_REF}\n`);
  const installed = Object.fromEntries(Object.keys(original.files).map(rel =>
    [rel, digest(path.join(runtimeSource, rel))]));
  fs.writeFileSync(path.join(runtimeSource, 'BUILD-INPUTS.json'), JSON.stringify({
    sourceCommit: env.RUNTIME_REF, installed}));
  env.CJCJ_BOOTSTRAP_RUNTIME_SOURCE = 'local-sharedbuild';
  env.CJCJ_BOOTSTRAP_LOCAL_RUN = 'sym_cjcj_135_fixture';
  env.GITHUB_ACTIONS = 'false';
  prepareRuntime(runtimeSource, runtime, env);
  env.COLOUR_RT_MANIFEST_SHA256 = digest(path.join(runtime, 'manifest.json'));
}

test('explicit local sharedbuild root reaches the unified bootstrap consumer', () => fixture(({env, runtime, runtimeSource, run}) => {
  localRuntime(env, runtime, runtimeSource);
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /COLOUR_RT_VERIFIED run=local:sym_cjcj_135_fixture artifact=local-sharedbuild/);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_RT=${runtime}\n`));
  console.log('ASSERT local sharedbuild root exported by real input entry');
}));

for (const scenario of ['payload', 'undeclared', 'publication', 'stamp', 'source']) {
  test(`local sharedbuild rejects ${scenario} at its identity assertion`, () => fixture(({env, runtime, runtimeSource, run}) => {
    localRuntime(env, runtime, runtimeSource);
    let expected;
    if (scenario === 'payload') {
      fs.appendFileSync(path.join(runtime, runtimeFiles[1]), 'changed');
      expected = /COLOUR_RT_FILE_SHA256_MISMATCH/;
    } else if (scenario === 'undeclared') {
      delete env.CJCJ_BOOTSTRAP_RUNTIME_SOURCE;
      expected = /COLOUR_RT_LOCAL_SOURCE_UNDECLARED/;
    } else if (scenario === 'publication') {
      env.GITHUB_ACTIONS = 'true';
      expected = /COLOUR_RT_LOCAL_PUBLICATION_FORBIDDEN/;
    } else if (scenario === 'stamp') {
      const manifestFile = path.join(runtime, 'manifest.json');
      const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
      const library = path.join(runtime, runtimeFiles[0]);
      fs.appendFileSync(library, `\nCJRT-COMMIT:${'a'.repeat(40)}\n`);
      manifest.files[runtimeFiles[0]] = digest(library);
      fs.writeFileSync(manifestFile, JSON.stringify(manifest));
      env.COLOUR_RT_MANIFEST_SHA256 = digest(manifestFile);
      expected = /COLOUR_RT_LOCAL_STAMP_MISMATCH/;
    } else {
      env.RUNTIME_REF = 'e'.repeat(40);
      env.CJCJ_RUNTIME_REF_OVERRIDE = env.RUNTIME_REF;
      expected = /COLOUR_RT_MANIFEST_MISMATCH/;
    }
    const result = run();
    assert.match(result.stderr, expected);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stdout, /CJCJ_BOOTSTRAP_COLOUR_RT=/);
    console.log(`ASSERT local ${scenario} identity rejection executed`);
  }));
}

test('runtime pair reaches bootstrap with explicit identity and host remains separate', () => fixture(({env, runtime, runtimeSource, run}) => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /COLOUR_RT_VERIFIED run=123 artifact=456/);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_COLOUR_RT=${runtime}\n`));
  const base = /^CJCJ_BOOTSTRAP_BASE=(.+)$/m.exec(result.stdout)?.[1];
  assert.notEqual(base, env.CJCJ_SRCBUILD_HOST_SDK);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_HOST_RT=${base}\n`));
  for (const rel of runtimeFiles) {
    assert.equal(digest(path.join(runtime, rel)), digest(path.join(runtimeSource, rel)));
    assert.equal(fs.lstatSync(path.join(runtime, rel)).isFile(), true);
  }
  console.log('ASSERT runtime producer bytes and consumer identity executed');
}));

test('runtime pin tampering fails only runtime identity assertion', () => fixture(({env, run}) => {
  env.COLOUR_RT_MANIFEST_SHA256 = '0'.repeat(64);
  const result = run();
  assert.match(result.stderr, /COLOUR_RT_SHA256_MISMATCH expected=0{64} actual=[a-f0-9]{64}/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stderr, /LLVM_DYLIB_|ast-support|SHA256SUMS disagrees/);
  assert.doesNotMatch(result.stdout, /CJCJ_BOOTSTRAP_COLOUR_RT=/);
  console.log('ASSERT runtime digest rejection executed');
}));

test('missing colour runtime cannot fall back to the available host SDK', () => fixture(({env, run}) => {
  env.CJCJ_BOOTSTRAP_COLOUR_RT += '-missing';
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ENOENT/);
}));

for (const field of ['COLOUR_RT_RUN_ID', 'COLOUR_RT_RUN_ATTEMPT', 'RUNTIME_REF']) {
  test(`runtime manifest binds ${field}`, () => fixture(({env, run}) => {
    env[field] = field === 'RUNTIME_REF' ? 'e'.repeat(40) : '999';
    // Keep selection authorized so this arm reaches the manifest guard.
    if (field === 'RUNTIME_REF') env.CJCJ_RUNTIME_REF_OVERRIDE = env[field];
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_MANIFEST_MISMATCH/);
  }));
}
for (const rel of runtimeFiles) {
  test(`runtime payload digest binds ${rel}`, () => fixture(({runtime, run}) => {
    fs.appendFileSync(path.join(runtime, rel), 'changed');
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_FILE_SHA256_MISMATCH/);
  }));
}

for (const rel of ['lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so', 'lib/libstdFFI.so', 'modules/linux_x86_64_cjnative/std.core.cjo']) {
  test(`new std producer and consumer bind ${rel}`, () => fixture(({runtime, runtimeSource, run}) => {
    assert.equal(fs.readFileSync(path.join(runtime, rel), 'utf8'), fs.readFileSync(path.join(runtimeSource, rel), 'utf8'));
    assert.equal(run().status, 0);
    fs.appendFileSync(path.join(runtime, rel), 'changed std');
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /COLOUR_RT_FILE_SHA256_MISMATCH/);
    console.log(`ASSERT new std bytes copied and checked ${rel}`);
  }));
}

for (const scenario of ['publication', 'source', 'stamp', 'payload', 'stdlib', 'module']) {
  test(`local producer rejects ${scenario} before publishing its receipt`, () => fixture(({env, runtime, runtimeSource, run}) => {
    localRuntime(env, runtime, runtimeSource);
    const output = path.join(path.dirname(runtime), `producer-${scenario}`);
    fs.mkdirSync(output);
    let expected;
    if (scenario === 'publication') {
      env.GITHUB_ACTIONS = 'true';
      expected = /COLOUR_RT_LOCAL_PUBLICATION_FORBIDDEN/;
    } else if (scenario === 'source') {
      env.RUNTIME_REF = 'e'.repeat(40);
      expected = /COLOUR_RT_SOURCE_MISMATCH/;
    } else if (scenario === 'stamp') {
      const file = path.join(runtimeSource, runtimeFiles[0]);
      fs.appendFileSync(file, `\nCJRT-COMMIT:${'a'.repeat(40)}\n`);
      const receipt = path.join(runtimeSource, 'BUILD-INPUTS.json');
      const build = JSON.parse(fs.readFileSync(receipt, 'utf8'));
      build.installed[runtimeFiles[0]] = digest(file);
      fs.writeFileSync(receipt, JSON.stringify(build));
      expected = /COLOUR_RT_LOCAL_STAMP_MISMATCH/;
    } else if (scenario === 'payload') {
      fs.appendFileSync(path.join(runtimeSource, runtimeFiles[1]), 'changed');
      expected = /COLOUR_RT_BUILD_PRODUCTS_MISMATCH/;
    } else if (scenario === 'stdlib') {
      fs.rmSync(path.join(runtimeSource, 'lib/linux_x86_64_cjnative/libcangjie-std-core.a'));
      expected = /COLOUR_RT_STD_MISSING/;
    } else {
      fs.rmSync(path.join(runtimeSource, 'modules/linux_x86_64_cjnative/std.core.cjo'));
      expected = /COLOUR_RT_MODULES_MISSING/;
    }
    assert.throws(() => prepareRuntime(runtimeSource, output, env), expected);
    assert.equal(fs.existsSync(path.join(output, 'manifest.json')), false);
    console.log(`ASSERT local producer ${scenario} rejection executed`);
  }));
}
