import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from '../../vendor/js-yaml/js-yaml.mjs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {buildConfig} from '../../../build/lib/config.mjs';
import {baseEnv} from '../../../build/srcbuild/stages/common.mjs';
import {assembleCjcLinkOption} from '../../platform_matrix/link_option.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';
import {llvmToolMatrix, sourceBuildCells} from '../../../build/lib/targets.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const readWorkflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');
const llvmWorkflow = name => loadYaml(fsSync.readFileSync(path.join(root, '.github/workflows', name), 'utf8'));

const producer = llvmWorkflow('build-llvm-tools.yml');
const wrapper = llvmWorkflow('platform-tuples.yml');

function llvmPlan(requested = 'all', platformSet = '', publishTuple = false) {
  const directory = fsSync.mkdtempSync(path.join(os.tmpdir(), 'llvm-matrix-'));
  const output = path.join(directory, 'output');
  try {
    const step = producer.jobs.plan.steps.find(entry => entry.id === 'select');
    const result = spawnSync('bash', ['-eu', '-o', 'pipefail', '-c', step.run], {
      cwd: root, encoding: 'utf8',
      env: {...process.env, REQUESTED: requested, PLATFORM_SET: platformSet,
        PUBLISH_TUPLE: String(publishTuple), GITHUB_OUTPUT: output},
    });
    assert.equal(result.status, 0, result.stderr);
    const record = fsSync.readFileSync(output, 'utf8').trim();
    assert.ok(record.startsWith('matrix='), record);
    const matrix = JSON.parse(record.slice('matrix='.length));
    console.log(`LLVM_MATRIX_RESULT ${JSON.stringify(matrix)}`);
    return matrix.include;
  } finally {
    fsSync.rmSync(directory, {recursive: true, force: true});
  }
}

test('producer emits the real runner and glibc baseline for all five tuples', () => {
  const rows = llvmPlan('all', 'all');
  assert.deepEqual(rows.map(row => [row.platform, row.runner, row.glibc]), [
    ['linux_x86_64', 'ubuntu-22.04', '2.35'],
    ['linux_aarch64', 'ubuntu-22.04-arm', '2.35'],
    ['darwin_aarch64', 'macos-15', null],
    ['darwin_x86_64', 'macos-15-intel', null],
    ['windows_x86_64', 'windows-2022', null],
  ]);
});

