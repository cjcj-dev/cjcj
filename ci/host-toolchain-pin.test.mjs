import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {baseSdkDownload, RELEASE_HOST_TOOLCHAIN} from '../build/lib/release-component-provenance.mjs';
import {
  hostToolchainFromCjcVersion,
  requireHostToolchain,
  requireMatchingBaseSdkToolchain,
} from './host-toolchain-pin.mjs';

const root = path.resolve(import.meta.dirname, '..');
const pinPath = path.join(root, 'ci', 'host_sdk_pin.env');
const cjpmPinPath = path.join(root, 'ci', 'cjpm_pin.env');
const h48LanguagePinPath = path.join(root, 'ci', 'h48_language_tuple_pin.json');
const nightlyLiteral = /nightly-\d+\.\d+\.\d+-alpha\.\d+/;
// Built in pieces so this test source is not itself an undeclared nightly literal.
const h48HostSdk = 'nightly-' + '1.3.0-alpha.' + '20260904010027';
const loadCommand = 'cat ci/cjpm_pin.env >> "$GITHUB_ENV"';
const srcbuildLoadCommand = 'cat ci/host_sdk_pin.env >> "$GITHUB_ENV"';

async function filesBelow(directory) {
  const found = [];
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await filesBelow(target));
    else found.push(target);
  }
  return found;
}

async function hostPin() {
  const text = await fs.readFile(pinPath, 'utf8');
  const match = text.match(/^CJCJ_TOOLCHAIN=(\S+)$/m);
  assert.ok(match, 'ci/host_sdk_pin.env must define CJCJ_TOOLCHAIN');
  return match[1];
}

async function runSrcbuildHostResolver({
  pin,
  runtimeVersion,
  runtimePinVersion = '1.2.0-alpha.fixture',
  staleToolchain = 'nightly-stale',
  readerOnly = false,
}) {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'srcbuild-host-pin-'));
  try {
    const fixtureScript = path.join(fixture, 'tools', 'srcbuild_kkk2.sh');
    await fs.mkdir(path.dirname(fixtureScript), {recursive: true});
    await fs.mkdir(path.join(fixture, 'ci'), {recursive: true});
    await fs.copyFile(path.join(root, 'tools', 'srcbuild_kkk2.sh'), fixtureScript);
    await fs.writeFile(path.join(fixture, 'ci', 'host_sdk_pin.env'), pin);
    await fs.writeFile(path.join(fixture, 'ci', 'cjpm_pin.env'), pin);
    await fs.writeFile(
      path.join(fixture, 'ci', 'runtime_pin.env'),
      `RUNTIME_VERSION=${runtimePinVersion}\n`,
    );
    const command = readerOnly
      ? 'source "$1" --lib-only; read_host_toolchain_pin'
      : 'source "$1" --lib-only; export RUNTIME_VERSION="$2" CJCJ_TOOLCHAIN="$3"; resolve_host_toolchain_pin; printf "%s\\n" "$CJCJ_TOOLCHAIN"';
    return spawnSync('bash', ['-c', command, 'bash', fixtureScript, runtimeVersion, staleToolchain], {
      encoding: 'utf8',
    });
  } finally {
    await fs.rm(fixture, {recursive: true, force: true});
  }
}

test('host toolchain consumers fail closed when the pin was not loaded', () => {
  assert.throws(() => requireHostToolchain({}), /CJCJ_TOOLCHAIN is required/);
  assert.throws(() => requireHostToolchain({CJCJ_TOOLCHAIN: '   '}), /CJCJ_TOOLCHAIN is required/);
});

test('host toolchain consumers accept the value loaded from the sole pin', async () => {
  const pin = await hostPin();
  assert.equal(requireHostToolchain({CJCJ_TOOLCHAIN: pin}), pin);
});

