import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  DAG_REQUIREMENT_PRODUCERS,
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

test('readiness is derived from DAG producers: native and Android packages have DAG producers; other gaps remain named', () => {
  const byStatus = {buildable: [], blocked: [], excluded: []};
  for (const key of allReleasePlatforms()) byStatus[releasePlatformReadiness(key).status].push(key);
  assert.deepEqual(byStatus.buildable, ['linux-x64', 'linux-arm64', 'linux-x64-android', 'darwin-arm64', 'darwin-x64', 'darwin-arm64-android', 'win32-x64', 'win32-x64-android']);
  assert.deepEqual(byStatus.excluded, ['win32-x64-ohos-arm32']);
  assert.equal(byStatus.blocked.length, 5);
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
  assert.throws(() => getTarget('linux-x64-ohos'), error => {
    assert.match(error.message, /release platform 'linux-x64-ohos' is blocked/);
    // The OHOS SDK is installed and probed by the prerequisites job, so the gap this
    // platform still has is the cross-built tuple. Naming the SDK here would be
    // a stale claim, so assert its absence too.
    assert.match(error.message, /linux_ohos_aarch64_cjnative/);
    assert.doesNotMatch(error.message, /ohos-sdk/);
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
  assert.equal(jobs.length, allReleasePlatforms().filter(key => releasePlatformReadiness(key).status === 'buildable').length);
  const scalar = (job, key) => job.match(new RegExp(String.raw`^\s*${key}: '?([^'\n]*)'?\s*$`, 'm'))?.[1];
  const seen = [];
  for (const job of jobs) {
    const platform = scalar(job, 'platform');
    const key = scalar(job, 'release_key');
    seen.push(key);
    assert.ok(key, `release.yml packages ${platform}, which no buildable release platform uses as host`);
    const readiness = releasePlatformReadiness(key);
    assert.equal(platform, readiness.host);
    assert.equal(scalar(job, 'runner'), readiness.runner, `${key}: runner`);
    assert.equal(scalar(job, 'llvm_platform'), readiness.llvmPlatform, `${key}: llvm_platform`);
    assert.equal(scalar(job, 'sdk_runtime_dir'), readiness.runtimeTuple, `${key}: sdk_runtime_dir`);
    assert.equal(scalar(job, 'std_artifact'), `final-std-${readiness.host}`, `${key}: std_artifact`);
    const cross = JSON.parse(scalar(job, 'cross_std_artifacts'));
    assert.deepEqual(Object.keys(readiness.crossStd), cross.map(entry => entry.tuple), `${key}: cross tuples`);
  }
  assert.deepEqual(seen.sort(), allReleasePlatforms().filter(key => releasePlatformReadiness(key).status === 'buildable').sort());
});

// DAG_REQUIREMENT_PRODUCERS is the only thing that lets a `requires <sdk>` line
// leave the readiness reasons, so it must name a stage that really installs and
// probes the SDK. These three tests are the anti-drift guard: each one fails if
// the table claims a producer the workflow does not have, or if the workflow
// stops consuming the table.
test('every runner SDK requirement has a DAG stage that installs and probes it', () => {
  assert.deepEqual(Object.keys(DAG_REQUIREMENT_PRODUCERS).sort(), Object.keys(RELEASE_REQUIREMENTS).sort());
  for (const [requirement, producer] of Object.entries(DAG_REQUIREMENT_PRODUCERS)) {
    assert.ok(producer.job, `${requirement}: producer names no job`);
    assert.ok(producer.action, `${requirement}: producer names no action`);
  }
});

test('each requirement producer resolves to a real job in release-matrix.yml that installs and probes', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/release-matrix.yml'), 'utf8');
  // Split on job boundaries so a job name cannot be matched in a comment or in
  // another job's body. assert.ok(re.test(...)) keeps a failure one line long
  // instead of dumping the whole workflow.
  const jobs = new Map(workflow.split(/\n  (?=[a-z0-9-]+:\n)/).map(job => {
    const name = /^\s*([a-z0-9-]+):\n/.exec(job)?.[1];
    return [name, job];
  }));
  for (const [requirement, producer] of Object.entries(DAG_REQUIREMENT_PRODUCERS)) {
    const job = jobs.get(producer.job);
    assert.ok(job, `${requirement}: release-matrix.yml has no job '${producer.job}'`);
    const checks = [
      [`uses: ${producer.action}`, 'does not use the setup action'],
      ['matrix: ${{ fromJson(needs.plan.outputs.prerequisite_matrix) }}', 'is not fanned out over prerequisite_matrix'],
      ['requirement: ${{ matrix.requirement }}', 'does not pass matrix.requirement to the action'],
      ['verify-runner-sdk.mjs "$SDK_REQUIREMENT"', 'does not run the causal probe harness'],
    ];
    for (const [needle, why] of checks) {
      assert.ok(job.includes(needle), `${requirement}: job '${producer.job}' ${why} (looking for ${needle})`);
    }
  }
  // And the plan must be what emits that matrix, in two places: the plan job
  // forwards it as a step output, and the step writes it into GITHUB_OUTPUT.
  assert.ok(workflow.includes('prerequisite_matrix: ${{ steps.plan.outputs.prerequisite_matrix }}'),
    'the plan job does not forward prerequisite_matrix');
  const matrix = fs.readFileSync(path.join(root, 'ci/release/platform-matrix.mjs'), 'utf8');
  assert.ok(matrix.includes('`prerequisite_matrix=${JSON.stringify({include: plan.prerequisites})}`'),
    'the plan step does not write prerequisite_matrix into GITHUB_OUTPUT');
});

test('the action behind a requirement producer runs both the installer and the probe', () => {
  for (const [requirement, producer] of Object.entries(DAG_REQUIREMENT_PRODUCERS)) {
    const action = fs.readFileSync(path.join(root, producer.action.replace(/^\.\//, ''), 'action.yml'), 'utf8');
    assert.ok(action.includes('ci/release/install-runner-sdk.py "$SDK_REQUIREMENT"'),
      `${requirement}: the action does not run the SDK installer`);
    assert.ok(action.includes('platform-matrix.mjs probe --requirement "$SDK_REQUIREMENT"'),
      `${requirement}: the action does not run the capability probe`);
  }
});

// The acceptance is a difference set, not reasons.length === 0: installing the
// SDK removes exactly the `requires` lines and leaves the cross-tuple ones, so a
// platform can still be blocked for the tuple and say so.
test('a platform whose SDK is installed and probed no longer reports a missing capability', () => {
  const tupleReason = /^tuple \S+_cjnative: /;
  let checkedRequirements = 0;
  for (const key of allReleasePlatforms()) {
    const readiness = releasePlatformReadiness(key);
    for (const requirement of getReleasePlatform(key).requires) {
      checkedRequirements++;
      assert.ok(!readiness.reasons.some(reason => reason.startsWith(`requires ${requirement}:`)),
        `${key}: still claims nothing installs ${requirement}: ${readiness.reasons.join('; ')}`);
    }
    // What is left must be the cross-built tuples (and the device-side gap),
    // never a runner capability. The excluded arm32 package keeps its own line.
    if (readiness.status === 'excluded') {
      assert.match(readiness.reasons[0], /ARM32/, `${key}: excluded without the ARM32 reason`);
      continue;
    }
    for (const reason of readiness.reasons) {
      assert.ok(tupleReason.test(reason) || reason.startsWith('device-side SDK: '),
        `${key}: leftover reason is neither a tuple nor a device-side gap: ${reason}`);
    }
  }
  // Nine uses over nine platforms (the excluded arm32 package also names ohos-sdk,
  // and is held to the same no-stale-claim rule before its own ARM32 line).
  assert.equal(checkedRequirements, 9, 'the requirement uses across the release platform table');
});