test('both caller subsets reach the same producer matrix and upload identity', () => {
  const call = wrapper.jobs['build-tuple'];
  assert.equal(call.uses, './.github/workflows/build-llvm-tools.yml');
  const allCaller = llvmWorkflow('platform-matrix.yml').jobs;
  const releaseCaller = llvmWorkflow('release.yml').jobs;
  const subset = jobs => Object.values(jobs).find(job => job.uses === './.github/workflows/platform-tuples.yml')
    .with?.platform_set || 'all';
  const binding = call.with.platform_set;
  const resolve = value => binding === "${{ inputs.platform_set || 'all' }}" ? value : binding;
  const allRows = llvmPlan('all', resolve(subset(allCaller)));
  const windowsRows = llvmPlan('all', resolve(subset(releaseCaller)));
  console.log(`CALLER_IDENTITY all=${allRows.length} windows=${windowsRows.length}`);
  assert.equal(allRows.length, 5, 'platform-matrix receives every tuple');
  assert.equal(windowsRows.length, 1, 'release receives only its Windows tuple');
  assert.deepEqual(windowsRows[0], allRows.find(row => row.platform === 'windows_x86_64'));
  const uploads = producer.jobs['build-tools'].steps.filter(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(uploads.length, 1);
  assert.equal(uploads[0].with.name, 'fixed-llvm-tools-${{ matrix.platform }}');
  assert.equal(uploads[0].with.path, 'fixed-toolchain/${{ matrix.platform }}');
  assert.equal(producer.jobs['build-tools'].strategy.matrix, '${{ fromJson(needs.plan.outputs.matrix) }}');
  assert.equal(producer.jobs['build-tools']['runs-on'], '${{ matrix.runner }}');
});

test('native callers retain four tuples and explicit selections deduplicate', () => {
  assert.equal(llvmPlan().length, 4);
  assert.deepEqual(llvmPlan(' linux_aarch64, linux_aarch64 ').map(row => row.platform), ['linux_aarch64']);
  assert.equal(llvmPlan('all', 'darwin-windows').length, 3);
});

test('static publication adds x64 once without dropping the requested tuple', () => {
  assert.deepEqual(llvmPlan('darwin_aarch64', '', true).map(row => row.platform), ['darwin_aarch64', 'linux_x86_64']);
  assert.equal(llvmPlan('linux_x86_64', '', true).length, 1);
});

test('invalid and empty selections fail before emitting a matrix', () => {
  for (const [requested, platformSet] of [['linux_typo', ''], [' , ', ''], ['all', 'typo']]) {
    const result = spawnSync(process.execPath, ['ci/llvm-tools-matrix.mjs'], {
      cwd: root, encoding: 'utf8',
      env: {...process.env, REQUESTED: requested, PLATFORM_SET: platformSet, GITHUB_OUTPUT: '', PUBLISH_TUPLE: 'false'},
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /unknown LLVM|no LLVM platforms/);
    assert.equal(result.stdout, '');
  }
});

test('the repository has one fixed LLVM artifact uploader and preserves native and Windows checks', () => {
  const uploaders = [];
  for (const name of fsSync.readdirSync(path.join(root, '.github/workflows')).filter(name => name.endsWith('.yml'))) {
    for (const job of Object.values(llvmWorkflow(name).jobs || {})) {
      for (const step of job.steps || []) {
        if (step.uses?.startsWith('actions/upload-artifact@') && step.with?.name?.startsWith('fixed-llvm-tools-')) {
          uploaders.push(name);
        }
      }
    }
  }
  assert.deepEqual(uploaders, ['build-llvm-tools.yml']);
  const steps = producer.jobs['build-tools'].steps;
  const cacheKey = steps.find(step => step.id === 'cache').with.key;
  for (const input of ['ci/llvm_pin.env', 'build/lib/targets.mjs', 'ci/llvm-tools-matrix.mjs', 'ci/platform_tuples/**']) {
    assert.ok(cacheKey.includes(input), `cache identity includes ${input}`);
  }
  assert.ok(steps.some(step => step.run?.includes('validate tuple')));
  assert.ok(steps.some(step => step.run?.includes('assert_no_libxml2_needed.sh')));
  assert.ok(steps.some(step => step.run?.includes('bash ci/platform_tuples/build_tuple.sh')));
  assert.ok(steps.some(step => step.run?.includes('llvm-static-libs.txt')));
});

const uncommented = text => text.split('\n').filter(line => !/^\s*#/.test(line)).join('\n');

// One entry per reusable-workflow *call*, not per distinct file: two jobs calling
// one producer upload its artifacts twice, so the repeat has to survive here.
async function invokedWorkflows(entry, stack = []) {
  assert.ok(!stack.includes(entry), `reusable workflow cycle: ${[...stack, entry].join(' -> ')}`);
  const text = uncommented(await readWorkflow(entry));
  const invocations = [entry];
  for (const [, called] of text.matchAll(/uses:\s*\.\/\.github\/workflows\/([\w.-]+\.yml)/g)) {
    invocations.push(...await invokedWorkflows(called, [...stack, entry]));
  }
  return invocations;
}

// A selectable matrix cannot be a literal any more -- Actions has no way to
// filter one -- so each table moved into its plan step as JSON. It is still one
// table in one place; it just is not YAML, and reading only the YAML form leaves
// this file blind to every row. Two selectors are live and both are covered:
// the fixed-LLVM producer (llvm-tools-matrix.mjs) and the source-build matrix
// (srcbuild/target-matrix.mjs).
const planTable = text => {
  if (text.includes('run: node ci/llvm-tools-matrix.mjs')) {
    return llvmToolMatrix('all', {platformSet: 'all'}).include;
  }
  if (text.includes('run: node ci/srcbuild/target-matrix.mjs')) return sourceBuildCells();
  return [...text.matchAll(/^\s*all='(\[[\s\S]*?\])'\s*$/gm)].flatMap(([, json]) => JSON.parse(json));
};

// The values a ${{ matrix.KEY }} placeholder can take inside one workflow file.
const matrixValues = (text, key) => [
  ...[...text.matchAll(new RegExp(String.raw`^\s*(?:- )?${key}: (\S+)$`, 'gm'))].map(([, value]) => value),
  ...planTable(text).map(entry => entry[key]).filter(value => value !== undefined).map(String),
];

function expandMatrix(name, text, workflow = text) {
  const placeholder = name.match(/\$\{\{\s*matrix\.(\w+)\s*\}\}/);
  if (!placeholder) return [name];
  const local = matrixValues(text, placeholder[1]);
  const values = local.length ? local : planTable(workflow)
    .map(entry => entry[placeholder[1]]).filter(value => value !== undefined).map(String);
  assert.ok(values.length > 0, `no matrix values for ${placeholder[1]} in ${name}`);
  return values.flatMap(value => expandMatrix(name.replace(placeholder[0], value), text, workflow));
}

// Artifact names one workflow file uploads, with its own matrix fanout expanded.
function uploadedArtifacts(text) {
  const names = [];
  // Matrix values belong to the producing job. A Linux-only cross job must
  // not multiply every native artifact by its own target declaration.
  for (const job of jobs(text).values()) {
    const lines = job.split('\n');
    for (const [index, line] of lines.entries()) {
      if (!line.includes('uses: actions/upload-artifact@')) continue;
      const nameLine = lines.slice(index + 1, index + 10).find(entry => /^\s+name: /.test(entry));
      assert.ok(nameLine, `upload step at line ${index + 1} declares no artifact name`);
      names.push(...expandMatrix(nameLine.replace(/^\s+name: /, '').trim(), job, text));
    }
  }
  return names;
}

// [artifact, producing workflow] for everything a dispatch entry point uploads.
async function runArtifacts(entry) {
  const produced = [];
  for (const name of await invokedWorkflows(entry)) {
    const text = uncommented(await readWorkflow(name));
    for (const artifact of uploadedArtifacts(text)) produced.push([artifact, name]);
  }
  return produced;
}

// --- consumer side -----------------------------------------------------------
// The produced set above is a property of the producer files alone, so on its own
// it cannot notice a caller that asks for a name nobody builds. Everything below
// derives what the caller actually demands, straight out of the caller's YAML.

// The lines nested under the first line matching `header`.
function block(text, header) {
  const lines = text.split('\n');
  const start = lines.findIndex(line => header.test(line));
  if (start < 0) return undefined;
  const indent = lines[start].match(/^ */)[0].length;
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() && line.match(/^ */)[0].length <= indent) break;
    body.push(line);
  }
  return body.join('\n');
}

// Anchored and whole-token on purpose: a substring test passes on `<value>-BROKEN`.
const scalar = (text, key) => text?.match(new RegExp(String.raw`^\s*${key}: (.+?)\s*$`, 'm'))?.[1];

const mapping = text => new Map(
  (text ?? '').split('\n')
    .map(line => line.match(/^\s*([A-Za-z0-9_-]+): (.+?)\s*$/))
    .filter(Boolean)
    .map(([, key, value]) => [key, value]),
);

function jobs(text) {
  const body = block(uncommented(text), /^jobs:\s*$/);
  assert.ok(body !== undefined, 'workflow declares no jobs');
  const parsed = new Map();
  let current;
  for (const line of body.split('\n')) {
    const header = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (header) parsed.set(current = header[1], []);
    else if (current) parsed.get(current).push(line);
  }
  return new Map([...parsed].map(([name, lines]) => [name, lines.join('\n')]));
}

const needsOf = job => {
  const raw = scalar(job, 'needs');
  if (raw === undefined) return [];
  return raw.startsWith('[') ? raw.slice(1, -1).split(',').map(entry => entry.trim()) : [raw];
};

// One `- ` item of a steps: list, with its trailing keys.
function steps(text) {
  const collected = [];
  let current;
  for (const line of uncommented(text).split('\n')) {
    if (/^ {6}- /.test(line)) {
      if (current) collected.push(current.join('\n'));
      current = [line];
    } else if (current) {
      if (line.trim() && /^ {0,6}\S/.test(line)) {
        collected.push(current.join('\n'));
        current = undefined;
      } else current.push(line);
    }
  }
  if (current) collected.push(current.join('\n'));
  return collected;
}

const runnerOs = runner => {
  if (runner.startsWith('ubuntu')) return 'Linux';
  if (runner.startsWith('macos')) return 'macOS';
  if (runner.startsWith('windows')) return 'Windows';
  return assert.fail(`unknown runner image: ${runner}`);
};

// Only the `if:` forms this repo actually uses. An unrecognized one fails the test
// instead of defaulting either way -- guessing here is how a gate goes quietly green.
function stepRuns(step, context) {
  const condition = scalar(step, 'if');
  if (condition === undefined) return true;
  if (condition.includes(' || ')) {
    const results = condition.split(' || ').map(part => stepRuns(`        if: ${part}`, context));
    return results.some(Boolean);
  }
  const os = condition.match(/^runner\.os (==|!=) '(\w+)'$/);
  if (os) return (os[1] === '==') === (context.runnerOs === os[2]);
  // `*` not `+`: `inputs.x != ''` is how this repo spells "was anything passed",
  // and a `+` cannot match the empty literal at all.
  const input = condition.match(/^inputs\.(\w+) (==|!=) '([\w\[\]-]*)'$/);
  if (input) {
    // Reading straight from the caller's map would compare against undefined for
    // any input the caller omitted, and `undefined !== ''` flips every one of
    // these conditions the wrong way -- the test would then believe a step runs
    // that Actions skips. Resolve through the declared defaults first.
    assert.ok(context.inputs.has(input[1]), `no resolved value for inputs.${input[1]}`);
    return (input[2] === '==') === (context.inputs.get(input[1]) === input[3]);
  }
  return assert.fail(`unrecognized step condition, cannot decide statically: ${condition}`);
}

const unquote = value => value?.replace(/^'(.*)'$/, '$1').replace(/^"(.*)"$/, '$1');

// name -> declaration block, for the inputs a called workflow accepts.
function declaredInputs(text) {
  const body = block(uncommented(text), /^\s*workflow_call:\s*$/);
  const inputsBlock = body === undefined ? undefined : block(body, /^\s*inputs:\s*$/);
  const declared = new Map();
  if (inputsBlock === undefined) return declared;
  let current;
  for (const line of inputsBlock.split('\n')) {
    const header = line.match(/^ {6}([A-Za-z0-9_-]+):\s*$/);
    if (header) declared.set(current = header[1], []);
    else if (current) declared.get(current).push(line);
  }
  return new Map([...declared].map(([name, lines]) => [name, lines.join('\n')]));
}

// What `inputs.<name>` actually evaluates to inside the called workflow: the
// caller's value if it passed one, otherwise the declared default, and for a
// string input declared without one, ''. Actions resolves it this way, so a test
// that reads only the caller's `with:` block disagrees with the thing it checks.
function effectiveInputs(text, inputs) {
  const resolved = new Map(inputs);
  for (const [name, declaration] of declaredInputs(text)) {
    if (resolved.has(name)) continue;
    const fallback = scalar(declaration, 'default');
    if (fallback !== undefined) {
      resolved.set(name, unquote(fallback));
      continue;
    }
    // No caller value and no default: only a string input has an implicit one.
    // Anything else would be a real gap, so say so rather than pick a value.
    assert.equal(scalar(declaration, 'type'), 'string',
      `input ${name} is omitted by the caller and declares no default`);
    resolved.set(name, '');
  }
  return resolved;
}

// Artifacts a called workflow will download and fail on if they are absent.
function failClosedDownloads(text, inputs) {
  const context = {inputs: effectiveInputs(text, inputs), runnerOs: runnerOs(inputs.get('runner'))};
  return steps(text)
    .filter(step => step.includes('uses: actions/download-artifact@'))
    .filter(step => scalar(step, 'continue-on-error') !== 'true')
    .filter(step => stepRuns(step, context))
    .flatMap(step => {
      if (scalar(step, 'pattern') === 'final-std-*') {
        return [...JSON.parse(context.inputs.get('cross_std_artifacts')).map(entry => entry.artifact),
          ...[context.inputs.get('cross_std_artifact')].filter(Boolean)];
      }
      return [substitute(scalar(step, 'name'), inputs)];
    });
}

function substitute(value, inputs) {
  return value.replace(/\$\{\{\s*inputs\.(\w+)\s*\}\}/g, (_, name) => {
    assert.ok(inputs.has(name), `no value for inputs.${name}`);
    return inputs.get(name);
  });
}

test('source-build workflow connects every native runner to its LLVM and std artifact', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const fixed = await fs.readFile(path.join(root, '.github/workflows/build-llvm-tools.yml'), 'utf8');
  assert.ok(workflow.includes('uses: ./.github/workflows/build-llvm-tools.yml'), 'source build must call the reusable tuple producer');
  for (const {target, runner, llvm_platform: llvmPlatform} of sourceBuildCells()) {
    // Whole-tuple equality: a row that pairs the right target with the wrong
    // runner has to fail, which is why this compares the entry and not three
    // independent substring hits.
    const row = planTable(workflow).find(entry => entry.target === target);
    assert.ok(row, `srcbuild plan has no row for ${target}`);
    assert.equal(row.runner, runner, `${target} runner`);
    assert.equal(row.llvm_platform, llvmPlatform, `${target} llvm_platform`);
    const tuple = planTable(fixed).find(entry => entry.platform === llvmPlatform);
    assert.ok(tuple, `LLVM producer plan has no tuple for ${llvmPlatform}`);
    assert.equal(tuple.runner, target === 'linux-aarch64' ? 'ubuntu-22.04-arm' : runner, `${llvmPlatform} runner`);
  }
  // The dependency, not one spelling of it: the list form appeared when the
  // matrix became selectable and a literal match would have read that as the
  // edge being gone.
  assert.match(workflow, /^\s*needs:\s*(fixed-llvm\s*$|\[[^\]]*\bfixed-llvm\b)/m,
    'the source SDK job no longer depends on fixed-llvm');
  for (const edge of [
    'name: fixed-llvm-tools-${{ matrix.llvm_platform }}',
    'name: final-std-${{ matrix.target }}',
    'path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-stage2',
  ]) assert.ok(workflow.includes(edge), edge);

  const order = [
    'Bootstrap stage0 compiler', 'Bootstrap stage1 compiler', 'Build stage 3 compiler and final std',
    'Upload final source-built std install root', 'Build stdx from source',
    'Compose self-hosted SDK', 'Verify self-hosted SDK',
  ].map(name => workflow.indexOf(`name: ${name}`));
  assert.ok(order.every(index => index >= 0));
  assert.deepEqual([...order].sort((a, b) => a - b), order);

  for (const payload of ['llc.gz', 'opt.gz', 'ld.lld', 'ld64.lld', 'llvm-tools.manifest', 'cjselfhost_llvmshim.o']) {
    assert.ok(fixed.includes(payload), payload);
  }
});

