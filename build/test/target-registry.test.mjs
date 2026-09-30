import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {allTargets, ciBuildCells, ciProvisionCells, getTarget, platformTestCells, sourceBuildCells, targetForHost} from '../lib/targets.mjs';
import {baseSdkDownload} from '../lib/release-component-provenance.mjs';
import {resolveGateHostRuntime} from '../lib/release-gate-apparatus.mjs';

const root = path.resolve(import.meta.dirname, '../..');
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

test('platform dispatch consumes every registry runner with its LLVM and runtime tuple', t => {
  const {text, outputs} = plan(t, 'platform-matrix.yml');
  assert.deepEqual(matrix(text, 'platform', outputs), platformTestCells(), 'platform dispatch rows');
});

test('ARM caller requests only ARM and package fields consume the same plan', t => {
  const {text, outputs} = plan(t, 'arm-soak.yml');
  const resolve = value => value.replace(/\$\{\{ needs.matrix-plan.outputs.(\w+) \}\}/g, (_, key) => outputs[key]);
  const source = job(text, 'source-final-std');
  const requested = resolve(source.match(/^      targets: (.+)$/m)?.[1] || 'all');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'arm-source-'));
  t.after(() => fs.rmSync(temp, {recursive: true, force: true}));
  const output = path.join(temp, 'output');
  const result = spawnSync(process.execPath, ['ci/srcbuild/target-matrix.mjs', '--targets', requested], {
    cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: ''},
  });
  assert.equal(result.status, 0, result.stderr);
  const cells = JSON.parse(fs.readFileSync(output, 'utf8').match(/^cells=(.+)$/m)[1]).include;
  console.log(`ARM_REQUEST requested=${requested} result=${JSON.stringify(cells)}`);
  assert.deepEqual(cells.map(cell => cell.target), ['linux-aarch64'], 'ARM caller excludes unrelated source cells');
  assert.match(result.stdout, /issues\/763/);
  assert.doesNotMatch(result.stdout, /issues\/473/);
  const {spec, sourceBuild} = getTarget('linux-aarch64');
  const expected = {runner: sourceBuild.runner, platform: spec.key, llvm_platform: spec.llvmPlatform,
    sdk_runtime_dir: spec.runtimeTuple, compiler_artifact: `final-compiler-${spec.key}`};
  const packageJob = job(text, 'package');
  for (const [key, value] of Object.entries(expected)) {
    assert.equal(resolve(packageJob.match(new RegExp(`^      ${key}: (.+)$`, 'm'))[1]), value, key);
  }
  assert.match(packageJob, /std_artifact: \$\{\{ inputs.std_artifact \|\| needs.matrix-plan.outputs.std_artifact \}\}/);
  assert.equal(outputs.std_artifact, `final-std-${spec.key}`);
});

test('every target mapping reaches archive naming, runtime lookup and native host selection', async t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'target-spec-'));
  t.after(() => fs.rmSync(temp, {recursive: true, force: true}));
  for (const key of allTargets()) {
    const {spec} = getTarget(key);
    const download = baseSdkDownload(key, 'nightly-1.2.0-alpha.20260721165458');
    assert.equal(download.archive, `cangjie-sdk-${spec.sdkName}-1.2.0-alpha.20260721165458.${spec.archiveFormat}`, key);
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
      "import {hostIdentity} from './ci/release/host_llvm.mjs'; console.log(JSON.stringify(hostIdentity()));"], {
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
       process.argv = [process.execPath, 'ci/release/prepare_python_bundle.mjs', ${JSON.stringify(key)}, 'unused'];
       await import('./ci/release/prepare_python_bundle.mjs');`], {
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
    ['scripts/verify_packaged_cjdb.mjs', ['getTarget(platform).spec.runtimeTuple']],
    ['ci/release/prepare_python_bundle.mjs', ['getTarget(platform).spec.packageHost']],
    ['ci/platform_matrix/build_cjcj.mjs', ['targetForHost()?.spec.runtimeTuple']],
    ['ci/platform_matrix/fetch_llvm_tuple.mjs', ['targetForHost()?.spec.llvmPlatform']],
    ['ci/setup_sdk.mjs', ['targetForHost()?.spec.llvmPlatform']],
    ['ci/release/host_llvm.mjs', ['spec.llvmPlatform', 'spec.hostLlvmLibrary']],
    ['ci/release/prepare_bootstrap_fixture.mjs', ['getTarget(target).spec.llvmPlatform']],
    ['scripts/package_sdk.mjs', ['getTarget(platform)', 'targetSpec.nativeFilePattern', 'targetSpec.requiredLlvmTools']],
  ];
  for (const [file, fields] of consumers) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    assert.match(text, /import .* from ['"].*targets.mjs['"]/);
    for (const field of fields) assert.ok(text.includes(field), `${file} consumes ${field}`);
    assert.doesNotMatch(text, /['"](?:linux-x64|linux-aarch64|darwin-arm64|darwin-x64|windows-x64)['"]:\s*(?:\[|\{|['"])/, file);
  }
  const text = workflow('srcbuild-target.yml');
  assert.match(text, /TARGET_LLVM_PLATFORM: \$\{\{ matrix.llvm_platform \}\}/);
  assert.match(text, /pin\['platform'\] == os.environ\['TARGET_LLVM_PLATFORM'\]/);
  assert.doesNotMatch(text, /platforms = \{/);
});

test('source workflows drop unused final outputs while retaining artifact upload steps', () => {
  for (const file of ['srcbuild.yml', 'srcbuild-target.yml']) {
    assert.doesNotMatch(workflow(file), /final_(?:std|compiler)_|artifact-contract:/);
  }
  assert.match(workflow('srcbuild-target.yml'), /name: final-compiler-\$\{\{ matrix.target \}\}/);
  assert.match(workflow('srcbuild-target.yml'), /name: final-std-\$\{\{ matrix.target \}\}/);
});
