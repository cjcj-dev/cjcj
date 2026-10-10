import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fixture} from './prepare_bootstrap_fixture.mjs';

function repackSdk(env, dir) {
  const packed = spawnSync('tar', ['-czf', env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE,
    '-C', path.join(dir, 'official'), 'cangjie'], {encoding: 'utf8'});
  assert.equal(packed.status, 0, packed.stderr);
  const digest = crypto.createHash('sha256').update(fs.readFileSync(env.CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE)).digest('hex');
  const identities = fs.readFileSync(env.STAGE1_HOST_IDENTITIES, 'utf8').replace(
    /^# HOST_SDK_PROVENANCE (.+)$/m, (_line, json) =>
      `# HOST_SDK_PROVENANCE ${JSON.stringify({...JSON.parse(json), sha256: digest})}`);
  fs.writeFileSync(env.STAGE1_HOST_IDENTITIES, identities);
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

test('explicit depot layout does not determine input identity', () => fixture(({env, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT;
  delete env.CJCJ_BOOTSTRAP_COLOUR_TUPLE;
  env.CJCJ_LLVM_DEPOT_ROOT = path.join(path.dirname(fallback), 'depot');
  env.CANGJIE_COMPILER_SHA = 'c'.repeat(40);
  const nested = path.join(env.CJCJ_LLVM_DEPOT_ROOT, env.LLVM_SHA, env.CANGJIE_COMPILER_SHA);
  env.CJCJ_BOOTSTRAP_COLOUR_TUPLE = nested;
  fs.mkdirSync(nested, {recursive: true});
  fs.cpSync(fallback, nested, {recursive: true});
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /BOOTSTRAP_VERIFIED SHA256SUMS/);
  console.log('ASSERT nested-depot fallback executed');
}));


test('prepare defaults to persistent source despite unavailable artifact run', () => fixture(({env, pinFile, run}) => {
  delete env.CJCJ_BOOTSTRAP_SOURCE;
  delete env.CJCJ_BOOTSTRAP_SOURCE_REASON;
  const pin = JSON.parse(fs.readFileSync(pinFile));
  pin.run = 999999999;
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
test('ast artifact wins over an available fallback archive', () => fixture(({env, artifact, run, sdk, astFiles}) => {
  const astRoot = path.join(artifact, 'ast-inputs');
  fs.mkdirSync(astRoot);
  const ast = path.join(astRoot, 'libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  for (const name of ['SHA256SUMS', ...astFiles]) {
    fs.mkdirSync(path.dirname(path.join(astRoot, name)), {recursive: true});
    fs.copyFileSync(path.join(sdk, name), path.join(astRoot, name));
  }
  fs.writeFileSync(path.join(astRoot, 'SHA256SUMS'), fs.readFileSync(path.join(sdk, 'SHA256SUMS'), 'utf8').replace('  ast.a', '  libcangjie-ast-support.a'));
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

test('kkk2 complete ast build directory fallback uses the reviewed pin', () => fixture(({env, fallback, run, sdk, astFiles}) => {
  delete env.CJCJ_BOOTSTRAP_AST_SUPPORT;
  env.CANGJIE_BUILD_ROOT = fallback;
  fs.mkdirSync(path.join(fallback, 'lib'));
  const ast = path.join(fallback, 'lib/libcangjie-ast-support.a');
  fs.writeFileSync(ast, 'ast fixture');
  for (const name of ['SHA256SUMS', ...astFiles]) {
    fs.mkdirSync(path.dirname(path.join(fallback, 'lib', name)), {recursive: true});
    fs.copyFileSync(path.join(sdk, name), path.join(fallback, 'lib', name));
  }
  fs.writeFileSync(path.join(fallback, 'lib/SHA256SUMS'), fs.readFileSync(path.join(sdk, 'SHA256SUMS'), 'utf8').replace('  ast.a', '  libcangjie-ast-support.a'));
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT=${ast}\n`));
  assert.ok(result.stdout.includes(`CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256=${env.AST_SUPPORT_SHA256}\n`));
  console.log('ASSERT ast kkk2 fallback and reviewed digest executed');
}));

test('explicit bare ast archive is rejected before bootstrap export', () => fixture(({env, sdk, run}) => {
  fs.unlinkSync(path.join(sdk, 'SHA256SUMS'));
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /AST_SUPPORT_INPUTS_INCOMPLETE/);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_AST_SUPPORT=/m);
  console.log('ASSERT incomplete explicit AST input rejected before export');
}));

for (const name of ['include/cangjie', 'include/flatbuffers/StdAstFormat_generated.h',
  'schema/StdAstFormat.fbs', 'third_party/flatbuffers/bin/flatc', 'third_party/flatbuffers/include',
  'third_party/flatbuffers/cangjie', 'third_party/flatbuffers/modules']) {
  test(`explicit AST input missing ${name} is rejected before export`, () => fixture(({sdk, run}) => {
    fs.rmSync(path.join(sdk, name), {recursive: true});
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /AST_SUPPORT_INPUTS_INCOMPLETE/);
    assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_AST_SUPPORT=/m);
    console.log(`ASSERT incomplete explicit AST input rejected: ${name}`);
  }));
}

test('complete SDK library directory fallback uses the reviewed pin', () => fixture(({env, dir, sdk, astFiles, run}) => {
  delete env.CJCJ_BOOTSTRAP_AST_SUPPORT;
  delete env.CJCJ_BOOTSTRAP_AST_ARTIFACT;
  env.CANGJIE_BUILD_ROOT = path.join(dir, 'empty-build');
  const root = path.join(dir, 'official/cangjie/lib/ast-inputs');
  fs.mkdirSync(root, {recursive: true});
  fs.writeFileSync(path.join(root, 'libcangjie-ast-support.a'), 'ast fixture');
  for (const name of astFiles) {
    fs.mkdirSync(path.dirname(path.join(root, name)), {recursive: true});
    fs.copyFileSync(path.join(sdk, name), path.join(root, name));
  }
  fs.writeFileSync(path.join(root, 'SHA256SUMS'), fs.readFileSync(path.join(sdk, 'SHA256SUMS'), 'utf8').replace('  ast.a', '  libcangjie-ast-support.a'));
  repackSdk(env, dir);
  const result = run();
  const selected = /^CJCJ_BOOTSTRAP_AST_SUPPORT=(.+)$/m.exec(result.stdout)?.[1];
  assert.equal(result.status, 0, result.stderr);
  assert.ok(selected?.endsWith('/lib/ast-inputs/libcangjie-ast-support.a'), result.stdout);
  assert.deepEqual(fs.readFileSync(selected), fs.readFileSync(path.join(root, 'libcangjie-ast-support.a')));
  console.log('ASSERT complete SDK library AST input selected with reviewed pin');
}));

for (const location of ['build', 'SDK']) {
test(`bare ${location} archive selects complete downloaded AST inputs consumed by installer`, () => fixture(({env, dir, sdk, astFiles, fallback, run}) => {
  delete env.CJCJ_BOOTSTRAP_AST_SUPPORT;
  delete env.CJCJ_BOOTSTRAP_AST_ARTIFACT;
  env.CANGJIE_BUILD_ROOT = fallback;
  const libraryDir = location === 'build' ? path.join(fallback, 'lib') : path.join(dir, 'official/cangjie/lib');
  fs.mkdirSync(libraryDir, {recursive: true});
  const bare = path.join(libraryDir, 'libcangjie-ast-support.a');
  fs.writeFileSync(bare, 'ast fixture');
  if (location === 'SDK') repackSdk(env, dir);
  const payload = path.join(dir, 'ast-payload');
  fs.mkdirSync(payload);
  fs.copyFileSync(bare, path.join(payload, 'libcangjie-ast-support.a'));
  for (const name of astFiles) {
    fs.mkdirSync(path.dirname(path.join(payload, name)), {recursive: true});
    fs.copyFileSync(path.join(sdk, name), path.join(payload, name));
  }
  fs.writeFileSync(path.join(payload, 'SHA256SUMS'), fs.readFileSync(path.join(sdk, 'SHA256SUMS'), 'utf8').replace('  ast.a', '  libcangjie-ast-support.a'));
  const archive = path.join(dir, 'ast.zip');
  const zip = spawnSync('zip', ['-qr', archive, '.'], {cwd: payload, encoding: 'utf8'});
  assert.equal(zip.status, 0, zip.stderr);
  const bin = path.join(dir, 'transport-bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'gh'), '#!/bin/sh\n[ "$1" = api ] && [ "$2" = "repos/cjcj-dev/cjcj/releases/assets/789" ] || exit 91\ncat "$AST_TEST_ZIP"\n', {mode: 0o755});
  env.PATH = `${bin}:${env.PATH}`;
  env.AST_TEST_ZIP = archive;
  env.AST_SUPPORT_ARTIFACT_ID = '456';
  env.BOOTSTRAP_ARCHIVES_PIN = path.join(dir, 'archive-pin.json');
  fs.writeFileSync(env.BOOTSTRAP_ARCHIVES_PIN, JSON.stringify({version: 1, artifacts: {
    [env.AST_SUPPORT_ARTIFACT_ID]: {repository: 'cjcj-dev/cjcj', asset: 789, prerelease: true,
      release_sha256: crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex')},
  }}));
  const result = run();
  const selected = /^CJCJ_BOOTSTRAP_AST_SUPPORT=(.+)$/m.exec(result.stdout)?.[1];
  assert.equal(selected?.includes('/ast_support-') ?? false, true, 'bare archive must not be exported as SDK input');
  assert.equal(result.status, 0, result.stderr);
  assert.ok(selected, result.stdout);
  const dest = path.join(dir, 'installed-sdk');
  const installed = spawnSync('python3', [new URL('../install_std_sdk_inputs.py', import.meta.url).pathname,
    path.dirname(selected), dest, 'linux_x86_64_cjnative'], {encoding: 'utf8'});
  assert.equal(installed.status, 0, installed.stderr);
  for (const name of [...astFiles, 'lib/linux_x86_64_cjnative/libcangjie-ast-support.a']) {
    const source = name.startsWith('lib/') ? bare : path.join(payload, name);
    assert.deepEqual(fs.existsSync(path.join(dest, name)) ? fs.readFileSync(path.join(dest, name)) : undefined,
      fs.readFileSync(source), `installed producer bytes: ${name}`);
  }
  console.log('ASSERT downloaded AST selection and installer payload bytes executed');
}));
}

// Independent pins: store integrity must not replace the reviewed tuple manifest pin.
test('reviewed tuple manifest pin rejects valid stored bytes from a different tuple', () => fixture(({env, run}) => {
  env.LLVM_TUPLE_SUMS_SHA = 'f'.repeat(64);
  const result = run();
  assert.match(result.stderr, /colour tuple SHA256SUMS disagrees with ci\/llvm_pin.env/);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /^CJCJ_BOOTSTRAP_COLOUR_TUPLE=/m);
  console.log('ASSERT independent reviewed tuple manifest pin executed');
}));