test('arm soak produces every artifact its package job downloads, each exactly once', async () => {
  const armSoak = await readWorkflow('arm-soak.yml');
  const soakJobs = jobs(armSoak);

  // A needs: pointing at a job that no longer exists is rejected by Actions before
  // anything runs, and renaming a producer job is the easy way to introduce one.
  for (const [name, job] of soakJobs) {
    for (const need of needsOf(job)) assert.ok(soakJobs.has(need), `job ${name} needs missing job ${need}`);
  }

  // What the package job asks for, resolved through arm-soak's own dispatch defaults.
  const packageJob = soakJobs.get('package');
  assert.ok(packageJob, 'arm-soak has no package job');
  const command = scalar(soakJobs.get('matrix-plan'), 'run');
  const output = execFileSync('bash', ['-e', '-c', command], {
    cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_OUTPUT: ''},
  });
  const plan = Object.fromEntries(output.trim().split('\n').map(line => line.split('=')));
  const callerInputs = new Map([...mapping(block(packageJob, /^\s*with:\s*$/))].map(([key, value]) => [
    key,
    value.replace(/\$\{\{\s*inputs\.(\w+)\s*\|\|\s*needs.matrix-plan.outputs.(\w+)\s*\}\}/g, (_, name, outputName) => {
      const declared = block(armSoak, new RegExp(String.raw`^ {6}${name}:\s*$`));
      assert.ok(declared, `arm-soak declares no dispatch input ${name}`);
      const fallback = scalar(declared, 'default');
      assert.ok(fallback !== undefined, `dispatch input ${name} has no default`);
      return unquote(fallback) || plan[outputName];
    }).replace(/\$\{\{\s*needs.matrix-plan.outputs.(\w+)\s*\}\}/g, (_, name) => plan[name]),
  ]));

  const platform = callerInputs.get('platform');
  const demanded = callerInputs.get('std_artifact');

  // build-release-package.yml:66-73 fails the run on any other value, so the caller
  // has to demand exactly this name. Whole-value equality: `-BROKEN` must not pass.
  const consumer = await readWorkflow('build-release-package.yml');
  assert.ok(consumer.includes('EXPECTED_STD_ARTIFACT: final-std-${{ inputs.platform }}'));
  assert.equal(demanded, `final-std-${platform}`);

  // Every download the package job will reach on this platform and die on if absent.
  const required = failClosedDownloads(consumer, callerInputs);
  assert.ok(required.includes(demanded), `std artifact ${demanded} is not among ${required}`);

  const produced = await runArtifacts('arm-soak.yml');
  const producersOf = artifact => produced.filter(([name]) => name === artifact).map(([, source]) => source);

  // The point of the whole test: demanded and produced have to be the same set.
  for (const artifact of required) assert.equal(producersOf(artifact).length, 1, `producers of ${artifact}`);
  assert.deepEqual(producersOf(demanded), ['srcbuild-target.yml']);

  // upload-artifact rejects a name already uploaded in the same run, so two callers
  // of one producer workflow break the run rather than merging.
  const names = produced.map(([artifact]) => artifact);
  assert.deepEqual(names.filter((artifact, index) => names.indexOf(artifact) !== index), []);

  // The package job must wait for whichever job actually builds those artifacts.
  const producerJobs = [];
  for (const [name, job] of soakJobs) {
    const called = scalar(job, 'uses')?.match(/^\.\/\.github\/workflows\/([\w.-]+\.yml)$/);
    if (!called) continue;
    const uploads = (await runArtifacts(called[1])).map(([artifact]) => artifact);
    if (uploads.includes(demanded)) producerJobs.push(name);
  }
  assert.equal(producerJobs.length, 1, `jobs producing ${demanded}: ${producerJobs}`);
  assert.ok(needsOf(packageJob).includes(producerJobs[0]),
    `package needs ${needsOf(packageJob)} but ${demanded} is built by ${producerJobs[0]}`);
});

