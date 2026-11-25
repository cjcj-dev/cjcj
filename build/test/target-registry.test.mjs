import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {allTargets, ciBuildCells, ciProvisionCells, getTarget, platformTestCells, sourceBuildCells, targetForHost} from '../lib/targets.mjs';
import {baseSdkDownload} from '../lib/release-component-provenance.mjs';
import {resolveGateHostRuntime} from '../lib/release-gate-apparatus.mjs';
import {readHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const baseSdkIdentities = JSON.parse(fs.readFileSync(path.join(root, 'build/sdk/producers/release/base-sdk-identities.json'), 'utf8'));
const workflow = name => fs.readFileSync(path.join(root, '.github/workflows', name), 'utf8');
const job = (text, name) => text.split(`\n  ${name}:\n`)[1]?.split(/\n  [\w-]+:\n/)[0];

function plan(t, file) {
  const text = workflow(file);
  const command = job(text, 'matrix-plan')?.match(/^        run: (.+)$/m)?.[1];
  assert.ok(command, `${file} has a runnable matrix producer`);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'target-registry-'));
  t.after(() => fs.rmSync(temp, {recursive: true, force: true}));
  const output = path.join(temp, 'output');
  const result = spawnSync('bash', ['-e', '-c', command], {
    cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_OUTPUT: output},
  });
  assert.equal(result.status, 0, result.stderr);
  const outputs = Object.fromEntries(fs.readFileSync(output, 'utf8').trim().split('\n').map(line => {
    const split = line.indexOf('=');
    return [line.slice(0, split), line.slice(split + 1)];
  }));
  console.log(`REGISTRY_PLAN ${file} ${JSON.stringify(outputs)}`);
  return {text, outputs};
}

function matrix(text, name, outputs) {
  const body = job(text, name);
  const expression = body.match(/^      matrix: (.+)$/m)?.[1];
  const key = expression?.match(/^\$\{\{ fromJSON\(needs.matrix-plan.outputs.(\w+)\) \}\}$/)?.[1];
  assert.ok(key, `${name} dispatch must consume the registry plan`);
  assert.match(body, /needs:.*matrix-plan/);
  return JSON.parse(outputs[key]).include;
}

test('CI build and provision dispatch consume the registry runner and experimental fields', t => {
  const {text, outputs} = plan(t, 'ci.yml');
  assert.deepEqual(matrix(text, 'build', outputs), ciBuildCells(), 'CI build dispatch rows');
  assert.deepEqual(matrix(text, 'provision', outputs), ciProvisionCells(), 'CI provision dispatch rows');
  assert.equal(ciBuildCells().find(cell => cell.runner === 'ubuntu-24.04-arm').experimental, false);
  assert.equal(ciBuildCells().find(cell => cell.runner === 'ubuntu-26.04').experimental, true);
});



test('every target mapping reaches archive naming, runtime lookup and native host selection', async t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'target-spec-'));
  t.after(() => fs.rmSync(temp, {recursive: true, force: true}));
  for (const key of allTargets()) {
    const {spec} = getTarget(key);
    const download = baseSdkDownload(key, readHostToolchainPin(key));
    const identity = baseSdkIdentities.platforms[key];
    assert.equal(download.archive, `cangjie-sdk-${identity.os}-${identity.arch}-${identity.version || baseSdkIdentities.version}${identity.extension}`, key);
    assert.equal(download.size, identity.size, `${key} pinned size`);
    assert.equal(download.sha256, identity.sha256, `${key} pinned SHA-256`);
    assert.equal(targetForHost(...spec.packageHost).spec.key, key, `${key} package host`);
    const relative = `runtime/lib/${spec.runtimeTuple}/${spec.runtimeLibrary}`;
    const file = path.join(temp, relative);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, key);
    const actual = await resolveGateHostRuntime({sdk: temp, platform: key});
    assert.equal(actual.relative, relative, `${key} runtime mapping`);
    if (spec.os === 'windows') {
      const fallback = relative.replace(/\/libcangjie-runtime.dll$/, '/cangjie-runtime.dll');
      fs.renameSync(file, path.join(temp, fallback));
      assert.equal((await resolveGateHostRuntime({sdk: temp, platform: key})).relative, fallback);
    }
    console.log(`SPEC_CONSUMER ${key} archive=${download.archive} runtime=${actual.relative} host=${spec.packageHost}`);
  }
  assert.deepEqual(getTarget('windows-x64').spec.packageHost, ['win32', 'x64']);
  assert.equal(getTarget('windows-x64').spec.nodePlatform, 'linux');
});