test('ordinary and release host nightly literals use the host pins', async () => {
  const files = [
    ...await filesBelow(path.join(root, 'ci')),
    ...await filesBelow(path.join(root, '.github', 'workflows')),
    ...await filesBelow(path.join(root, 'tools')),
  ];
  const offenders = [];
  for (const file of files) {
    // The astabi behavior-triad evidence harness is pinned to the 1.2 baseline
    // SDK lib paths; it is not an ordinary host consumer.
    const isAstabiBaselineHarness = file === path.join(root, 'tools', 'astabi', 'run_behavior_triad.sh');
    if (file === pinPath || file === cjpmPinPath || file === h48LanguagePinPath || isAstabiBaselineHarness) continue;
    let text = await fs.readFile(file, 'utf8');
    // These are observations of past runs, not inputs to SDK selection.
    // Keep scanning the rest of each record: neither file is a pin exemption.
    if (file === path.join(root, 'ci', 'cangjie-test', 'README.md')) {
      text = text.replace(
        /^(Two consecutive runs of the same SDK \(`)(nightly-\d+\.\d+\.\d+-alpha\.\d+)(`,)$/m,
        '$1$3',
      );
    }
    if (file === path.join(root, 'ci', 'host-runtime', 'release.json')) {
      const record = JSON.parse(text);
      if (record.role === 'official-host-runtime') {
        // host_runtime.mjs emits this identity after setup_sdk loads the pin.
        // Remove only the identity value, preserving any other pin definitions.
        if (typeof record.toolchain === 'string' &&
            /^nightly-\d+\.\d+\.\d+-alpha\.\d+$/.test(record.toolchain)) {
          record.toolchain = '';
        }
        text = JSON.stringify(record);
      }
    }
    if (/nightly-\d+\.\d+\.\d+-alpha\.\d+/.test(text)) {
      offenders.push(path.relative(root, file));
    }
  }
  assert.deepEqual(offenders, []);
  console.log(`ORDINARY-HOST-SCAN offenders=${offenders.length}`);
  const release = await fs.readFile(path.join(root, '.github', 'workflows', 'build-release-package.yml'), 'utf8');
  assert.ok(release.includes(srcbuildLoadCommand));
});

// Run the real scan entry in an isolated tree, not a duplicate classifier.
// The filter prevents these integration controls from recursively spawning.
const scanTestName = 'ordinary and release host nightly literals use the host pins';
const competingSdk = 'nightly-' + '9.9.9-alpha.' + '20990101000000';
const scanControls = [
  ['historical observations', null, null],
  ['shell pin', 'tools/competing-host.sh', () => `CJCJ_TOOLCHAIN=${competingSdk}\n`],
  ['workflow pin', '.github/workflows/competing-host.yml', () => `env:\n  CJCJ_TOOLCHAIN: ${competingSdk}\n`],
  ['env pin', 'ci/competing-host.env', () => `CJCJ_TOOLCHAIN=${competingSdk}\n`],
  ['JSON pin', 'ci/competing-host.json', () => JSON.stringify({toolchain: competingSdk})],
  ['README pin', 'ci/cangjie-test/README.md', text => text + `\nCJCJ_TOOLCHAIN=${competingSdk}\n`],
  ['provenance extra pin', 'ci/host-runtime/release.json', text =>
    JSON.stringify({...JSON.parse(text), CJCJ_TOOLCHAIN: competingSdk})],
  ['provenance nested pin', 'ci/host-runtime/release.json', text =>
    JSON.stringify({...JSON.parse(text), selection: {toolchain: competingSdk}})],
  ['non-provenance role', 'ci/host-runtime/release.json', text =>
    JSON.stringify({...JSON.parse(text), role: 'host-selection'})],
  ['provenance non-identity', 'ci/host-runtime/release.json', text =>
    JSON.stringify({...JSON.parse(text), toolchain: `CJCJ_TOOLCHAIN=${competingSdk}`})],
];
for (const [name, changedFile, mutate] of scanControls) {
  test(`ordinary host scan control: ${name}`, async () => {
    const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'host-scan-'));
    try {
      for (const directory of ['ci', 'tools', '.github/workflows', 'build/lib']) {
        await fs.mkdir(path.join(fixture, directory), {recursive: true});
      }
      for (const relative of [
        'ci/host-toolchain-pin.test.mjs', 'ci/host-toolchain-pin.mjs',
        'ci/host_sdk_pin.env', 'ci/release/base-sdk-identities.json',
        'build/lib/release-component-provenance.mjs',
        'build/lib/targets.mjs', 'build/lib/errors.mjs',
        '.github/workflows/build-release-package.yml',
        'ci/cangjie-test/README.md', 'ci/host-runtime/release.json',
      ]) {
        const destination = path.join(fixture, relative);
        await fs.mkdir(path.dirname(destination), {recursive: true});
        await fs.copyFile(path.join(root, relative), destination);
      }
      if (changedFile) {
        const target = path.join(fixture, changedFile);
        const previous = await fs.readFile(target, 'utf8').catch(error => {
          if (error.code !== 'ENOENT') throw error;
          return '';
        });
        await fs.writeFile(target, mutate(previous));
      }
      const childEnv = {...process.env};
      delete childEnv.NODE_TEST_CONTEXT;
      const result = spawnSync(process.execPath, [
        '--test', '--test-reporter=tap', `--test-name-pattern=^${scanTestName}$`,
        path.join(fixture, 'ci', 'host-toolchain-pin.test.mjs'),
      ], {encoding: 'utf8', timeout: 30_000, env: childEnv});
      assert.ifError(result.error);
      const output = result.stdout + result.stderr;
      assert.equal(result.status, changedFile ? 1 : 0, output);
      if (changedFile) {
        assert.ok(output.includes(changedFile), output);
        assert.match(output, /ERR_ASSERTION/, output);
      } else {
        assert.match(output, /ORDINARY-HOST-SCAN offenders=0/, output);
      }
    } finally {
      await fs.rm(fixture, {recursive: true, force: true});
    }
  });
}