test('source-build leaves the sccache GHA backend off and persists the disk cache as one entry per target', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const action = await fs.readFile(path.join(root, '.github/actions/sccache/action.yml'), 'utf8');
  // The per-object backend was measured, not assumed: run 31551077927 got 230 hits
  // against 6585 misses while spending 4162 s on writes, and the repository cache
  // held 27840 entries in 6.9 GB of a 10 GB cap -- one entry per object file, so
  // every run evicted the last one's. The cache that replaced it is sccache's
  // disk cache saved as a single actions/cache entry keyed by component, target
  // and pin (.github/actions/sccache); this asserts the off state is still spelled
  // out there rather than merely dropping the old assertion.
  assert.ok(action.includes('SCCACHE_GHA_ENABLED=false'));
  assert.ok(!workflow.includes('SCCACHE_GHA_ENABLED: "true"'));
  assert.ok(!workflow.includes('SCCACHE_MULTILEVEL_CHAIN'),
    'multi-level chain only means something with a durable backend enabled');
  assert.ok(workflow.includes('uses: ./.github/actions/sccache\n'), 'srcbuild starts sccache through the shared action');
  assert.ok(workflow.includes('uses: ./.github/actions/sccache-report'), 'and reports through it');
  // The diagnostics stay: they are how the next measurement gets taken.
  const report = await fs.readFile(path.join(root, '.github/actions/sccache-report/action.yml'), 'utf8');
  assert.ok(action.includes('SCCACHE_ERROR_LOG=$RUNNER_TEMP/sccache-$COMPONENT-error.log'));
  assert.ok(report.includes('--stats-format=json'));
  assert.ok(report.includes('name: sccache-${{ inputs.component }}-${{ inputs.platform }}-${{ github.run_attempt }}'));
});

