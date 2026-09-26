import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {checkPlatform, planMatrix, probeRequirement, runnerHost, selectPlatforms} from './platform-matrix.mjs';
import {allReleasePlatforms, getReleasePlatform, RELEASE_REQUIREMENTS} from '../../build/lib/targets.mjs';

const script = path.resolve(import.meta.dirname, 'platform-matrix.mjs');
const run = args => spawnSync(process.execPath, [script, ...args], {encoding: 'utf8'});

test('probe CLI reports SDK capability independently of blocked cross-build readiness', t => {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'release-probe-'));
  t.after(() => fs.rmSync(sdk, {recursive: true, force: true}));
  const env = {...process.env, OHOS_SDK_HOME: sdk, OHOS_NDK_HOME: '', HOS_SDK_HOME: ''};
  const probe = () => spawnSync(process.execPath, [script, 'probe', '--requirement', 'ohos-sdk'], {env, encoding: 'utf8'});
  const absent = probe();
  assert.equal(absent.status, 1, absent.stderr);
  assert.match(absent.stdout, /^MISSING ohos-sdk:/);
  fs.mkdirSync(path.join(sdk, 'native/llvm/bin'), {recursive: true});
  const present = probe();
  assert.equal(present.status, 0, present.stderr);
  assert.match(present.stdout, /^PRESENT ohos-sdk:/);
  const check = spawnSync(process.execPath, [script, 'check', '--platform', 'linux-x64-ohos'], {env, encoding: 'utf8'});
  assert.equal(check.status, 1, 'SDK presence must not invent cross-build producers');
  assert.match(check.stderr, /BLOCKED tuple linux_ohos_aarch64_cjnative:/);
});

test('probe CLI refuses absent and unknown requirement names', () => {
  assert.equal(run(['probe']).status, 2);
  assert.equal(run(['probe', '--requirement', 'unknown-sdk']).status, 2);
});

test('SDK input jobs cover the selected runner/requirement pairs and exclude abandoned ARM32', () => {
  const expected = new Set(allReleasePlatforms().filter(key => !getReleasePlatform(key).excluded)
    .flatMap(key => {
      const platform = getReleasePlatform(key);
      return platform.requires.map(requirement => `${platform.runner}/${requirement}`);
    }));
  const actual = planMatrix('all').prerequisites.map(row => `${row.runner}/${row.requirement}`);
  assert.deepEqual(new Set(actual), expected);
  assert.equal(actual.length, expected.size, 'shared runner SDKs install once');
  assert.deepEqual(planMatrix('win32-x64-ohos-arm32').prerequisites, []);
  assert.deepEqual(planMatrix('linux-x64-android').prerequisites,
    [{runner: 'ubuntu-24.04', requirement: 'android-ndk'}]);
});

test('phased release source and package sets equal the buildable matrix', () => {
  const workflow = fs.readFileSync(path.resolve(import.meta.dirname, '../../.github/workflows/release.yml'), 'utf8');
  const source = [...workflow.matchAll(/^      targets: (\S+)$/gm)].map(match => match[1]);
  const packages = [...workflow.matchAll(/^      release_key: (\S+)$/gm)].map(match => match[1]);
  const plan = planMatrix('all');
  assert.deepEqual(source.sort(), plan.source.map(row => row.target).sort(), 'source symmetric difference');
  assert.deepEqual(packages.sort(), plan.package.map(row => row.release_key).sort(), 'package symmetric difference');
});

test('plan for all fourteen platforms: four source cells, eight packages, five blocked, one excluded', () => {
  const plan = planMatrix('all');
  assert.deepEqual(plan.source.map(row => row.target).sort(), ['darwin-arm64', 'darwin-x64', 'linux-aarch64', 'linux-x64']);
  assert.deepEqual(plan.package.map(row => row.release_key), ['linux-x64', 'linux-arm64', 'linux-x64-android', 'darwin-arm64', 'darwin-x64', 'darwin-arm64-android', 'win32-x64', 'win32-x64-android']);
  assert.equal(plan.blocked.length, 5);
  assert.deepEqual(plan.excluded.map(row => row.release_key), ['win32-x64-ohos-arm32']);
  assert.equal(plan.windowsSide, true);
  for (const row of plan.blocked) {
    assert.match(row.runner, /^(ubuntu|macos|windows)-/);
    assert.ok(row.reasons.length > 0, `${row.release_key}: empty reasons`);
  }
});

