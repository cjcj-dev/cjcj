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
  // Keep the ZIP extractable so disabling verification cannot hide the target
  // behind an unzip error. Its comment is part of the pinned archive digest.
  assert.equal(spawnSync('zip', ['-q', '-z', zip], {input: 'unreviewed cache comment\n'}).status, 0);
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

// This is an entry-wiring apparatus: the real resolver/gate child interfaces
// are reached; the dedicated native language integration uses actual SDK ELF.
for (const platform of ['linux_x86_64', 'linux_aarch64']) test(`colour entry ${platform} consumes the supplied SDK and rejects a changed target pair`, () => {
 const tuple=platform+'_cjnative';
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'colour-entry-'));
 try {
  const put=(rel,bytes,mode=0o644)=>{const p=path.join(root,rel);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,bytes,{mode});};
  for(const name of ['libcangjie-runtime.so','libboundscheck.so'])for(const dir of ['target',`installed/runtime/lib/${tuple}`,`sdk/runtime/lib/${tuple}`])put(dir+'/'+name,'tested '+name);
  put('sdk/bin/cjc','compiler fixture',0o755);
  put(`sdk/.host/runtime/lib/${tuple}/libcangjie-runtime.so`,'host fixture');
  const target=path.join(root,'installed/runtime/lib',tuple);
  put('source/runtime/tests/gc_unit/gate_gc_unit.sh',`#!/bin/bash
set -eu
[[ "$GC_UNIT_LANGUAGE_SDK" == "$TEST_ROOT/sdk" ]]
[[ "$GC_UNIT_RUNTIME_TUPLE" == "${tuple}" ]]
[[ "$GC_UNIT_CJC_RUNTIME_TUPLE" == "${tuple}" ]]
[[ "$CJC" == "$TEST_ROOT/sdk/bin/cjc" ]]
[[ "$GC_UNIT_CJC_RUNTIME_LIB_DIR" == "$TEST_ROOT/sdk/.host/runtime/lib/${tuple}" ]]
[[ "$GC_UNIT_COLOUR_HOST_RUNTIME" == "$GC_UNIT_CJC_RUNTIME_LIB_DIR/libcangjie-runtime.so" ]]
[[ "$GCV2_RUNTIME_LIB_DIR" == "$TEST_TARGET" ]]
[[ -z "\${GC_UNIT_LANGUAGE_QUALIFICATION-}" ]]
[[ "$GCV2_RUNTIME_BUILD_DIR" == "$TEST_ROOT/source/runtime/CMakebuild" ]]
[[ "$GC_UNIT_GATE_LANGUAGE_TESTS" == all ]]
printf 'GATE=PASS\\nGATE_RC=0\\nLANGUAGE_TESTS=LANGUAGE_DONE\\n' >"$GC_UNIT_GATE_STATUS"
echo TARGET_CURRENT_SDK_CONSUMED
`,0o755);
  const run=()=>spawnSync('npx',['--yes','zx@8',new URL('./gate_colour_runtime.mjs',import.meta.url).pathname,
   path.join(root,'source'),path.join(root,'sdk'),path.join(root,'work'),path.join(root,'installed')],
   {encoding:'utf8',env:{...process.env,TEST_ROOT:root,TEST_TARGET:target,PLATFORM_TUPLE:platform}});
  const good=run();assert.equal(good.status,0,good.stderr);assert.match(good.stdout,/TARGET_CURRENT_SDK_CONSUMED/);
  put(`sdk/runtime/lib/${tuple}/libcangjie-runtime.so`,'wrong pair');
  const bad=run();assert.notEqual(bad.status,0);assert.doesNotMatch(bad.stdout,/TARGET_CURRENT_SDK_CONSUMED/);
  put(`sdk/runtime/lib/${tuple}/libcangjie-runtime.so`,'tested libcangjie-runtime.so');
  const restored=run();assert.equal(restored.status,0,restored.stderr);assert.match(restored.stdout,/TARGET_CURRENT_SDK_CONSUMED/);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