test('Windows MinGW product cache has one bounded rate-limit retry', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/build-windows-runtime.yml'), 'utf8');
  const start = workflow.indexOf('- name: Restore official MinGW toolchain');
  const end = workflow.indexOf('- name: Cross-build pinned Windows runtime');
  assert.ok(start >= 0 && end > start);
  const cacheBlock = workflow.slice(start, end);
  assert.equal(cacheBlock.match(/uses: actions\/cache\/save@v6/g)?.length, 2);
  assert.equal(cacheBlock.match(/lookup-only: true/g)?.length, 2);
  assert.equal(cacheBlock.match(/run: sleep 5/g)?.length, 1);
  assert.ok(cacheBlock.includes("steps.mingw-cache-probe.outputs.cache-hit != 'true'"));
  assert.ok(cacheBlock.includes('still absent after one bounded retry'));
});

test('native build environments use configured architecture, OpenSSL, and loader', () => {
  const oldDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  try {
    for (const targetKey of ['linux-aarch64', 'darwin-arm64', 'darwin-x64', 'linux-x64']) {
      const config = buildConfig({targetKey});
      const env = baseEnv(config);
      assert.equal(env.ARCH, config.target.spec.arch);
      assert.equal(env.OPENSSL_PATH, config.target.spec.opensslLibDir);
      assert.ok(env.PATH.startsWith(config.target.spec.llvmBinDir));
      assert.ok(env[config.target.spec.loaderEnv].includes(config.target.spec.opensslLibDir));
      assert.equal('LDFLAGS' in env, config.target.spec.os === 'linux');
    }
  } finally {
    if (oldDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = oldDryRun;
  }
});

test('source build keeps the pinned plain host runtime across both bootstrap halves', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const provision = workflow.indexOf('- name: Provision uncoloured host SDK');
  const bootstrap0 = workflow.indexOf('- name: Bootstrap stage0 compiler');
  const bootstrap1 = workflow.indexOf('- name: Bootstrap stage1 compiler');
  const stdxStep = workflow.indexOf('- name: Build stdx from source');
  assert.ok(provision >= 0 && bootstrap0 > provision);
  assert.ok(bootstrap1 > bootstrap0 && stdxStep > bootstrap1);
  assert.ok(!workflow.includes('- name: Build compiler oracle'));
  assert.ok(!workflow.includes('build compiler'));
  for (const contract of [
    'export CJCJ_SDK_STOCK_LLC=1',
    'cat ci/host_sdk_pin.env >> "$GITHUB_ENV"',
    'CJCJ_SRCBUILD_BOOTSTRAP_SDK=$host_sdk',
    'CJCJ_SRCBUILD_HOST_SDK=$host_sdk',
  ]) assert.ok(workflow.includes(contract), contract);

  const prepare = await fs.readFile(path.join(root, 'ci/srcbuild/steps/prepare-source-host-sdk.mjs'), 'utf8');
  for (const contract of [
    'await fs.realpath(bootstrapSdk)',
    "path.join(workspace, 'source-host-sdk')",
    'await fs.rm(hostSdk, {recursive: true, force: true})',
    'await fs.cp(sourceSdk, hostSdk, {recursive: true, preserveTimestamps: true})',
    'await fs.copyFile(compiler, hostCompiler)',
    'assertPlainHostRuntime({hostSdk, target})',
    'CJCJ_SRCBUILD_HOST_SDK=${hostSdk}',
  ]) assert.ok(prepare.includes(contract), contract);

  const stdlib = await fs.readFile(path.join(root, 'build/srcbuild/stages/stdlib.mjs'), 'utf8');
  const nativeBuild = stdlib.indexOf("'build', '-t', config.buildType");
  assert.ok(stdlib.indexOf('assertRuntimeSplit({') < stdlib.indexOf("['clean']"));
  assert.ok(stdlib.indexOf("['clean']") < nativeBuild);
  assert.ok(nativeBuild < stdlib.indexOf('assertRuntimeCommonCache({'));

  const activation = await fs.readFile(path.join(root, 'ci/srcbuild/steps/activate-source-sdk.mjs'), 'utf8');
  assert.ok(activation.includes('assertRuntimeSplit({'));
  assert.ok(activation.includes('const libraryPath = targetLoaderPath({'));
  assert.ok(!activation.includes('const libraryPath = hostLoaderPath({'));
  assert.ok(activation.includes("const hostCompiler = path.join(sdk, 'bin', 'cjc')"));
  assert.ok(activation.includes('CJCJ_SRCBUILD_HOST_CJC=${hostCompiler}'));
  assert.ok(!activation.includes('const libraryPath = [llvmLib, runtimeLib, toolsLib'));

  const common = await fs.readFile(path.join(root, 'build/srcbuild/stages/common.mjs'), 'utf8');
  assert.ok(common.includes("extraPathDirs.unshift(path.join(hostSdk, 'bin'))"));
  const stage1 = await fs.readFile(path.join(root, 'ci/srcbuild/steps/build-stage1.mjs'), 'utf8');
  assert.ok(stage1.includes('hostLoaderPath({'));
  assert.ok(stage1.includes("path.join(oracleCompilerDir, 'cjc')"));
  assert.ok(stage1.includes('PATH: `${oracleCompilerDir}${path.delimiter}'));
  assert.ok(stage1.includes('await $({env: oracleEnv})`cjpm build`'));

  const stdx = await fs.readFile(path.join(root, 'build/srcbuild/stages/stdx.mjs'), 'utf8');
  assert.ok(stdx.includes('STDX_HOST_CANGJIE_HOME'));
  assert.ok(!stdx.includes('applyTextPatch'));
  assert.ok(stdx.includes('assertRuntimeSplit({'));
  assert.ok(stdx.includes('assertHostRuntimeCommands({'));
});

