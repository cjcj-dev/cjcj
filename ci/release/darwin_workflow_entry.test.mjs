import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {load as loadYaml} from '../vendor/js-yaml/js-yaml.mjs';

// The fixture is the Git blob of the reviewed workflow at this exact product
// commit, not a copy of its product implementation or a simulated CI result.
const sourceSha = '255d8c7e1f5e70be69b4cf3e9091514cfb1a4d09';
const reviewedText = fs.readFileSync(new URL('./fixtures/darwin-input-consumers-255d.yml', import.meta.url), 'utf8');
const reviewed = loadYaml(reviewedText);
const workflowFile = new URL('../../.github/workflows/darwin-input-consumers.yml', import.meta.url);
const workflow = loadYaml(fs.readFileSync(workflowFile, 'utf8'));
const originalJob = reviewed.jobs['native-input'];
const job = workflow.jobs?.['native-input'];
const originalSteps = originalJob.steps;
const steps = job?.steps || [];
const byName = (list, name) => list.find(step => step.name === name);
const originalNamed = name => byName(originalSteps, name);
const actualNamed = name => byName(steps, name);
const byUses = (list, uses) => list.find(step => step.uses === uses);

function observed(label, value) {
  // A passing target assertion must also show the parsed values it consumed.
  console.log(`ASSERT ${label} observed=${JSON.stringify(value)}`);
}

test('reviewed workflow fixture retains its fixed Git content', () => {
  const hash = createHash('sha256').update(reviewedText).digest('hex');
  assert.equal(hash, '216b08dac6055c6b95be79673fabe504bfd4356d9da26af9b4cf91f0f92d3d39', 'DARWIN_REVIEWED_FIXTURE');
  observed('DARWIN_REVIEWED_FIXTURE', {sourceSha, hash});
});

test('first checkout executes the immutable dispatch commit', () => {
  const expected = {...originalSteps[0], with: {ref: '${{ github.sha }}'}};
  observed('DARWIN_FIXED_CHECKOUT', steps[0]);
  assert.deepEqual(steps[0], expected, 'DARWIN_FIXED_CHECKOUT');
});

test('registered entry keeps the reviewed name and input-free dispatch event', () => {
  observed('DARWIN_DISPATCH', {name: workflow.name, on: workflow.on});
  assert.equal(workflow.name, reviewed.name, 'DARWIN_WORKFLOW_NAME');
  assert.deepEqual(workflow.on, reviewed.on, 'DARWIN_INPUT_FREE_DISPATCH');
  assert.deepEqual(Object.keys(workflow).sort(), Object.keys(reviewed).sort(), 'DARWIN_TOP_LEVEL_SCOPE');
  assert.deepEqual(Object.keys(workflow.jobs), Object.keys(reviewed.jobs), 'DARWIN_JOB_SCOPE');
});

test('entry retains contents and actions read-only permissions', () => {
  observed('DARWIN_READ_ONLY_PERMISSIONS', workflow.permissions);
  assert.deepEqual(workflow.permissions, reviewed.permissions, 'DARWIN_READ_ONLY_PERMISSIONS');
});

test('all four native cells retain targets runtime split timeout and environment', () => {
  const {steps: ignoredOriginal, ...expected} = originalJob;
  const {steps: ignoredActual, ...actual} = job || {};
  observed('DARWIN_FOUR_CELL_CONTRACT', actual);
  assert.deepEqual(actual, expected, 'DARWIN_FOUR_CELL_CONTRACT');
});

test('runtime checkout retains its pinned repository and separate source directory', () => {
  const checkouts = steps.filter(step => step.uses === 'actions/checkout@v7');
  const expected = originalSteps.filter(step => step.uses === 'actions/checkout@v7');
  observed('DARWIN_RUNTIME_SOURCE_DOMAIN', checkouts[1]);
  assert.equal(checkouts.length, 2, 'DARWIN_CHECKOUT_DOMAINS');
  assert.deepEqual(checkouts[1], expected[1], 'DARWIN_RUNTIME_SOURCE_DOMAIN');
});

test('Node boundary pin loading and actual input consumption retain reviewed commands', () => {
  const expectedNode = {...byUses(originalSteps, 'actions/setup-node@v4'), uses: 'actions/setup-node@v7.1.0'};
  expectedNode.with = {...expectedNode.with, 'node-version': '24.22.1'};
  assert.deepEqual(byUses(steps, expectedNode.uses), expectedNode, 'DARWIN_NODE24');
  for (const name of [
    'Check host and target guard before tools and input preparation',
    'Load pinned runtime source',
    'Build or acquire native inputs and consume their actual loaded libraries',
  ]) {
    observed('DARWIN_REVIEWED_CONSUMPTION', actualNamed(name));
    const expected = {...originalNamed(name)};
    if (name === 'Build or acquire native inputs and consume their actual loaded libraries') {
      // This exact run is the sole authorized command change from the fixture.
      expected.run = 'ulimit -c 0\n'
        + 'CANGJIE_BUILD_JOBS=$(sysctl -n hw.logicalcpu)\n'
        + 'export CANGJIE_BUILD_JOBS\n'
        + 'npx --yes zx@8 ci/release/darwin_consumer_ci.mjs "$RUNNER_TEMP/darwin-inputs"\n';
    }
    assert.deepEqual(actualNamed(name), expected, 'DARWIN_REVIEWED_CONSUMPTION');
  }
});

test('actual Mach-O loading retains its cut and restored consumer control', () => {
  const name = 'Qualify the actual Mach-O loading target with cut and restored consumer';
  observed('DARWIN_LOADER_CONTROL', actualNamed(name));
  assert.deepEqual(actualNamed(name), originalNamed(name), 'DARWIN_LOADER_CONTROL');
});

