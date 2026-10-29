import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {baseSdkDownload, RELEASE_HOST_TOOLCHAIN} from '../build/lib/release-component-provenance.mjs';
import {
  hostToolchainFromCjcVersion,
  parseHostToolchainPin,
  readHostToolchainPin,
  requireHostToolchain,
  requireMatchingBaseSdkToolchain,
} from './host-toolchain-pin.mjs';

const root = path.resolve(import.meta.dirname, '..');
const pinPath = path.join(root, 'ci', 'host_sdk_pin.env');
const cjpmPinPath = path.join(root, 'ci', 'source_pin.env');
const h48LanguagePinPath = path.join(root, 'ci', 'h48_language_tuple_pin.json');
const nightlyLiteral = /nightly-\d+\.\d+\.\d+-alpha\.\d+/;
// Built in pieces so this test source is not itself an undeclared nightly literal.
const h48HostSdk = 'nightly-' + '1.3.0-alpha.' + '20260904010027';
const loadCommand = 'cat ci/source_pin.env >> "$GITHUB_ENV"';
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
  return parseHostToolchainPin(await fs.readFile(pinPath, 'utf8'));
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
    const fixtureScript=path.join(fixture,'ci/host-toolchain-pin.mjs');
    await fs.mkdir(path.dirname(fixtureScript),{recursive:true});
    await fs.copyFile(path.join(root,'ci/host-toolchain-pin.mjs'),fixtureScript);
    const file=path.join(fixture,'ci/host_sdk_pin.env');await fs.writeFile(file,pin);
    await fs.writeFile(path.join(fixture,'ci/runtime_pin.env'),`RUNTIME_VERSION=${runtimePinVersion}\n`);
    return spawnSync(process.execPath,[fixtureScript,'--file',file],{encoding:'utf8',
      env:{...process.env,RUNTIME_VERSION:runtimeVersion,CJCJ_TOOLCHAIN:staleToolchain}});

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
  assert.ok(release.includes('name: cjcj-srcbuild-${{ inputs.platform }}-${{ inputs.version }}'));
  assert.doesNotMatch(release, /setup_sdk|prepare_base_sdk/);
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
        'ci/host-toolchain-pin.test.mjs', 'ci/host-toolchain-pin.mjs', 'ci/vendor/js-yaml/js-yaml.mjs',
        'ci/host_sdk_pin.env', 'ci/release/base-sdk-identities.json',
        'build/lib/release-component-provenance.mjs', 'ci/release/source-tool-payloads.mjs',
        'ci/bootstrap/sdk-platform.mjs', 'ci/bootstrap/sdk-io.mjs', 'ci/bootstrap/sdk-flow.mjs',
        'ci/bootstrap/sdk-command-lifetime.mjs', 'ci/bootstrap/sdk-std-resume.mjs',
        'ci/bootstrap/sdk-source.mjs', 'ci/bootstrap/sdk-install-entries.mjs', 'ci/build-resources.mjs',
        'build/lib/targets.mjs', 'build/lib/errors.mjs', 'build/srcbuild/tool-layout.mjs',
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
    pin: 'TOOLS_REF=fixture\n',
    runtimeVersion: '9.9.9',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsupported host toolchain pin record|must define exactly one CJCJ_TOOLCHAIN/);
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

