import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {digest} from './bootstrap_store.mjs';

// Only the remote transport is substituted. The CLI, release selection,
// digest verification, extraction and consumer bytes are the production path.
function fixture(fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'persistent-archive-'));
  try {
    const payload = path.join(root, 'payload'); fs.mkdirSync(payload);
    fs.writeFileSync(path.join(payload, 'manifest.json'), 'reviewed producer bytes');
    const zip = path.join(root, 'original.zip');
    assert.equal(spawnSync('zip', ['-q', zip, 'manifest.json'], {cwd: payload}).status, 0);
    const bin = path.join(root, 'bin'); fs.mkdirSync(bin);
    const trace = path.join(root, 'commands');
    const realUnzip = spawnSync('which', ['unzip'], {encoding: 'utf8'}).stdout.trim();
    for (const command of ['gh', 'unzip']) {
      const shim = path.join(bin, `${command}.mjs`);
      fs.writeFileSync(shim, `#!/usr/bin/env node
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
fs.appendFileSync(process.env.TEST_COMMANDS, ${JSON.stringify(command + '\n')});
${command === 'gh' ? `
if (JSON.stringify(process.argv.slice(2)) !== JSON.stringify(['api', 'repos/cjcj-dev/cjcj/releases/assets/789', '-H', 'Accept: application/octet-stream'])) process.exit(91);
process.stdout.write(fs.readFileSync(process.env.TEST_ARCHIVE));` : `
const result = spawnSync(${JSON.stringify(realUnzip)}, process.argv.slice(2), {stdio: 'inherit'});
if (result.error) throw result.error;
process.exit(result.status);`}
`, {mode: 0o755});
      fs.symlinkSync(`${command}.mjs`, path.join(bin, command));
    }
    const pinFile = path.join(root, 'pin.json');
    const pin = {version: 1, artifacts: {456: {repository: 'cjcj-dev/cjcj', asset: 789,
      prerelease: true, release_sha256: digest(fs.readFileSync(zip))}}};
    const save = () => fs.writeFileSync(pinFile, JSON.stringify(pin)); save();
    const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_ARCHIVE: zip,
      TEST_COMMANDS: trace, BOOTSTRAP_ARCHIVES_PIN: pinFile};
    const run = (entry = 'cli', localArchive) => {
      fs.writeFileSync(trace, '');
      const destination = path.join(root, `out-${Math.random()}`);
      const args = entry === 'cli' ? [new URL('./download_pinned.mjs', import.meta.url).pathname,
        ...(localArchive === undefined ? [] : ['--archive', localArchive]),
        'cjcj-dev/cjcj', '456', destination] : ['--input-type=module', '-e',
        `import {bootstrapArtifact} from ${JSON.stringify(new URL('./bootstrap_artifact.mjs', import.meta.url).href)}; import fs from 'node:fs'; const result=bootstrapArtifact(undefined,'cjcj-dev/cjcj',456,${JSON.stringify(destination)},'AST_SUPPORT'); console.log('CONSUMER='+fs.readFileSync(result+'/manifest.json','utf8'));`];
      const result = spawnSync(process.execPath, args, {env, encoding: 'utf8'});
      return {destination, ...result, commands: fs.readFileSync(trace, 'utf8').trim().split('\n').filter(Boolean)};
    };
    fn({root, pin, save, zip, run, env});
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
}
for (const entry of ['cli', 'bootstrap']) {
  test(`${entry}: persistent producer bytes reach the consumer`, () => fixture(({run}) => {
    const result = run(entry);
    const file = path.join(result.destination, 'manifest.json');
    const observed = {rc: result.status, bytes: entry === 'cli'
      ? (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null)
      : (/CONSUMER=(.*)/.exec(result.stdout)?.[1] ?? null)};
    console.log(`TARGET ${entry} acceptance ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {rc: 0, bytes: 'reviewed producer bytes'},
      'verified producer bytes must reach consumer');
    assert.match(result.stdout, /PERSISTENT_ARCHIVE_VERIFIED artifact=456 asset=789 sha256=[a-f0-9]{64}/);
    console.log(`ASSERT ${entry} verified producer bytes reached consumer`);
  }));
  test(`${entry}: tampered sha256 pin rejects before extraction; restored pin passes`, () => fixture(({pin, save, run}) => {
    const original = pin.artifacts[456].release_sha256;
    pin.artifacts[456].release_sha256 = 'f'.repeat(64); save();
    const rejected = run(entry);
    console.log(`TARGET ${entry} pin rejection rc=${rejected.status}`);
    assert.notEqual(rejected.status, 0, 'tampered sha256 must reject');
    assert.match(rejected.stderr, /bootstrap digest mismatch: artifact-456.zip/);
    if (entry === 'cli') assert.deepEqual(fs.readdirSync(rejected.destination), []);
    console.log(`ASSERT ${entry} tampered pin rejected at target digest`);
    pin.artifacts[456].release_sha256 = original; save();
    const restored = run(entry);
    assert.equal(restored.status, 0, restored.stderr);
    console.log(`ASSERT ${entry} restored pin accepted`);
  }));
  test(`${entry}: tampered asset bytes reject at the reviewed sha256`, () => fixture(({zip, run}) => {
    fs.appendFileSync(zip, 'changed producer bytes');
    const result = run(entry);
    console.log(`TARGET ${entry} asset rejection rc=${result.status}`);
    assert.notEqual(result.status, 0, 'tampered asset must reject');
    assert.match(result.stderr, /bootstrap digest mismatch: artifact-456.zip/);
    console.log(`ASSERT ${entry} corrupted producer rejected at target digest`);
  }));
}
test('missing persistent pin refuses artifact fallback', () => fixture(({pin, save, run}) => {
  delete pin.artifacts[456]; save();
  const result = run('bootstrap');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PERSISTENT_ARCHIVE_PIN_MISSING artifact=456/);
}));

test('local archive: verified read-only bytes reach the real extraction consumer without network', () => fixture(({zip, run}) => {
  fs.chmodSync(zip, 0o444);
  const before = fs.readFileSync(zip);
  const result = run('cli', zip);
  const file = path.join(result.destination, 'manifest.json');
  const observed = {rc: result.status, commands: result.commands,
    bytes: fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null};
  console.log(`TARGET cache acceptance ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rc: 0, commands: ['unzip'], bytes: 'reviewed producer bytes'},
    'verified local archive must reach consumer without network');
  assert.match(result.stdout, /PERSISTENT_ARCHIVE_VERIFIED .*source=local-archive path=/);
  assert.doesNotMatch(result.stdout, /PERSISTENT_ARCHIVE_DOWNLOAD|source=network/);
  assert.deepEqual(fs.readFileSync(zip), before);
  assert.equal(fs.statSync(zip).mode & 0o777, 0o444);
  console.log('ASSERT cache acceptance verified source unchanged');
}));