test('release markdown does not carry an ordinary nightly literal', async () => {
  const bounded = [
    'ci/release/H48_LANGUAGE_TUPLE.md',
    'ci/ast_support/README.md',
  ];
  for (const rel of bounded) {
    const text = await fs.readFile(path.join(root, rel), 'utf8');
    assert.doesNotMatch(text, nightlyLiteral, rel);
    console.log(`NIGHTLY-LITERAL-ABSENT ${rel}`);
  }
  const readme = await fs.readFile(path.join(root, 'ci', 'ast_support', 'README.md'), 'utf8');
  assert.equal(readme.includes('20260924001050'), false, 'README must not keep a second flatbuffers SDK timestamp');
});

test('AST workflow and shell install the host pin and carry no nightly literal', async () => {
  const workflowRel = '.github/workflows/build-ast-support.yml';
  const shellRel = 'ci/build_ast_support.sh';
  const workflow = await fs.readFile(path.join(root, workflowRel), 'utf8');
  const shell = await fs.readFile(path.join(root, shellRel), 'utf8');
  console.log(`AST-NIGHTLY-LITERAL-CHECK ${workflowRel}`);
  assert.doesNotMatch(workflow, nightlyLiteral, workflowRel);
  console.log(`AST-NIGHTLY-LITERAL-CHECK ${shellRel}`);
  assert.doesNotMatch(shell, nightlyLiteral, shellRel);
  console.log(`AST-NIGHTLY-LITERAL-ABSENT ${workflowRel} ${shellRel}`);
  assert.match(workflow, /install "\$CJCJ_TOOLCHAIN"/);
  assert.match(workflow, /toolchains\/\$CJCJ_TOOLCHAIN/);
  assert.equal(workflow.includes('AST_FLATBUFFERS_SDK'), false);
  assert.equal(workflow.includes('ast_sdk_pin.env'), false);
  console.log('AST-HOST-PIN-INSTALL load=ci/host_sdk_pin.env install="$CJCJ_TOOLCHAIN" path=$CJCJ_TOOLCHAIN');
});