test('Darwin selfhost link uses the source SDK dylib and libc++', () => {
  const link = assembleCjcLinkOption('darwin', '/source-sdk', 'linux-only');
  assert.match(link, /\/source-sdk\/third_party\/llvm\/lib\/libLLVM\.dylib/);
  assert.match(link, /-lc\+\+/);
  assert.doesNotMatch(link, /libLLVM-15\.so|-lstdc\+\+/);
});

// #736 moved these jobs into srcbuild-target.yml and reordered them: the
// source-mingw job now restores the stage3 handoff before cross-building, so
// the stage2 step name it shipped with is stale and the stage3 one is truthful.
test('Windows final std is cross-built by the shipped stage3 Linux host compiler', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild-target.yml'), 'utf8');
  const producer = await fs.readFile(path.join(root, 'ci/srcbuild/steps/build-windows-final-std.mjs'), 'utf8');
  for (const edge of [
    "if: matrix.target == 'linux-x64'",
    'run: npx --yes zx@8 ci/srcbuild/steps/build-windows-final-std.mjs',
    'name: final-std-windows-x64',
    'path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-windows-stage2',
  ]) assert.ok(workflow.includes(edge), edge);
  for (const contract of [
    "getTarget('windows-x64')",
    "path.join(sdk, 'bin', 'cjcj-stage1')",
    "lineage.stdCompilerSha256 !== lineage.compilerSha256",
    '--target windows-x86_64',
    '--target-sysroot ${mingwRoot}/',
    '--target-toolchain ${mingwBin}',
  ]) assert.ok(producer.includes(contract), contract);
});