test('local archive: wrong digest rejects before unzip or network at the target assertion', () => fixture(({zip, run}) => {
  fs.appendFileSync(zip, 'corrupted cache');
  const result = run('cli', zip);
  const observed = {rejected: result.status !== 0, commands: result.commands,
    extracted: fs.readdirSync(result.destination)};
  console.log(`TARGET cache digest rejection rc=${result.status} ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rejected: true, commands: [], extracted: []},
    'wrong cache digest must reject before extraction and network');
  assert.match(result.stderr, /bootstrap digest mismatch: artifact-456.zip/);
  console.log('ASSERT cache digest rejection reached');
}));

for (const input of ['missing', 'directory', 'empty']) {
  test(`local archive: ${input} path refuses network fallback and extraction`, () => fixture(({root, run}) => {
    const archive = input === 'missing' ? path.join(root, 'absent.zip') : input === 'directory' ? root : '';
    const result = run('cli', archive);
    const observed = {rejected: result.status !== 0, commands: result.commands};
    console.log(`TARGET cache ${input} rejection rc=${result.status} ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {rejected: true, commands: []}, `${input} cache path must fail closed`);
    assert.match(result.stderr, input === 'missing' ? /ENOENT/ : input === 'directory'
      ? /PERSISTENT_ARCHIVE_INPUT_NOT_FILE/ : /PERSISTENT_ARCHIVE_INPUT_PATH_MISSING/);
  }));
}