test('every native host identity consumer returns the registry platform and library', () => {
  for (const {target} of sourceBuildCells()) {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e',
      "import {hostIdentity} from './build/sdk/producers/release/host_llvm.mjs'; console.log(JSON.stringify(hostIdentity()));"], {
      cwd: root, encoding: 'utf8', env: {...process.env, CJCJ_SRCBUILD_TARGET: target, STAGE1_HOST_IDENTITIES: ''},
    });
    assert.equal(result.status, 0, `${target}: ${result.stderr}`);
    const actual = JSON.parse(result.stdout);
    const {spec} = getTarget(target);
    assert.equal(actual.platform, spec.llvmPlatform, `${target} identity platform`);
    assert.equal(actual.library, spec.hostLlvmLibrary, `${target} identity library`);
    console.log(`HOST_SPEC ${target} platform=${actual.platform} library=${actual.library}`);
  }
});

for (const key of allTargets()) {
  test(`Python preparation enforces the registry package host for ${key}`, () => {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e',
      `Object.defineProperty(process, 'platform', {value: 'unsupported'});
       process.argv = [process.execPath, 'build/sdk/producers/release/prepare_python_bundle.mjs', ${JSON.stringify(key)}, 'unused'];
       await import('./build/sdk/producers/release/prepare_python_bundle.mjs');`], {
      cwd: root, encoding: 'utf8',
    });
    const expected = `${key} Python must be prepared natively on ${getTarget(key).spec.packageHost.join('/')}, got unsupported/${process.arch}`;
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes(expected), `${key} package host rejection: ${result.stderr}`);
    console.log(`PYTHON_PACKAGE_HOST ${expected}`);
  });
}

test('all audited spec consumers reference registry fields without independent target tables', () => {
  const consumers = [
    ['build/lib/release-component-provenance.mjs', ['spec.sdkName', 'spec.archiveFormat']],
    ['build/lib/release-gate-apparatus.mjs', ['spec.runtimeTuple', 'spec.runtimeLibrary']],
    ['build/sdk/producers/package/verify_packaged_cjdb.mjs', ['getTarget(platform).spec.runtimeTuple']],
    ['build/sdk/producers/release/prepare_python_bundle.mjs', ['getTarget(platform).spec.packageHost']],
    ['build/sdk/producers/platform_matrix/build_cjcj.mjs', ['targetForHost()?.spec.runtimeTuple']],
    ['build/sdk/producers/platform_matrix/fetch_llvm_tuple.mjs', ['targetForHost()?.spec.llvmPlatform']],
    ['ci/setup_sdk.mjs', ['targetForHost()?.spec.llvmPlatform']],
    ['build/sdk/producers/release/host_llvm.mjs', ['spec.llvmPlatform', 'spec.hostLlvmLibrary']],
    ['build/sdk/producers/release/prepare_bootstrap_fixture.mjs', ['getTarget(target).spec.llvmPlatform']],
    ['build/sdk/producers/package/package_sdk.mjs', ['getTarget(platform)', 'targetSpec.nativeFilePattern', 'targetSpec.requiredLlvmTools']],
  ];
  for (const [file, fields] of consumers) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    assert.match(text, /import .* from ['"].*targets.mjs['"]/);
    for (const field of fields) assert.ok(text.includes(field), `${file} consumes ${field}`);
    assert.doesNotMatch(text, /['"](?:linux-x64|linux-aarch64|darwin-arm64|darwin-x64|windows-x64)['"]:\s*(?:\[|\{|['"])/, file);
  }
  const text = workflow('sdk-build-target.yml');
  assert.match(text, /TARGET_LLVM_PLATFORM: \$\{\{ matrix.llvm_platform \}\}/);
  assert.match(text, /pin\['platform'\] == os.environ\['TARGET_LLVM_PLATFORM'\]/);
  assert.doesNotMatch(text, /platforms = \{/);
});

test('source workflows drop unused final outputs while retaining artifact upload steps', () => {
  for (const file of ['sdk-build.yml', 'sdk-build-target.yml']) {
    assert.doesNotMatch(workflow(file), /final_(?:std|compiler)_|artifact-contract:/);
  }
  assert.match(workflow('sdk-build-target.yml'), /name: final-compiler-\$\{\{ matrix.target \}\}/);
  assert.match(workflow('sdk-build-target.yml'), /name: \$\{\{ matrix.std_artifact \}\}/);
});
