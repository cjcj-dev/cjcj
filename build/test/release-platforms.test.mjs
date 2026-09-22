import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  RELEASE_REQUIREMENTS,
  allReleasePlatforms,
  allTargets,
  getReleasePlatform,
  getTarget,
  isDroppedArm32Tuple,
  releasePlatformReadiness,
} from '../lib/targets.mjs';

const root = path.resolve(import.meta.dirname, '../..');

// The fourteen keys cjv's nightly.json lists for 1.3.0-alpha.20260904010027
// (reports/EVIDENCE-exp_sdk_parity/sdk-packages-0904-manifest.tsv). The table
// must cover exactly these: one missing is a package nobody builds, one extra
// is a package the nightly does not ship.
const OFFICIAL = [
  'darwin-arm64', 'darwin-arm64-android', 'darwin-arm64-ios', 'darwin-arm64-ohos', 'darwin-x64',
  'linux-arm64', 'linux-x64', 'linux-x64-android', 'linux-x64-ohos', 'ohos-arm64',
  'win32-x64', 'win32-x64-android', 'win32-x64-ohos', 'win32-x64-ohos-arm32',
];

test('the release platform table is exactly the fourteen official packages', () => {
  assert.deepEqual([...allReleasePlatforms()].sort(), OFFICIAL);
});

test('every release platform names a buildable host target and a runner of that host', () => {
  for (const key of allReleasePlatforms()) {
    const platform = getReleasePlatform(key);
    assert.ok(allTargets().includes(platform.host), `${key}: host ${platform.host} is not a target key`);
    assert.match(platform.runner, /^(ubuntu|macos|windows)-/, `${key}: runner ${platform.runner}`);
    const hostOs = getTarget(platform.host).spec.os;
    // The package runner runs the host SDK: Linux hosts on ubuntu, Darwin on
    // macos, and the cross-built Windows SDK is packaged on a Windows runner.
    const expectedPrefix = {linux: 'ubuntu-', darwin: 'macos-', windows: 'windows-'}[hostOs];
    assert.ok(platform.runner.startsWith(expectedPrefix), `${key}: ${hostOs} host packaged on ${platform.runner}`);
    for (const requirement of platform.requires) assert.ok(RELEASE_REQUIREMENTS[requirement], `${key}: unknown requirement ${requirement}`);
  }
});

test('readiness is derived from DAG producers: the five native packages build, the rest are blocked or excluded by name', () => {
  const byStatus = {buildable: [], blocked: [], excluded: []};
  for (const key of allReleasePlatforms()) byStatus[releasePlatformReadiness(key).status].push(key);
  assert.deepEqual(byStatus.buildable, ['linux-x64', 'linux-arm64', 'darwin-arm64', 'darwin-x64', 'win32-x64']);
  assert.deepEqual(byStatus.excluded, ['win32-x64-ohos-arm32']);
  assert.equal(byStatus.blocked.length, 8);
  for (const key of byStatus.blocked) {
    const readiness = releasePlatformReadiness(key);
    assert.ok(readiness.reasons.length > 0, `${key} blocked without a reason`);
    for (const reason of readiness.reasons) {
      assert.match(reason, /^(tuple \S+_cjnative: |requires [a-z-]+: |device-side SDK: )/, `${key}: reason does not name a tuple, capability or device-side gap: ${reason}`);
    }
  }
  for (const key of byStatus.buildable) assert.deepEqual(releasePlatformReadiness(key).reasons, []);
});

test('buildable packages resolve their std producers to the same cells release.yml wires', () => {
  const linux = releasePlatformReadiness('linux-x64');
  assert.equal(linux.sourceTarget, 'linux-x64');
  assert.deepEqual(linux.crossStd, {windows_x86_64_cjnative: 'linux-x64'});
  const arm = releasePlatformReadiness('linux-arm64');
  assert.equal(arm.sourceTarget, 'linux-aarch64');
  assert.deepEqual(arm.crossStd, {windows_x86_64_cjnative: 'linux-x64'});
  const windows = releasePlatformReadiness('win32-x64');
  assert.equal(windows.sourceTarget, 'linux-x64', 'the Windows std is cross-built by the linux-x64 cell');
  assert.equal(windows.hostStdCrossBuilt, true);
  assert.equal(windows.runner, 'windows-2025');
  for (const key of ['darwin-arm64', 'darwin-x64']) {
    const darwin = releasePlatformReadiness(key);
    assert.equal(darwin.sourceTarget, key);
    assert.deepEqual(darwin.crossStd, {});
  }
});

test('ARM32 tuples are dropped, never carried, and the arm32-only package is excluded', () => {
  assert.ok(isDroppedArm32Tuple('linux_android23_arm_cjnative'));
  assert.ok(isDroppedArm32Tuple('linux_ohos_arm_cjnative'));
  for (const key of allReleasePlatforms()) {
    const platform = getReleasePlatform(key);
    for (const tuple of platform.crossTuples) assert.ok(!isDroppedArm32Tuple(tuple), `${key} carries ARM32 tuple ${tuple}`);
  }
  assert.match(releasePlatformReadiness('win32-x64-ohos-arm32').reasons[0], /ARM32/);
});

test('asking the build for a blocked release platform fails closed with the missing tuple, not "unknown target"', () => {
  assert.throws(() => getTarget('linux-x64-android'), error => {
    assert.match(error.message, /release platform 'linux-x64-android' is blocked/);
    assert.match(error.message, /linux_android_aarch64_cjnative/);
    assert.match(error.message, /android-ndk/);
    assert.doesNotMatch(error.message, /unknown target/);
    return true;
  });
  assert.throws(() => getTarget('plan9-mips'), /unknown target 'plan9-mips'/);
});

// release.yml still spells its five package jobs by hand; they must agree with
// the table so there is one truth about which runner packages which platform.
test('release.yml package jobs agree with the release platform table', () => {
  const release = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
  const jobs = release.split(/\n  (?=[a-z0-9-]+:\n)/).filter(job => job.includes('uses: ./.github/workflows/build-release-package.yml'));
  assert.equal(jobs.length, 5);
  const scalar = (job, key) => job.match(new RegExp(String.raw`^\s*${key}: '?([^'\n]*)'?\s*$`, 'm'))?.[1];
  // Several official packages share a host (linux-x64 also hosts the android,
  // ohos and device-side packages); release.yml builds the plain one, which is
  // the buildable release platform of that host.
  const buildableByHost = new Map(allReleasePlatforms()
    .filter(key => releasePlatformReadiness(key).status === 'buildable')
    .map(key => [getReleasePlatform(key).host, key]));
  for (const job of jobs) {
    const platform = scalar(job, 'platform');
    const key = buildableByHost.get(platform);
    assert.ok(key, `release.yml packages ${platform}, which no buildable release platform uses as host`);
    const readiness = releasePlatformReadiness(key);
    assert.equal(scalar(job, 'runner'), readiness.runner, `${key}: runner`);
    assert.equal(scalar(job, 'llvm_platform'), readiness.llvmPlatform, `${key}: llvm_platform`);
    assert.equal(scalar(job, 'sdk_runtime_dir'), readiness.runtimeTuple, `${key}: sdk_runtime_dir`);
    assert.equal(scalar(job, 'std_artifact'), `final-std-${readiness.host}`, `${key}: std_artifact`);
    const crossTuple = scalar(job, 'cross_std_tuple') || '';
    assert.deepEqual(Object.keys(readiness.crossStd), crossTuple ? [crossTuple] : [], `${key}: cross_std_tuple`);
  }
});