test('final std install roots satisfy package_sdk layout (a) on every release target', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'srcbuild-final-std-'));
  try {
    for (const targetKey of ['linux-aarch64', 'darwin-arm64', 'darwin-x64', 'linux-x64', 'windows-x64']) {
      const target = buildConfig({targetKey}).target;
      const install = path.join(fixture, targetKey);
      const modulesTop = path.join(install, 'modules', target.spec.runtimeTuple);
      const modulesStd = path.join(modulesTop, 'std');
      const staticDir = path.join(install, 'lib', target.spec.runtimeTuple);
      const sharedDir = path.join(install, 'runtime', 'lib', target.spec.runtimeTuple);
      await Promise.all([modulesStd, staticDir, sharedDir].map(directory => fs.mkdir(directory, {recursive: true})));
      await Promise.all([
        fs.writeFile(path.join(modulesStd, 'std.core.cjo'), ''),
        fs.writeFile(path.join(staticDir, 'libcangjie-std-core.a'), ''),
        fs.writeFile(path.join(staticDir, 'libcangjie-std-coreFFI.a'), ''),
        fs.writeFile(path.join(sharedDir, `libcangjie-std-core${target.spec.sharedLibrarySuffix}`), ''),
        fs.writeFile(path.join(install, 'PROVENANCE.txt'), 'fixture\n'),
      ]);
      if (target.spec.expectedStdArtifacts.bitcode !== 0) {
        await fs.writeFile(path.join(modulesStd, 'libstd.core.bc'), '');
      }
      await assertFinalStd(install, target, {dryRun: true});
    }

    const consumer = await fs.readFile(path.join(root, 'scripts/package_sdk.mjs'), 'utf8');
    assert.ok(consumer.includes("modulesStd: path.join(root, 'modules', runtimeDir, 'std')"));
    assert.ok(consumer.includes("libDir: path.join(root, 'lib', runtimeDir)"));
  } finally {
    await fs.rm(fixture, {recursive: true, force: true});
  }
});

