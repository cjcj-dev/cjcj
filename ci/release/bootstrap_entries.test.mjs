import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import {fixture} from './prepare_bootstrap_fixture.mjs';

const repository = path.resolve(import.meta.dirname, '../..');
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function driverFixture(check) {
  fixture(inputs => {
    const root = path.join(inputs.dir, "runner's tree");
    fs.mkdirSync(root);
    for (const directory of ['ci', 'build', 'tools']) {
      fs.cpSync(path.join(repository, directory), path.join(root, directory), {recursive: true});
    }
    const driver = path.join(root, 'tools/srcbuild_kkk2.sh');
    inputs.env.NODE_OPTIONS = `${inputs.env.NODE_OPTIONS || ''} --import=${JSON.stringify(inputs.transport)}`;
    if (os.hostname().split('.')[0] !== 'kkk2') {
      const bin = path.join(inputs.dir, 'driver-bin');
      fs.mkdirSync(bin);
      fs.writeFileSync(path.join(bin, 'hostname'), '#!/bin/sh\nprintf "kkk2\\n"\n', {mode: 0o755});
      inputs.env.PATH = `${bin}:${inputs.env.PATH}`;
    }
    const runDriver = (stage = 31) => spawnSync('bash', [driver,
      '--from-step', String(stage), '--through-step', String(stage), '--dry-run'],
    {env: inputs.env, encoding: 'utf8'});
    const runFull = () => {
      const result = spawnSync('bash', [driver, '--from-step', '2', '--through-step', '36'],
        {env: inputs.env, encoding: 'utf8'});
      const logs = path.join(root, '.srcbuild/logs');
      const log = fs.existsSync(logs) ? fs.readdirSync(logs)
        .map(name => fs.readFileSync(path.join(logs, name), 'utf8')).join('\n') : '';
      return {...result, log};
    };
    check({...inputs, root, driver, runDriver, runFull});
  });
}

function identity(result) {
  const record = /^BOOTSTRAP_INPUT_IDENTITIES=(.+)$/m.exec(result.stdout + result.stderr);
  return record ? JSON.parse(record[1]) : null;
}

function argumentsFrom(result) {
  const command = /^DRY_RUN COMMAND=(.+)$/m.exec(result.stdout)?.[1];
  if (!command) return [];
  const decoded = spawnSync('bash', ['-c', 'eval "set -- $1"; printf "%s\\0" "$@"', 'argv', command], {encoding: 'utf8'});
  assert.equal(decoded.status, 0, decoded.stderr);
  return decoded.stdout.split('\0');
}