test('package rows carry exactly the inputs build-release-package.yml takes, spelled as release.yml spells them', () => {
  const rows = new Map(planMatrix('all').package.map(row => [row.release_key, row]));
  assert.deepEqual(rows.get('linux-x64'), {
    release_key: 'linux-x64', platform: 'linux-x64', runner: 'ubuntu-24.04', llvm_platform: 'linux_x86_64',
    sdk_runtime_dir: 'linux_x86_64_cjnative', compiler_artifact: 'final-compiler-linux-x64',
    std_artifact: 'final-std-linux-x64',
    cross_std_artifacts: JSON.stringify([{tuple: 'windows_x86_64_cjnative', artifact: 'final-std-windows-x64'}]), host_std_cross_built: 'false',
  });
  assert.deepEqual(rows.get('win32-x64'), {
    release_key: 'win32-x64', platform: 'windows-x64', runner: 'windows-2025', llvm_platform: 'windows_x86_64',
    sdk_runtime_dir: 'windows_x86_64_cjnative', compiler_artifact: '', std_artifact: 'final-std-windows-x64',
    cross_std_artifacts: '[]', host_std_cross_built: 'true',
  });
  assert.equal(rows.get('darwin-arm64').runner, 'macos-15');
  assert.equal(rows.get('darwin-x64').runner, 'macos-15-intel');
  assert.equal(rows.get('linux-arm64').runner, 'ubuntu-24.04-arm');
});

test('selecting a consumer selects the source cells it needs and nothing else', () => {
  const windows = planMatrix('win32-x64');
  assert.deepEqual(windows.source.map(row => row.target), ['linux-x64'], 'the Windows std comes from the linux-x64 cell');
  assert.equal(windows.windowsSide, true);
  const arm = planMatrix('linux-arm64');
  assert.deepEqual(arm.source.map(row => row.target).sort(), ['linux-aarch64', 'linux-x64'], 'linux-arm64 embeds the Windows cross std built on linux-x64');
  assert.equal(arm.windowsSide, false);
  assert.deepEqual(arm.package.map(row => row.release_key), ['linux-arm64']);
  const darwin = planMatrix('darwin-arm64');
  assert.deepEqual(darwin.source.map(row => row.target), ['darwin-arm64']);
  assert.equal(darwin.windowsSide, false);
});

test('a blocked-only selection still produces a plan with a red cell, and an unknown key is refused', () => {
  const blocked = planMatrix('linux-x64-ohos');
  assert.deepEqual(blocked.source, []);
  assert.deepEqual(blocked.package, []);
  assert.equal(blocked.blocked.length, 1);
  assert.match(blocked.blocked[0].reasons, /linux_ohos_aarch64_cjnative/);
  assert.throws(() => selectPlatforms('linux-x64,plan9'), /unknown release platform\(s\): plan9/);
  assert.throws(() => planMatrix(' , '), /no release platform selected/);
});

test('runner labels resolve to the platform and architecture the host contract needs', () => {
  assert.deepEqual(runnerHost('ubuntu-24.04'), {platform: 'linux', arch: 'x64'});
  assert.deepEqual(runnerHost('ubuntu-24.04-arm'), {platform: 'linux', arch: 'arm64'});
  assert.deepEqual(runnerHost('macos-15'), {platform: 'darwin', arch: 'arm64'});
  assert.deepEqual(runnerHost('macos-15-intel'), {platform: 'darwin', arch: 'x64'});
  assert.deepEqual(runnerHost('windows-2025'), {platform: 'win32', arch: 'x64'});
  assert.throws(() => runnerHost('plan9-latest'), /unknown runner label/);
});