for (const defect of ['repository', 'missing', 'digest-format']) {
  test(`local archive: ${defect} pin rejects before consumers`, () => fixture(({pin, save, zip, run}) => {
    if (defect === 'repository') pin.artifacts[456].repository = 'other/repo';
    if (defect === 'missing') delete pin.artifacts[456];
    if (defect === 'digest-format') pin.artifacts[456].release_sha256 = 'invalid';
    save();
    const result = run('cli', zip);
    console.log(`TARGET cache ${defect} pin rejection rc=${result.status} commands=${JSON.stringify(result.commands)}`);
    assert.notEqual(result.status, 0);
    assert.deepEqual(result.commands, []);
    assert.match(result.stderr, /PERSISTENT_ARCHIVE_PIN_MISSING artifact=456/);
    assert.deepEqual(fs.readdirSync(result.destination), []);
  }));
}

test('local archive: output alias cannot modify the input', () => fixture(({root, zip, env}) => {
  const alias = path.join(root, 'alias.zip'); fs.linkSync(zip, alias);
  const before = fs.readFileSync(zip);
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {downloadPinned} from ${JSON.stringify(new URL('./download_pinned.mjs', import.meta.url).href)}; downloadPinned('cjcj-dev/cjcj','456',${JSON.stringify(alias)},${JSON.stringify(zip)});`], {env, encoding: 'utf8'});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PERSISTENT_ARCHIVE_INPUT_OUTPUT_ALIAS/);
  assert.deepEqual(fs.readFileSync(zip), before);
}));

// Run the real colour composition entry; substitute only transport and the
// downstream runtime gate so its received inputs can be asserted independently.
for (const archiveSource of ['network', 'local-archive']) {
test(`colour entry (${archiveSource}) separates pinned language SDK from same-build SDK`, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'colour-entry-'));
  try {
    const put = (rel, bytes, mode = 0o644) => {
      const file = path.join(root, rel); fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, bytes, {mode}); return file;
    };
    const target = path.join(root, 'target');
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      put(`target/${name}`, `tested ${name}`);
      put(`installed/runtime/lib/linux_x86_64_cjnative/${name}`, `tested ${name}`);
      put(`build/runtime/lib/linux_x86_64_cjnative/${name}`, `tested ${name}`);
      put(`payload/sdk/runtime/lib/linux_x86_64_cjnative/${name}`, `fixed ${name}`);
    }
    put('payload/sdk/bin/cjc', 'qualified compiler', 0o755);
    put('payload/sdk/host/compiler/libcangjie-runtime.so', 'qualified host');
    const archive = path.join(root, 'language.zip');
    assert.equal(spawnSync('zip', ['-qr', archive, 'sdk'], {cwd: path.join(root, 'payload')}).status, 0);
    const pin = put('pin.json', JSON.stringify({version: 1, artifacts: {1504: {
      repository: 'cjcj-dev/cjcj', asset: 789, prerelease: true,
      release_sha256: digest(fs.readFileSync(archive)),
    }}}));
    put('bin/gh.mjs', `#!/usr/bin/env node
import fs from 'node:fs';
fs.appendFileSync(process.env.TEST_ROOT + '/network-started', 'gh\\n');
process.stdout.write(fs.readFileSync(process.env.TEST_ARCHIVE));
`, 0o755);
    fs.symlinkSync('gh.mjs', path.join(root, 'bin/gh'));
    const archiveEnv = {...process.env};
    delete archiveEnv.COLOUR_GATE_LANGUAGE_ARCHIVE;
    if (archiveSource === 'local-archive') archiveEnv.COLOUR_GATE_LANGUAGE_ARCHIVE = archive;
    put('source/runtime/output/temp/config/runtime-build-config.txt',
      `CONFIG_ID=config\nRUNTIME_SHA256=${digest(fs.readFileSync(path.join(target, 'libcangjie-runtime.so')))}\n`);
    put('source/runtime/build/resolve_runtime_output.sh', '#!/bin/sh\nprintf "%s\\n" "$TEST_TARGET"\n', 0o755);
    put('source/runtime/tests/gc_unit/language_toolchain_qualification.json', '{}');
    put('source/runtime/tests/gc_unit/gate_gc_unit.sh', `#!/bin/bash
set -eu
echo "TARGET SDK domains build=$GC_UNIT_BUILD_SDK language=$GC_UNIT_LANGUAGE_SDK"
[[ "$GC_UNIT_BUILD_SDK" == "$TEST_ROOT/build" ]]
[[ "$GC_UNIT_LANGUAGE_SDK" != "$GC_UNIT_BUILD_SDK" ]]
[[ "$(cat "$GC_UNIT_LANGUAGE_SDK/bin/cjc")" == 'qualified compiler' ]]
[[ "$CJC" == "$GC_UNIT_LANGUAGE_SDK/bin/cjc" ]]
[[ "$GC_UNIT_CJC_RUNTIME_LIB_DIR" == "$GC_UNIT_LANGUAGE_SDK/host/compiler" ]]
[[ "$GC_UNIT_COLOUR_HOST_RUNTIME" == "$GC_UNIT_CJC_RUNTIME_LIB_DIR/libcangjie-runtime.so" ]]
[[ "$GC_UNIT_LANGUAGE_QUALIFICATION" == "$TEST_ROOT/source/runtime/tests/gc_unit/language_toolchain_qualification.json" ]]
[[ -f "$GC_UNIT_COLOUR_CHECKER" ]]
[[ "$GCV2_RUNTIME_LIB_DIR" == "$TEST_TARGET" ]]
[[ "$GC_UNIT_GATE_LANGUAGE_TESTS" == all ]]
echo 'TARGET independent SDK inputs reached actual gate consumer'
`, 0o755);
    const run = suffix => spawnSync('npx', ['--yes', 'zx@8', new URL('./gate_colour_runtime.mjs', import.meta.url).pathname,
      '--build-sdk', path.join(root, 'source'), path.join(root, 'build'),
      path.join(root, suffix), path.join(root, 'installed')], {encoding: 'utf8', env: {
        ...archiveEnv, PATH: `${root}/bin:${process.env.PATH}`, BOOTSTRAP_ARCHIVES_PIN: pin,
        TEST_ARCHIVE: archive, TEST_TARGET: target, TEST_ROOT: root,
      }});
    // Execute supplied_stage1 itself. Only earlier compiler/std production is
    // substituted; its command runner, caller line, gate, transport verifier and
    // downstream input assertions remain the real composition path.
    const bootstrap = new URL('../bootstrap/bootstrap.sh', import.meta.url).pathname;
    const supplied = spawnSync('bash', ['-c', `
source "$1"
WORK="$TEST_ROOT/bootstrap-work"; SRC="$2"
COLOUR_GATE_SOURCE="$TEST_ROOT/source"; COLOUR_GATE_INSTALL="$TEST_ROOT/installed"
HOST_SDK="$TEST_ROOT/build"; STAGE1_ELF="$TEST_ROOT/payload/sdk/bin/cjc"
AST_SUPPORT="$TEST_ROOT/unused"; HOST_TUPLE=linux_x86_64_cjnative
mkdir -p "$WORK"
python3() { if [[ "$1" == */ci/install_std_sdk_inputs.py ]]; then return 0; fi; command python3 "$@"; }
stage1_inputs() { sdk="$TEST_ROOT/build"; compiler="$STAGE1_ELF"; previous_std="$TEST_ROOT/std"; }
stage1_initial_std() { :; }
assemble_stage1_sdk() { [[ "$1" == "$TEST_ROOT/build" && "$3" == "$TEST_ROOT/std" ]]; }
stage1_compiler() { echo 'TARGET bootstrap gate completed before stage2'; exit 0; }
supplied_stage1
`, 'bootstrap-fixture', bootstrap, new URL('../..', import.meta.url).pathname], {encoding: 'utf8', env: {
      ...archiveEnv, PATH: `${root}/bin:${process.env.PATH}`, BOOTSTRAP_ARCHIVES_PIN: pin,
      TEST_ARCHIVE: archive, TEST_TARGET: target, TEST_ROOT: root,
    }});
    assert.equal(supplied.status, 0, supplied.stdout + supplied.stderr);
    assert.match(supplied.stdout, /TARGET independent SDK inputs reached actual gate consumer/);
    assert.match(supplied.stdout, /TARGET bootstrap gate completed before stage2/);
    assert.ok(fs.existsSync(path.join(root, 'bootstrap-work/colour-gate-active-language/sdk/bin/cjc')));
    console.log('TARGET bootstrap supplied_stage1 actual caller accepted --build-sdk');
    const legacy = spawnSync('npx', ['--yes', 'zx@8', new URL('./gate_colour_runtime.mjs', import.meta.url).pathname,
      '--same-source', 'unused-source', 'unused-sdk', 'unused-host', 'unused-install', 'unused-std'],
      {encoding: 'utf8'});
    assert.equal(legacy.status, 2);
    assert.match(legacy.stderr, /COLOUR_RT_GATE_INTERFACE unsupported=--same-source/);
    console.log('TARGET legacy --same-source precisely rejected rc=2 before admission');
    const accepted = run('accepted');
    const acceptance = {rc: accepted.status,
      consumerReached: /TARGET independent SDK inputs reached actual gate consumer/.test(accepted.stdout),
      verifiedSource: new RegExp(`PERSISTENT_ARCHIVE_VERIFIED .*source=${archiveSource}`).test(accepted.stdout),
      networkStarted: fs.existsSync(path.join(root, 'network-started'))};
    console.log(`TARGET colour ${archiveSource} acceptance ${JSON.stringify(acceptance)}`);
    assert.deepEqual(acceptance, {rc: 0, consumerReached: true, verifiedSource: true,
      networkStarted: archiveSource === 'network'}, 'colour entry must pass selected archive bytes to consumer');
    if (archiveSource === 'local-archive') {
      const original = fs.readFileSync(archive);
      fs.appendFileSync(archive, 'corrupted local language archive');
      const badCache = run('bad-cache');
      const observed = {rejected: badCache.status !== 0,
        consumerStarted: /TARGET independent SDK/.test(badCache.stdout),
        networkStarted: fs.existsSync(path.join(root, 'network-started')),
        extracted: fs.existsSync(path.join(root, 'bad-cache-language/sdk'))};
      console.log(`TARGET colour cache digest rejection rc=${badCache.status} ${JSON.stringify(observed)}`);
      assert.deepEqual(observed, {rejected: true, consumerStarted: false, networkStarted: false, extracted: false},
        'colour cache digest must reject before qualification consumer and network');
      assert.match(badCache.stderr, /bootstrap digest mismatch: artifact-1504.zip/);
      fs.writeFileSync(archive, original);
      console.log('ASSERT colour cache digest rejection reached; original bytes restored');
    }
    console.log(accepted.stdout.trim());
    put('build/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', 'wrong build target');
    const rejected = run('rejected');
    assert.notEqual(rejected.status, 0);
    assert.doesNotMatch(rejected.stdout, /TARGET independent SDK/);
    console.log(`TARGET mismatched build runtime rejected rc=${rejected.status}`);
    put('build/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', 'tested libcangjie-runtime.so');
    const restored = run('restored');
    assert.equal(restored.status, 0, restored.stderr);
    assert.match(restored.stdout, /TARGET independent SDK inputs reached actual gate consumer/);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});
}