test('native producer bytes retain Darwin identity and Mach-O rejection controls', () => {
  const name = 'Qualify Darwin identity and Mach-O rejection on native producer bytes';
  observed('DARWIN_LLVM_CONTROL', actualNamed(name));
  assert.deepEqual(actualNamed(name), originalNamed(name), 'DARWIN_LLVM_CONTROL');
});

test('local sccache start and always report retain their original workspace domain', () => {
  for (const uses of ['./.github/actions/sccache', './.github/actions/sccache-report']) {
    observed('DARWIN_SCCACHE_DOMAIN', byUses(steps, uses));
    assert.deepEqual(byUses(steps, uses), byUses(originalSteps, uses), 'DARWIN_SCCACHE_DOMAIN');
  }
});

test('always upload preserves actual work runtime configuration and platform evidence', () => {
  const uses = 'actions/upload-artifact@v7';
  observed('DARWIN_ALWAYS_EVIDENCE', byUses(steps, uses));
  assert.deepEqual(byUses(steps, uses), byUses(originalSteps, uses), 'DARWIN_ALWAYS_EVIDENCE');
});

test('entry adds no steps or side effects and preserves reviewed execution order', () => {
  // Missing steps are judged by their own assertions above, so a removed
  // control fails precisely there, without a generic length check masking it.
  const identities = list => {
    let checkout = 0;
    return list.map(step => step.name || (step.uses === 'actions/checkout@v7'
      ? `${step.uses}:${checkout++}` : step.uses));
  };
  const expected = identities(originalSteps);
  const actual = identities(steps);
  const positions = actual.map(identity => expected.indexOf(identity));
  observed('DARWIN_STEP_SCOPE_AND_ORDER', {actual, positions});
  assert.ok(positions.every((position, index) => position >= 0
    && (index === 0 || position > positions[index - 1])), 'DARWIN_STEP_SCOPE_AND_ORDER');
});

function runConsumerStep(sysctlRc) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'darwin-entry-shell-'));
  try {
    const command = path.join(root, 'controlled-command.mjs');
    fs.writeFileSync(command, `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
if (path.basename(process.argv[1]) === 'sysctl') {
  fs.writeFileSync(process.env.SYSCTL_OBSERVATION, JSON.stringify(process.argv.slice(2)));
  console.log(process.env.SYSCTL_JOBS);
  process.exit(Number(process.env.SYSCTL_RC));
}
fs.writeFileSync(process.env.NPX_OBSERVATION, JSON.stringify({
  jobs: process.env.CANGJIE_BUILD_JOBS, argv: process.argv.slice(2)
}));
`, {mode: 0o755});
    for (const name of ['sysctl', 'npx']) fs.symlinkSync(command, path.join(root, name));
    const script = path.join(root, 'workflow-run');
    // Execute the deployed YAML's actual run with GitHub's unspecified-shell
    // bash -e {0} semantics. Commands control inputs/observe continuation only.
    fs.writeFileSync(script, actualNamed('Build or acquire native inputs and consume their actual loaded libraries').run);
    const sysctlObservation = path.join(root, 'sysctl.json');
    const npxObservation = path.join(root, 'npx.json');
    const env = {...process.env, PATH: `${root}:${process.env.PATH}`,
      RUNNER_TEMP: root, SYSCTL_RC: String(sysctlRc), SYSCTL_JOBS: '17',
      SYSCTL_OBSERVATION: sysctlObservation, NPX_OBSERVATION: npxObservation};
    delete env.CANGJIE_BUILD_JOBS;
    const result = spawnSync('bash', ['-e', script], {env, encoding: 'utf8', timeout: 10000});
    if (result.error) throw result.error;
    return {rc: result.status, signal: result.signal,
      sysctl: fs.existsSync(sysctlObservation) ? JSON.parse(fs.readFileSync(sysctlObservation, 'utf8')) : null,
      npx: fs.existsSync(npxObservation) ? JSON.parse(fs.readFileSync(npxObservation, 'utf8')) : null,
      expectedArgv: ['--yes', 'zx@8', 'ci/release/darwin_consumer_ci.mjs', `${root}/darwin-inputs`]};
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
}

test('actual consumer shell exports successful sysctl jobs to the original npx argv', () => {
  const result = runConsumerStep(0);
  observed('DARWIN_JOBS_ENVIRONMENT', result);
  assert.deepEqual(result.sysctl, ['-n', 'hw.logicalcpu'], 'DARWIN_SYSCTL_INPUT');
  assert.equal(result.signal, null, 'DARWIN_SHELL_SIGNAL');
  assert.equal(result.rc, 0, 'DARWIN_SUCCESS_STATUS');
  assert.deepEqual(result.npx, {jobs: '17', argv: result.expectedArgv}, 'DARWIN_JOBS_ENVIRONMENT');
});

test('actual consumer shell propagates sysctl failure before starting npx', () => {
  const result = runConsumerStep(23);
  observed('DARWIN_SYSCTL_FAILURE_PROPAGATION', result);
  assert.deepEqual(result.sysctl, ['-n', 'hw.logicalcpu'], 'DARWIN_SYSCTL_INPUT');
  assert.equal(result.signal, null, 'DARWIN_SHELL_SIGNAL');
  // One combined target judges both the producer status and continuation.
  assert.deepEqual({rc: result.rc, npx: result.npx}, {rc: 23, npx: null}, 'DARWIN_SYSCTL_FAILURE_PROPAGATION');
});