test('both actual preparation entries export identical identities and consumer bytes', () => driverFixture(({run, runDriver}) => {
  const gha = run();
  for (const stage of [31, 32]) {
    const kkk2 = runDriver(stage);
    const argv = argumentsFrom(kkk2);
    const input = flag => argv[argv.indexOf(flag) + 1];
    const observed = {gha: gha.status, kkk2: kkk2.status, identities: identity(kkk2),
      host: argv.includes('--host-llvm-so') ? digest(input('--host-llvm-so')) : null,
      ast: argv.includes('--ast-support') ? digest(input('--ast-support')) : null,
      dylib: argv.includes('--colour-llvm-so') ? digest(input('--colour-llvm-so')) : null,
      symlink: argv.includes('--base') && fs.lstatSync(path.join(input('--base'), 'bin/ld.lld')).isSymbolicLink()
        ? fs.readlinkSync(path.join(input('--base'), 'bin/ld.lld')) : null,
    };
    console.log(`ENTRY_IDENTITIES_ASSERT stage=${stage} ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {gha: 0, kkk2: 0, identities: identity(gha),
      host: identity(gha)?.host_llvm, ast: identity(gha)?.ast_support,
      dylib: identity(gha)?.colour_llvm, symlink: 'lld'});
    assert.notEqual(identity(gha), null);
  }
}));

test('full 2..36 entry prepares the same fixed-tool bytes before numbered steps', () => driverFixture(({root, runFull, runDriver}) => {
  const full = runFull();
  const bootstrap = runDriver();
  const expected = identity(bootstrap)?.colour_tuple;
  const actual = Object.fromEntries(Object.keys(expected || {}).filter(name => name.startsWith('fixed-llc/'))
    .map(name => {
      const file = path.join(root, '.srcbuild', name);
      return [name, fs.existsSync(file) ? digest(file) : null];
    }));
  const observed = {prerequisite: /PREREQUISITE=fixed-llvm rc=0/.test(full.stdout),
    numberedSteps: /STEP=2 .*rc=128/.test(full.stdout), bootstrap: bootstrap.status, actual};
  console.log(`FULL_ENTRY_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {prerequisite: true, numberedSteps: true, bootstrap: 0,
    actual: Object.fromEntries(Object.entries(expected || {}).filter(([name]) => name.startsWith('fixed-llc/')))});
  assert.equal(Object.keys(actual).length, 5);
}));

test('full entry rejects an incorrect tuple pin before any numbered step', () => driverFixture(({pinFile, runFull, runDriver}) => {
  const pin = JSON.parse(fs.readFileSync(pinFile));
  const payload = pin.files.find(file => file.path === 'fixed-llc/opt.gz');
  payload.artifact_sha256 = payload.release_sha256 = '0'.repeat(64);
  fs.writeFileSync(pinFile, JSON.stringify(pin));
  const full = runFull();
  const bootstrap = runDriver();
  const observed = {full: full.status, bootstrap: bootstrap.status,
    fullRejects: full.log.includes('bootstrap digest mismatch: fixed-llc/opt.gz'),
    bootstrapRejects: bootstrap.stderr.includes('bootstrap digest mismatch: fixed-llc/opt.gz'),
    entered: /^STEP=/m.test(full.stdout)};
  console.log(`FULL_ENTRY_REJECTION_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {full: 1, bootstrap: 1, fullRejects: true, bootstrapRejects: true, entered: false});
}));

const corruptions = [
  ['host-sdk', inputs => fs.writeFileSync(inputs.env.STAGE1_HOST_IDENTITIES,
    fs.readFileSync(inputs.env.STAGE1_HOST_IDENTITIES, 'utf8').replace(/(# HOST_SDK_PROVENANCE .*"sha256":")[a-f0-9]{64}/,
      `$1${'0'.repeat(64)}`)), 'HOST_SDK_SHA256_MISMATCH'],
  ['host-llvm', inputs => fs.appendFileSync(path.join(inputs.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT, 'libLLVM-15.so'), 'changed'), 'HOST_LLVM_SHA256_MISMATCH'],
  ['ast', inputs => fs.appendFileSync(inputs.env.CJCJ_BOOTSTRAP_AST_SUPPORT, 'changed'), 'ast-support archive SHA256 disagrees'],
  ['tuple', inputs => fs.appendFileSync(path.join(inputs.fallback, 'SHA256SUMS'), 'changed'), 'bootstrap digest mismatch: SHA256SUMS'],
  ['runtime', inputs => fs.appendFileSync(path.join(inputs.runtime, 'manifest.json'), ' '), 'COLOUR_RT_SHA256_MISMATCH'],
  ['runtime-member', inputs => fs.appendFileSync(path.join(inputs.runtime, 'runtime/lib/linux_x86_64_cjnative/libboundscheck.so'), 'changed'), 'COLOUR_RT_FILE_SHA256_MISMATCH'],
  ['dylib', inputs => fs.appendFileSync(path.join(inputs.dylib, 'libLLVM-15.so'), 'changed'), 'LLVM_DYLIB_SHA256_MISMATCH'],
];
for (const [name, corrupt, marker] of corruptions) {
  test(`actual kkk2 preparation rejects changed ${name} before command publication`, () => driverFixture(inputs => {
    corrupt(inputs);
    const gha = inputs.run();
    const kkk2 = inputs.runDriver();
    const observed = {gha: gha.status, kkk2: kkk2.status,
      ghaMarker: gha.stderr.includes(marker), kkk2Marker: kkk2.stderr.includes(marker),
      command: argumentsFrom(kkk2).length > 0, identities: identity(kkk2)};
    console.log(`ENTRY_REJECTION_ASSERT input=${name} ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {gha: 1, kkk2: 1, ghaMarker: true, kkk2Marker: true, command: false, identities: null});
  }));
}

test('SDK archive pin is mandatory even when an installed SDK is available', () => driverFixture(({env, runDriver}) => {
  fs.writeFileSync(env.STAGE1_HOST_IDENTITIES,
    fs.readFileSync(env.STAGE1_HOST_IDENTITIES, 'utf8').replace(/^# HOST_SDK_PROVENANCE .*\n/m, ''));
  const result = runDriver();
  const observed = {rc: result.status, missingPin: result.stderr.includes('HOST_SDK_PIN_MISSING'), command: argumentsFrom(result).length > 0};
  console.log(`SDK_PIN_ASSERT ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, {rc: 1, missingPin: true, command: false});
}));