test('check on the right host passes for a buildable platform and fails naming the mismatch on the wrong one', () => {
  const ok = checkPlatform('linux-x64', {platform: 'linux', arch: 'x64', env: {}});
  assert.equal(ok.ok, true, ok.problems.join('\n'));
  const wrong = checkPlatform('linux-arm64', {platform: 'linux', arch: 'x64', env: {}});
  assert.equal(wrong.ok, false);
  assert.match(wrong.problems[0], /HOST mismatch: runner ubuntu-24.04-arm is linux\/arm64, this job runs on linux\/x64/);
});

test('check on a blocked platform is red even when the runner has the capability, and says what is missing', () => {
  const ndk = fs.mkdtempSync(path.join(os.tmpdir(), 'ndk-'));
  fs.mkdirSync(path.join(ndk, 'toolchains/llvm/prebuilt'), {recursive: true});
  const present = checkPlatform('linux-x64-android', {platform: 'linux', arch: 'x64', env: {ANDROID_NDK_ROOT: ndk}});
  assert.equal(present.ok, true);
  assert.ok(present.lines.some(line => line.startsWith('PRESENT android-ndk:')), present.lines.join('\n'));
  assert.deepEqual(present.problems, []);
  const absent = checkPlatform('linux-x64-android', {platform: 'linux', arch: 'x64', env: {}});
  assert.ok(absent.problems.some(problem => /^MISSING android-ndk: Android NDK/.test(problem)), absent.problems.join('\n'));
});

test('capability probes read the documented variables and markers', () => {
  const sdk = fs.mkdtempSync(path.join(os.tmpdir(), 'ohos-'));
  assert.equal(probeRequirement('ohos-sdk', {OHOS_SDK_HOME: sdk}).present, false, 'a directory without native/llvm/bin is not an SDK');
  fs.mkdirSync(path.join(sdk, 'native/llvm/bin'), {recursive: true});
  assert.equal(probeRequirement('ohos-sdk', {OHOS_NDK_HOME: sdk}).present, true);
  const xcrun = (cmd, args) => {
    assert.equal(cmd, 'xcrun');
    if (args[1] === 'iphoneos') return '/Applications/Xcode.app/.../iPhoneOS.sdk\n';
    throw new Error('no simulator sdk');
  };
  const ios = probeRequirement('xcode-ios', {}, xcrun);
  assert.equal(ios.present, false);
  assert.match(ios.detail, /iphonesimulator/);
  assert.throws(() => probeRequirement('quantum-sdk'), /unknown requirement/);
});

test('the CLI writes GITHUB_OUTPUT lines the workflow fans out over', () => {
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'plan-')), 'output');
  const result = run(['plan', '--platforms', 'linux-x64,linux-x64-android', '--github-output', out]);
  assert.equal(result.status, 0, result.stderr);
  const lines = Object.fromEntries(fs.readFileSync(out, 'utf8').trim().split('\n').map(line => line.split(/=(.*)/s).slice(0, 2)));
  assert.equal(lines.selected, 'linux-x64,linux-x64-android');
  assert.deepEqual(JSON.parse(lines.source_matrix), {include: [{target: 'linux-x64'}]});
  assert.deepEqual(JSON.parse(lines.package_matrix).include.map(row => row.release_key), ['linux-x64', 'linux-x64-android']);
  assert.deepEqual(JSON.parse(lines.blocked_matrix).include, []);
  assert.equal(lines.package_keys, 'linux-x64,linux-x64-android');
  assert.equal(lines.has_source, 'true');
  assert.equal(lines.has_blocked, 'false');
  assert.equal(lines.has_prerequisites, 'true');
  assert.deepEqual(JSON.parse(lines.prerequisite_matrix).include,
    [{runner: 'ubuntu-24.04', requirement: 'android-ndk'}]);
  assert.equal(lines.windows_side, 'false');
  const bad = run(['plan', '--platforms', 'plan9']);
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /unknown release platform/);
  const blocked = run(['check', '--platform', 'ohos-arm64']);
  assert.equal(blocked.status, 1);
  assert.match(blocked.stderr, /device-side SDK/);
});