test('H48 host_sdk stays the published 0904 identity and is absent from workflows', async () => {
  const pin = JSON.parse(await fs.readFile(h48LanguagePinPath, 'utf8'));
  assert.equal(pin.sources.compiler.host_sdk, h48HostSdk);
  const workflowDir = path.join(root, '.github', 'workflows');
  for (const name of await fs.readdir(workflowDir)) {
    if (!name.endsWith('.yml')) continue;
    const text = await fs.readFile(path.join(workflowDir, name), 'utf8');
    assert.equal(text.includes(h48HostSdk), false, name);
  }
  console.log(`H48-HOST-SDK workflows=absent identity=${h48HostSdk}`);
});

test('srcbuild pin reader returns the initial pinned host', async () => {
  const result = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-good\n',
    runtimeVersion: '9.9.9',
    readerOnly: true,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'nightly-good');
});

test('srcbuild resolved host changes only with the pin, not RUNTIME_VERSION', async () => {
  const runtimeA = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-good\n',
    runtimeVersion: '9.9.9',
  });
  const runtimeB = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-good\n',
    runtimeVersion: '8.8.8',
  });
  assert.equal(runtimeA.status, 0, runtimeA.stderr);
  assert.equal(runtimeB.status, 0, runtimeB.stderr);
  assert.notEqual(runtimeA.stdout.trim(), '');
  assert.equal(runtimeB.stdout, runtimeA.stdout);
});

test('srcbuild resolved host does not change with ci/runtime_pin.env', async () => {
  const runtimePinA = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-good\n',
    runtimeVersion: '9.9.9',
    runtimePinVersion: '1.2.0-alpha.first',
  });
  const runtimePinB = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-good\n',
    runtimeVersion: '9.9.9',
    runtimePinVersion: '1.2.0-alpha.second',
  });
  assert.equal(runtimePinA.status, 0, runtimePinA.stderr);
  assert.equal(runtimePinB.status, 0, runtimePinB.stderr);
  assert.equal(runtimePinA.stdout.trim(), 'nightly-good');
  assert.equal(runtimePinB.stdout, runtimePinA.stdout);
});

test('srcbuild pin reader returns a changed pinned host', async () => {
  const result = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=nightly-other\n',
    runtimeVersion: '9.9.9',
    readerOnly: true,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'nightly-other');
});