test('an omitted optional input reads the way Actions reads it, not as undefined', async () => {
  // Cross artifacts are a JSON list. An omitted input resolves to its declared
  // empty list, so it must skip the download exactly as Actions does.
  const consumer = await readWorkflow('build-release-package.yml');
  // failClosedDownloads yields the artifact names the job will demand.
  const gated = 'final-std-windows-x64';
  // Every input the surviving download steps interpolate into their names.
  const base = [
    ['runner', 'ubuntu-24.04-arm'],
    ['platform', 'linux-aarch64'],
    ['llvm_platform', 'linux_aarch64'],
    ['std_artifact', 'final-std-linux-aarch64'],
    ['compiler_artifact', 'final-compiler-linux-aarch64'],
  ];

  const withCross = failClosedDownloads(consumer,
    new Map([...base, ['cross_std_artifacts', JSON.stringify([{tuple: 'windows_x86_64_cjnative', artifact: 'final-std-windows-x64'}])]]));
  assert.ok(withCross.includes(gated), `passing it should demand the artifact: ${withCross}`);

  const legacy = failClosedDownloads(consumer, new Map([...base,
    ['cross_std_artifact', gated], ['cross_std_tuple', 'windows_x86_64_cjnative']]));
  assert.ok(legacy.includes(gated), 'legacy single tuple must still download its artifact');

  const withoutCross = failClosedDownloads(consumer, new Map(base));
  assert.ok(!withoutCross.includes(gated),
    `omitting it must skip that download the way Actions does: ${withoutCross}`);

  // The specific wrong answer this guards: leaving the caller's map alone makes the
  // value undefined, `undefined !== '[]'` holds, and the step reads as running.
  const resolved = effectiveInputs(consumer, new Map(base));
  assert.equal(resolved.get('cross_std_artifacts'), '[]');
  assert.equal(scalar(block(uncommented(consumer), /^ {6}cross_std_artifacts:\s*$/), 'default'), "'[]'");
});

test('an input the caller omits and the workflow does not default is a failure, not a guess', async () => {
  // The unrecognized-condition assert exists so the parser never picks a side it
  // cannot justify; the same has to hold for a value it cannot resolve.
  const declared = ['on:', '  workflow_call:', '    inputs:', '      needed:',
    '        required: true', '        type: boolean'].join('\n');
  assert.throws(() => effectiveInputs(declared, new Map()),
    /input needed is omitted by the caller and declares no default/);
});
