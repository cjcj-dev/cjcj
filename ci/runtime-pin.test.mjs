import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {parseEnv} from 'node:util';
import {readHostToolchainPin} from './host-toolchain-pin.mjs';
import {readSourcePins} from './native-llvm-inputs.mjs';
import {nativePair} from './runtime-pin.mjs';

const pins = readSourcePins();
const override = '1'.repeat(40);
const nativeArtifact = 'native-runtime-install';

function loadRuntime(t, {dryRun = false, runtimeRef = '', artifact = '', tamper = {}, developmentSdk = false} = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'runtime-pin-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const run = (script, env, args = []) => spawnSync(process.execPath, [path.join(import.meta.dirname, script), ...args],
    {env, encoding: 'utf8'});
  // Each Actions step reads the preceding exports and writes its own GITHUB_ENV.
  const sourceFile = path.join(dir, 'source.env');
  const env = {CJCJ_NATIVE_RUNTIME_ARTIFACT: artifact};
  const source = run('native-llvm-inputs.mjs', {...env, GITHUB_ENV: sourceFile});
  assert.equal(source.status, 0, source.stderr);
  const inherited = parseEnv(readFileSync(sourceFile, 'utf8'));
  assert.equal(inherited.CJCJ_NATIVE_PAIR_SELECTION, 'pinned');
  const runtimeFile = path.join(dir, 'runtime.env');
  const loaderEnv = {...env, ...inherited, ...tamper, GITHUB_ENV: runtimeFile,
    CJCJ_RUNTIME_REF_OVERRIDE: runtimeRef, CJCJ_ALLOW_RUNTIME_OVERRIDE: String(dryRun && !!runtimeRef)};
  if (developmentSdk) Object.assign(loaderEnv, {CJCJ_SRCBUILD_TARGET: 'linux-x64', RUNTIME_NATIVE_PAIR: '1'});
  const result = run('load_runtime_pin.mjs', loaderEnv, developmentSdk ? ['--development-sdk', runtimeFile] : []);
  return {result, inherited, exports: () => parseEnv(readFileSync(runtimeFile, 'utf8'))};
}

test('inherited pins allow an authorized dry-run override without an artifact', t => {
  const loader = loadRuntime(t, {dryRun: true, runtimeRef: override});
  assert.equal(loader.result.status, 0, loader.result.stderr);
  assert.match(loader.result.stdout, / native_pair=<none>$/m);
  const exported = loader.exports();
  assert.equal(exported.CJCJ_NATIVE_RUNTIME_REF, override);
  // Configure reads the merged job environment, including the earlier source marker.
  assert.equal(nativePair({...loader.inherited, ...exported}, {requireHost: false}).runtime, override);
});

test('inherited pins preserve the authorization error for an override without an artifact', t => {
  const {result} = loadRuntime(t, {runtimeRef: override});
  assert.equal(result.status, 1);
  assert.match(result.stderr, /^Error: CJCJ_RUNTIME_REF_OVERRIDE is allowed only by an explicit dry-run\/test authorization$/m);
});

test('inherited pins without an artifact select the default runtime and export no host', t => {
  const loader = loadRuntime(t);
  assert.equal(loader.result.status, 0, loader.result.stderr);
  assert.match(loader.result.stdout, / native_pair=<none>$/m);
  const env = loader.exports();
  assert.equal(env.CJCJ_NATIVE_RUNTIME_REF, pins.runtime.RUNTIME_REF);
  assert.equal(Object.hasOwn(env, 'CJCJ_NATIVE_HOST_VERSION'), false);
});

test('inherited pins select the checked-in pair and default host for a native artifact', t => {
  const loader = loadRuntime(t, {artifact: nativeArtifact});
  assert.equal(loader.result.status, 0, loader.result.stderr);
  assert.ok(loader.result.stdout.trimEnd().endsWith(' native_pair=' + pins.llvm.LLVM_SHA));
  const env = loader.exports();
  assert.equal(env.CJCJ_NATIVE_LLVM_REF, pins.llvm.LLVM_SHA);
  assert.equal(env.CJCJ_NATIVE_RUNTIME_REF, pins.runtime.RUNTIME_REF);
  assert.equal(env.CJCJ_NATIVE_HOST_VERSION, readHostToolchainPin().replace(/^nightly-/, ''));
});

for (const artifact of ['', nativeArtifact]) {
  test('a forged pinned pair is rejected ' + (artifact ? 'with' : 'without') + ' an artifact', t => {
    for (const key of ['CJCJ_NATIVE_LLVM_REF', 'CJCJ_NATIVE_RUNTIME_REF']) {
      const {result} = loadRuntime(t, {artifact, tamper: {[key]: override}});
      assert.equal(result.status, 1);
      assert.match(result.stderr, /^Error: NATIVE_PAIR_SELECTION_NOT_PINNED$/m);
    }
  });
}

test('the Linux development SDK can replace inherited defaults with its own pinned commits',
  {skip: process.platform !== 'linux' || process.arch !== 'x64'}, t => {
    const loader = loadRuntime(t, {developmentSdk: true});
    assert.equal(loader.result.status, 0, loader.result.stderr);
    const pair = nativePair({...loader.inherited, ...loader.exports()});
    assert.deepEqual(pair, {llvm: pins.llvm.LINUX_X64_SDK_LLVM_SHA, runtime: pins.runtime.LINUX_X64_SDK_RUNTIME_REF,
      hostVersion: readHostToolchainPin().replace(/^nightly-/, '')});
  });