test('srcbuild rejects a missing pin key instead of retaining stale host state', async () => {
  const result = await runSrcbuildHostResolver({
    pin: 'CJPM_FORK_REF=fixture\n',
    runtimeVersion: '9.9.9',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CJCJ_TOOLCHAIN is missing/);
  assert.equal(result.stdout, '');
});

test('srcbuild pin reader rejects duplicate CJCJ_TOOLCHAIN keys', async () => {
  const result = await runSrcbuildHostResolver({
    pin: 'CJCJ_TOOLCHAIN=one\nCJCJ_TOOLCHAIN=two\n',
    runtimeVersion: '9.9.9',
    readerOnly: true,
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CJCJ_TOOLCHAIN is duplicated in .*ci\/host_sdk_pin\.env/);
  assert.equal(result.stdout, '');
});

test('every workflow host consumer loads ci/cjpm_pin.env after checkout', async () => {
  const expectedLoads = new Map([
    ['build-cjpm.yml', 1],
    ['build-windows-runtime.yml', 1],
    ['ci.yml', 2],
    // colour-runtime consumes the independently pinned H48 release tuple.
    ['platform-matrix.yml', 1],
  ]);
  const workflows = path.join(root, '.github', 'workflows');
  for (const [name, count] of expectedLoads) {
    const text = await fs.readFile(path.join(workflows, name), 'utf8');
    assert.equal(text.split(loadCommand).length - 1, count, name);
  }
  const srcbuild = await fs.readFile(path.join(workflows, 'srcbuild-target.yml'), 'utf8');
  assert.equal(srcbuild.split(srcbuildLoadCommand).length - 1, 1, 'srcbuild-target.yml');


  const windowsRuntime = await fs.readFile(path.join(workflows, 'build-windows-runtime.yml'), 'utf8');
  assert.ok(!windowsRuntime.includes('inputs.toolchain'));
  const platformMatrix = await fs.readFile(path.join(workflows, 'platform-matrix.yml'), 'utf8');
  assert.ok(!platformMatrix.includes('sdk_archive:'));
  assert.ok(!platformMatrix.includes('SDK_ARCHIVE:'));
  const release = await fs.readFile(path.join(workflows, 'release.yml'), 'utf8');
  assert.ok(!release.includes('CJCJ_TOOLCHAIN'));
});

test('base SDK linking rejects a release archive aimed at a differently named host directory', () => {
  assert.throws(() => requireMatchingBaseSdkToolchain({
    hostToolchain: 'nightly-host-control',
    baseSdkToolchain: 'nightly-base-control',
  }), /refusing to link base SDK/);
  assert.equal(requireMatchingBaseSdkToolchain({
    hostToolchain: 'nightly-same-control',
    baseSdkToolchain: 'nightly-same-control',
  }), 'nightly-same-control');
});

test('measured cjc version is converted to the exact nightly identity', () => {
  const version = '1.3.0-alpha.20260831010012';
  assert.equal(hostToolchainFromCjcVersion(
    `Cangjie Compiler: ${version} (cjnative)\nTarget: x86_64-unknown-linux-gnu\n`,
  ), `nightly-${version}`);
  assert.throws(() => hostToolchainFromCjcVersion('not a compiler version'), /did not report/);
});

test('release workflow selects the same host pin for setup and base SDK consumers', async t => {
  const release = await fs.readFile(path.join(root, '.github', 'workflows', 'build-release-package.yml'), 'utf8');
  const script = release.match(/- name: Load release host pin\n        shell: bash\n        run: \|\n((?:          .*\n)+)/)?.[1];
  assert.ok(script, 'release pin loader must exist');
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'release-host-pin-'));
  t.after(() => fs.rm(temporary, {recursive: true, force: true}));
  const githubEnv = path.join(temporary, 'github.env');
  const result = spawnSync('bash', ['-c', script], {
    cwd: root, encoding: 'utf8',
    env: {...process.env, GITHUB_ENV: githubEnv, CJCJ_TOOLCHAIN: 'stale-host', RELEASE_HOST_TOOLCHAIN: 'stale-release'},
  });
  assert.equal(result.status, 0, result.stderr);
  const loaded = Object.fromEntries((await fs.readFile(githubEnv, 'utf8')).trim().split('\n').map(line => line.split('=')));
  const releaseHost = loaded.RELEASE_HOST_TOOLCHAIN;
  const ordinaryHost = await hostPin();
  assert.equal(releaseHost, ordinaryHost, 'release host must equal the host pin');
  assert.equal(loaded.CJCJ_TOOLCHAIN, ordinaryHost, 'setup host must equal the host pin');
  assert.equal(RELEASE_HOST_TOOLCHAIN, ordinaryHost, 'archive selector must equal the host pin');
  for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64']) {
    assert.match(baseSdkDownload(platform, releaseHost).sha256, /^[0-9a-f]{64}$/);
  }
  assert.throws(() => baseSdkDownload('linux-x64', 'nightly-unregistered'), /no pinned archive identity/);
  assert.throws(() => baseSdkDownload('unsupported', releaseHost), /unsupported base SDK platform/);
  assert.match(release, /--toolchain "\$RELEASE_HOST_TOOLCHAIN"/);
  assert.match(release, /--base-sdk-id "\$RELEASE_HOST_TOOLCHAIN"/);
});

test('both JavaScript entry points require the loaded environment value', async () => {
  for (const name of ['ci/setup_sdk.mjs', 'ci/platform_matrix/build_cjcj.mjs']) {
    const text = await fs.readFile(path.join(root, name), 'utf8');
    assert.ok(text.includes('requireHostToolchain()'), name);
    assert.ok(!text.includes('process.env.CJCJ_TOOLCHAIN ||'), name);
  }
});