test('every requirement has an installer export to cut, drawn from the probe candidates', () => {
  const installer = fs.readFileSync(path.resolve(import.meta.dirname, 'install-runner-sdk.py'), 'utf8');
  const exported = new Set(['android-ndk', 'ohos-sdk', 'xcode-ios'].map(requirement => {
    const contract = RELEASE_REQUIREMENTS[requirement];
    const candidates = contract.envCandidates ?? ['DEVELOPER_DIR'];
    const hit = candidates.filter(variable =>
      new RegExp(`^\\s*export\\('${variable}'.*$`, 'm').test(installer));
    assert.ok(hit.length > 0, `${requirement}: no export line for any of ${candidates.join('/')}`);
    return hit[0];
  }));
  assert.deepEqual([...exported].sort(), ['ANDROID_NDK_ROOT', 'DEVELOPER_DIR', 'OHOS_SDK_HOME']);
  // Each exported name is one the probe itself reads, so a disconnected export
  // can only turn the probe red through the documented candidate list.
  for (const name of exported) {
    assert.ok(Object.values(RELEASE_REQUIREMENTS).some(contract => contract.envCandidates?.includes(name))
      || name === 'DEVELOPER_DIR', `${name}: not a probe candidate`);
  }
});

test('the SDK identity record hashes file content, never a path', () => {
  const harness = fs.readFileSync(path.resolve(import.meta.dirname, 'verify-runner-sdk.mjs'), 'utf8');
  // Every digest in the harness is fed either a call (contentSha/textSha read
  // their argument) or one of the text variables below. A path variable is not
  // on the list: hashing one would hash the name of a file, not the file.
  const textVariables = ['text', 'source'];
  const digestArguments = [...harness.matchAll(/createHash\('sha256'\)\.update\(([^;]*?)\)\.digest/g)]
    .map(([, argument]) => argument.trim());
  assert.ok(digestArguments.length > 0, 'no digest found; the guard would be vacuous');
  for (const argument of digestArguments) {
    const source = argument.includes('(') ? 'call' : `variable ${argument}`;
    assert.ok(argument.includes('(') || textVariables.includes(argument),
      `digest reads a ${source}, not file content`);
  }
  const contentHashes = [...harness.matchAll(/contentSha\(([^)]*)\)/g)].map(([, argument]) => argument.trim());
  assert.ok(contentHashes.length >= 4, `expected the three arms plus the check, found ${contentHashes.length}`);
  assert.ok(harness.includes('const contentSha = (file) => createHash(\'sha256\').update(fs.readFileSync(file))'),
    'contentSha must read the file it names');
  // The three arms are recorded with their paths beside them, and the real entry
  // refuses a record whose identity equals its own path string.
  for (const field of ['candidate', 'cut', 'restored']) {
    assert.ok(new RegExp(`${field}: \\{path: \\w+, sha256: \\w+InstallerSha256, pathStringSha256: textSha\\(\\w+\\)\\}`, 'm')
      .test(harness), `${field}: no {path, sha256, pathStringSha256} identity record`);
  }
  assert.ok(harness.includes('the identity is not the path string'),
    'the entry does not judge a record against its own path string');
  assert.ok(harness.includes("'restored-export: the export is back'"),
    'the export face has no restored arm');
});

test('the export reader drops the carriage return of a CRLF GITHUB_ENV line', () => {
  const harness = fs.readFileSync(path.resolve(import.meta.dirname, 'verify-runner-sdk.mjs'), 'utf8');
  // The installer writes GITHUB_ENV in the platform's text mode, so a Windows
  // value arrives as `NAME=D:\path\r`. Splitting on a bare newline would put
  // that carriage return inside the SDK path and the probe would read the
  // directory as missing.
  assert.ok(harness.includes("split(/\\r?\\n/)"), 'GITHUB_ENV lines are split on a bare newline');
  assert.ok(harness.includes("'restored-export: the export is back'"),
    'nothing judges the value the restored export actually carried');
});