test('every workflow host consumer loads ci/source_pin.env after checkout', async () => {
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

test('release consumes native installs while official archive selectors retain the declared host pin', async () => {
  const release = await fs.readFile(path.join(root, '.github/workflows/build-release-package.yml'), 'utf8');
  assert.doesNotMatch(release, /Load release host pin|prepare_base_sdk|setup_sdk/);
  assert.ok(release.includes('run: node ci/release/compose-package.mjs'));
  assert.equal(RELEASE_HOST_TOOLCHAIN, await hostPin());
  for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64'])
    assert.match(baseSdkDownload(platform, readHostToolchainPin(platform)).sha256, /^[0-9a-f]{64}$/);
  assert.throws(() => baseSdkDownload('linux-x64', 'nightly-unregistered'), /no pinned archive identity/);
  assert.throws(() => baseSdkDownload('unsupported', RELEASE_HOST_TOOLCHAIN), /unsupported base SDK platform/);
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
  'ci/host_sdk_pin.env': Object.freeze({
    host: 'ordinary CI and source-build host',
    loaders: Object.freeze(['build-ast-support.yml', 'build-host-runtime.yml', 'srcbuild-target.yml']),
  }),
});

test('ordinary CI and source-build hosts use the sole nightly pin', async () => {
  const ordinary = await fs.readFile(cjpmPinPath, 'utf8');
  assert.doesNotMatch(ordinary, /^CJCJ_TOOLCHAIN(?:_[A-Z0-9_]+)?=/m,
    'cjpm source selection must not duplicate the host nightly');
  for (const name of ['build-cjpm.yml', 'build-windows-runtime.yml', 'ci.yml', 'objc-darwin-e2e.yml', 'platform-matrix.yml']) {
    const workflow = loadYaml(await fs.readFile(path.join(root, '.github/workflows', name), 'utf8'));
    for (const job of Object.values(workflow.jobs)) for (const step of job.steps || []) {
      if (!step.run?.includes(loadCommand)) continue;
      assert.match(step.run, /node ci\/host-toolchain-pin\.mjs/, name+' must resolve its host in the cjpm load step');
      assert.match(step.run, /(?:--github-env|echo "CJCJ_TOOLCHAIN=\$CJCJ_TOOLCHAIN")/, name+' must export the resolved host');
    }
  }
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

async function workflowStep(workflow, job, name) {
  const text = await fs.readFile(path.join(root, '.github/workflows', workflow), 'utf8');
  const step = loadYaml(text).jobs[job].steps.find(step => step.name === name);
  assert.ok(step?.run, `${workflow}: ${name} must remain executable`);
  return step.run;
}

const independentHostVersions = Object.freeze({
  linux_x86_64: '1.3.0-alpha.20261025001053',
  linux_aarch64: '1.3.0-alpha.20261025001053',
  darwin_x86_64: '1.3.0-alpha.20261025001053',
  darwin_aarch64: '1.3.0-alpha.20261025001053',
  windows_x86_64: '1.3.0-alpha.20261025001053',
});

for (const [platform, version] of Object.entries(independentHostVersions)) {
  test(`AST independent expected and real CLI producer agree for execution host ${platform}`, async () => {
    // The expectation comes from fixed declarations, independently of the CLI.
    const declared = Object.fromEntries((await fs.readFile(pinPath, 'utf8')).split('\n')
      .filter(line => line.includes('=')).map(line => line.split('=')));
    const expected = declared['CJCJ_TOOLCHAIN_' + platform.toUpperCase()] || declared.CJCJ_TOOLCHAIN;
    assert.equal(expected, 'nightly-' + version);
    if (platform === 'linux_x86_64') {
      const harness = await fs.readFile(path.join(root, 'ci/test_ast_host_workflow.py'), 'utf8');
      assert.ok(harness.includes("expected = 'nightly-' + '" + version + "'"), 'AST must use its independent expectation');
      assert.ok(harness.includes("'ci/host-toolchain-pin.mjs', 'ci/test_ast_host_workflow.py'"), 'AST input evidence must include its real producer');
    }
    const actual = spawnSync(process.execPath, ['ci/host-toolchain-pin.mjs', '--platform', platform],
      {cwd: root, encoding: 'utf8'});
    assert.equal(actual.status, 0, actual.stderr);
    console.log(`ASSERT_AST_INDEPENDENT_HOST ${platform} actual=${actual.stdout.trim()} expected=${expected}`);
    assert.equal(actual.stdout.trim(), expected);
  });
}

test('Windows cross workflow retains the Linux execution host after its second pin load', async t => {
  if (process.platform !== 'linux' || process.arch !== 'x64') return t.skip('Linux x64 execution-host workflow');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'windows-host-load-'));
  t.after(() => fs.rm(work, {recursive: true, force: true}));
  const githubEnv = path.join(work, 'github.env');
  for (const name of ['Load host toolchain pin', 'Load compiler pins']) {
    const script = await workflowStep('build-windows-runtime.yml', 'build-runtime', name);
    const run = spawnSync('bash', ['--noprofile', '--norc', '-euo', 'pipefail', '-c', script], {
      cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_ENV: githubEnv},
    });
    assert.equal(run.status, 0, run.stderr);
    const env = Object.fromEntries((await fs.readFile(githubEnv, 'utf8')).trim().split('\n')
      .filter(line => line && !line.startsWith('#')).map(line => line.split(/=(.*)/s).slice(0, 2)));
    console.log(`ASSERT_WINDOWS_EXECUTION_HOST step=${name} actual=${env.CJCJ_TOOLCHAIN}`);
    assert.equal(env.CJCJ_TOOLCHAIN, 'nightly-' + independentHostVersions.linux_x86_64);
  }
});

test('Android candidate installs the execution host before the lineage consumer', async () => {
  const script = await workflowStep('android-runtime.yml', 'runtime', 'Install official lineage test input');
  assert.match(script, /source ci\/host_sdk_pin\.env/);
  assert.match(script, /CJCJ_TOOLCHAIN="\$\(node ci\/host-toolchain-pin\.mjs\)"\nexport CJCJ_TOOLCHAIN/);
  assert.ok(script.indexOf('node ci/host-toolchain-pin.mjs') < script.indexOf('"$cjv_bin" install "$CJCJ_TOOLCHAIN"'));
  const workflow = loadYaml(await fs.readFile(path.join(root, '.github/workflows/android-runtime.yml'), 'utf8'));
  assert.deepEqual(workflow.jobs.runtime.strategy.matrix.arm, ['candidate', 'cut', 'restored']);
  const verify = workflow.jobs.runtime.steps.find(step => step.name === 'Verify Android release and pin contracts');
  assert.match(verify.run, /build\/test\/package-provenance\.test\.mjs/);
  assert.equal(verify.if, "matrix.arm == 'candidate'");
});

// Execute the actual workflow handoff under GitHub's Bash options. Stop at the
// first installer/environment consumer: these contracts qualify the handoff,
// without downloading or installing an SDK during the Node gate.
test('workflow host pin assignment preserves parser failure and exported success', async t => {
  const sites = [];
  for (const file of await fs.readdir(path.join(root, '.github/workflows'))) {
    if (!file.endsWith('.yml')) continue;
    const workflow = loadYaml(await fs.readFile(path.join(root, '.github/workflows', file), 'utf8'));
    for (const [job, definition] of Object.entries(workflow.jobs)) {
      for (const step of definition.steps ?? []) {
        if (!step.run?.includes('$(node ci/host-toolchain-pin.mjs)')) continue;
        const lines = step.run.trimEnd().split('\n');
        const assignment = lines.findIndex(line => line.includes('$(node ci/host-toolchain-pin.mjs)'));
        const start = lines.findLastIndex((line, i) => i < assignment && line === 'source ci/host_sdk_pin.env');
        assert.ok(start >= 0, `${file}:${job} must load its actual pin`);
        let end = assignment + 1;
        if (lines[end] === 'export CJCJ_TOOLCHAIN') end++;
        sites.push({file, job, name: step.name, handoff: lines.slice(start, end).join('\n'), consumer: lines[end]});
      }
    }
  }
  assert.deepEqual(sites.map(({file, job}) => `${file}:${job}`).sort(), [
    'android-runtime.yml:runtime', 'build-cjpm.yml:build-cjpm', 'ci.yml:contracts', 'test-host-identities.yml:aarch64',
  ].sort(), 'all workflow command-substitution host loaders must be exercised');
  for (const site of sites) {
    for (const invalid of [false, true]) {
      await t.test(`${site.file}:${site.job} ${invalid ? 'parser failure' : 'exported success'}`, async () => {
        const work = await fs.mkdtemp(path.join(os.tmpdir(), 'workflow-host-handoff-'));
        try {
          await fs.mkdir(path.join(work, 'ci'));
          await fs.copyFile(path.join(root, 'ci/host-toolchain-pin.mjs'), path.join(work, 'ci/host-toolchain-pin.mjs'));
          const pin = await fs.readFile(pinPath, 'utf8');
          await fs.writeFile(path.join(work, 'ci/host_sdk_pin.env'), pin + (invalid ? '\nCJCJ_TOOLCHAIN_UNKNOWN=invalid\n' : ''));
          const env = {...process.env};
          delete env.CJCJ_TOOLCHAIN;
          const parser = spawnSync(process.execPath, ['ci/host-toolchain-pin.mjs'], {cwd: work, env, encoding: 'utf8'});
          const observer = 'node -e \'console.log("HOST_HANDOFF_CONSUMED=" + JSON.stringify(process.env.CJCJ_TOOLCHAIN))\'';
          const result = spawnSync('bash', ['--noprofile', '--norc', '-euo', 'pipefail', '-x', '-c', `${site.handoff}\n${observer}`], {
            cwd: work, env, encoding: 'utf8',
          });
          console.log(`TARGET_HOST_HANDOFF ${JSON.stringify({...site, invalid, parserRc: parser.status, shellRc: result.status, stdout: result.stdout, stderr: result.stderr})}`);
          assert.ifError(parser.error);
          assert.ifError(result.error);
          if (invalid) {
            assert.equal(parser.status, 1, parser.stderr);
            assert.equal(result.status, parser.status, 'workflow must preserve the real parser exit status');
            assert.equal(result.stdout, '', 'failed pin must stop before the environment consumer');
          } else {
            assert.equal(parser.status, 0, parser.stderr);
            assert.equal(result.status, 0, result.stderr);
            assert.equal(result.stdout.trim(), `HOST_HANDOFF_CONSUMED=${JSON.stringify(parser.stdout.trim())}`,
              'the real parser result must reach the child environment unchanged');
          }
        } finally {
          await fs.rm(work, {recursive: true, force: true});
        }
      });
    }
  }
});

// These steps run on Linux (including the Windows cross-build) or on a native
// matrix host. Execute their actual shell text; a successful parser must win
// over the generic record before a later installer or cache consumer runs.
test('workflow GitHub environment loaders resolve the execution host and stop on reader failure', async t => {
  const sites = [
    ['build-ast-support.yml', 'build', 'Load host toolchain pin'],
    ['objc-darwin-e2e.yml', 'objc-darwin-e2e', 'Load pins'],
    ['build-windows-runtime.yml', 'build-runtime', 'Load host toolchain pin'],
    ['build-windows-runtime.yml', 'build-runtime', 'Load compiler pins'],
    ['ci.yml', 'build', 'Load host toolchain pin'],
    ['ci.yml', 'provision', 'Load host toolchain pin'],
    ['platform-matrix.yml', 'platform', 'Load host toolchain pin'],
    ['srcbuild-target.yml', 'source-stage0', 'Load host toolchain pin'],
  ];
  for (const [file, job, name] of sites) {
    const script = await workflowStep(file, job, name);
    for (const arm of ['normal', 'bad-pin', 'missing-reader']) {
      await t.test(`${file}:${job}:${name} ${arm}`, async () => {
        const work = await fs.mkdtemp(path.join(os.tmpdir(), 'github-host-loader-'));
        try {
          await fs.mkdir(path.join(work, 'ci'));
          for (const input of ['host_sdk_pin.env', 'source_pin.env', 'source_pin.env', 'llvm_pin.env', 'runtime_pin.env', 'host-toolchain-pin.mjs']) {
            await fs.copyFile(path.join(root, 'ci', input), path.join(work, 'ci', input));
          }
          if (arm === 'bad-pin') {
            const pin = path.join(work, 'ci/host_sdk_pin.env');
            await fs.writeFile(pin, (await fs.readFile(pin, 'utf8')).trimEnd() + '\nCJCJ_TOOLCHAIN_UNKNOWN=invalid\n');
          }
          if (arm === 'missing-reader') await fs.rename(path.join(work, 'ci/host-toolchain-pin.mjs'), path.join(work, 'ci/host-toolchain-pin.disabled'));
          const env = {...process.env, RUNNER_TEMP:work, GITHUB_ENV: path.join(work, 'github.env')};
          const result = spawnSync('bash', ['--noprofile', '--norc', '-euo', 'pipefail', '-c', `${script}\nprintf 'HOST_LOADER_COMPLETED\\n'`], {cwd: work, env, encoding: 'utf8'});
          assert.ifError(result.error);
          console.log(`TARGET_GITHUB_HOST_LOADER ${JSON.stringify({file, job, name, arm, rc: result.status, stdout: result.stdout, stderr: result.stderr})}`);
          if (arm === 'normal') {
            assert.equal(result.status, 0, result.stderr);
            assert.match(result.stdout, /HOST_LOADER_COMPLETED/);
            const records = (await fs.readFile(env.GITHUB_ENV, 'utf8')).split('\n').filter(line => line && !line.startsWith('#'));
            const loaded = Object.fromEntries(records.map(line => line.split(/=(.*)/s).slice(0, 2)));
            const platform = `${process.platform === 'win32' ? 'windows' : process.platform}_${process.arch === 'x64' ? 'x86_64' : 'aarch64'}`;
            assert.ok(independentHostVersions[platform]);
            console.log(`ASSERT_GITHUB_EXECUTION_HOST ${file}:${job}:${name} actual=${loaded.CJCJ_TOOLCHAIN}`);
            assert.equal(loaded.CJCJ_TOOLCHAIN, 'nightly-' + independentHostVersions[platform]);
          } else {
            assert.equal(result.status, 1, result.stderr);
            assert.doesNotMatch(result.stdout, /HOST_LOADER_COMPLETED/);
            assert.match(result.stderr, arm === 'bad-pin' ? /unsupported host platform pin/ : /Cannot find module/);
          }
        } finally {
          await fs.rm(work, {recursive: true, force: true});
        }
      });
    }
  }
});

// Explicit native H selection has a registered original archive; default pins
// and an arbitrary matching version string cannot select it.
test('explicit native host archive selection retains the default pin and rejects unregistered hosts',()=>{
 const old='nightly-'+'1.3.0-alpha.20260925001050';
 assert.throws(()=>baseSdkDownload('linux-x64',old),/no pinned archive identity/);
 assert.equal(baseSdkDownload('linux-x64',old,{selectedHost:true}).sha256,
  'fde68a5713968f5f875e013355d73aab8bd95bb1fbfd1f1b6a29b1adcf48943b');
 assert.equal(baseSdkDownload('linux-x64',readHostToolchainPin('linux-x64')).sha256,
  '772cfec6e7e371b78ad487c7938dad296e2fb6fe9e2462fe4a5ff68b3d02984f');
 assert.throws(()=>baseSdkDownload('linux-x64','nightly-'+'1.3.0-alpha.20260101000000',{selectedHost:true}),/no pinned archive identity/);
});