// Both host roles use the latest official nightly. Keep their existing loader
// sets explicit so updating a pin cannot silently disconnect a workflow.
// Enumerate definitions from git to discover undeclared additional pins.
const HOST_TOOLCHAIN_PINS = Object.freeze({
  'ci/cjpm_pin.env': Object.freeze({
    host: 'ordinary CI build host',
    loaders: Object.freeze(['build-cjpm.yml', 'build-windows-runtime.yml', 'ci.yml', 'objc-darwin-e2e.yml', 'platform-matrix.yml']),
  }),
  'ci/host_sdk_pin.env': Object.freeze({
    host: 'source-build host',
    // ci.yml/package-tests installs the official test SDK and keys its shim
    // sccache on the same pin, so ci.yml loads this file and not cjpm_pin.env.
    loaders: Object.freeze(['build-ast-support.yml', 'build-darwin-std.yml', 'build-host-runtime.yml',
      'build-release-package.yml', 'ci.yml', 'measure-darwin-host-sdk.yml', 'srcbuild-target.yml']),
  }),
});

test('ordinary CI and source-build hosts use the same nightly', async () => {
  const ordinary = await fs.readFile(cjpmPinPath, 'utf8');
  const definitions = ordinary.match(/^CJCJ_TOOLCHAIN=\S+$/gm) ?? [];
  assert.equal(definitions.length, 1, 'ordinary host must define exactly one toolchain');
  assert.equal(definitions[0].slice('CJCJ_TOOLCHAIN='.length), await hostPin(),
    'CJCJ_TOOLCHAIN must be equal in ci/cjpm_pin.env and ci/host_sdk_pin.env');
});

test('every CJCJ_TOOLCHAIN definition names a host and has measured consumers', async () => {
  const tracked = spawnSync('git', ['-C', root, 'ls-files', '-z'], {encoding: 'utf8'});
  assert.equal(tracked.status, 0, tracked.stderr);
  const files = tracked.stdout.split('\0').filter(Boolean);
  assert.ok(files.length > 100, `git ls-files found ${files.length} files; discovery is broken`);

  const definitions = [];
  for (const file of files) {
    let text;
    try {
      text = await fs.readFile(path.join(root, file), 'utf8');
    } catch {
      continue;
    }
    if (/^CJCJ_TOOLCHAIN=/m.test(text)) definitions.push(file);
  }
  assert.deepEqual(definitions.sort(), Object.keys(HOST_TOOLCHAIN_PINS).sort(),
    'a CJCJ_TOOLCHAIN definition appeared or vanished; give each one a host and its consumers here');

  // The half that makes deleting a pin red rather than quiet: each definition
  // is loaded by exactly the workflows recorded against it, and by no others.
  const workflowDir = path.join(root, '.github', 'workflows');
  const workflowNames = (await fs.readdir(workflowDir)).filter(name => name.endsWith('.yml')).sort();
  for (const [file, {host, loaders}] of Object.entries(HOST_TOOLCHAIN_PINS)) {
    const text = await fs.readFile(path.join(root, file), 'utf8');
    assert.match(text, /^CJCJ_TOOLCHAIN=nightly-\S+$/m, `${file} (${host}) must pin an exact nightly`);
    const load = `cat ${file} >> "$GITHUB_ENV"`;
    const observed = [];
    for (const name of workflowNames) {
      if ((await fs.readFile(path.join(workflowDir, name), 'utf8')).includes(load)) observed.push(name);
    }
    assert.deepEqual(observed, [...loaders],
      `${file} is the ${host} pin; its loader set changed, so either a consumer lost its pin or gained one`);
    assert.ok(observed.length > 0, `${file} has no consumer; delete it or wire it, do not leave it readable`);
    console.log(`HOST-TOOLCHAIN-PIN ${file} host="${host}" loaders=${observed.join(',')}`);
  }
});
