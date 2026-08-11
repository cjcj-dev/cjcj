import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../../../build/lib/config.mjs';
import {baseEnv} from '../../../build/srcbuild/stages/common.mjs';
import {assembleCjcLinkOption} from '../../platform_matrix/link_option.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const readWorkflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');

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
// filter one -- so the tuple table moved into the plan step as JSON. It is still
// one table in one place; it just is not YAML, and reading only the YAML form
// leaves this file blind to every tuple.
const planTable = text => [...text.matchAll(/^\s*all='(\[[\s\S]*?\])'\s*$/gm)]
  .flatMap(([, json]) => JSON.parse(json));

// The values a ${{ matrix.KEY }} placeholder can take inside one workflow file.
const matrixValues = (text, key) => [
  ...[...text.matchAll(new RegExp(String.raw`^\s*(?:- )?${key}: (\S+)$`, 'gm'))].map(([, value]) => value),
  ...planTable(text).map(entry => entry[key]).filter(value => value !== undefined).map(String),
];

function expandMatrix(name, text) {
  const placeholder = name.match(/\$\{\{\s*matrix\.(\w+)\s*\}\}/);
  if (!placeholder) return [name];
  const values = matrixValues(text, placeholder[1]);
  assert.ok(values.length > 0, `no matrix values for ${placeholder[1]} in ${name}`);
  return values.flatMap(value => expandMatrix(name.replace(placeholder[0], value), text));
}

// Artifact names one workflow file uploads, with its own matrix fanout expanded.
function uploadedArtifacts(text) {
  const lines = text.split('\n');
  const names = [];
  for (const [index, line] of lines.entries()) {
    if (!line.includes('uses: actions/upload-artifact@')) continue;
    const nameLine = lines.slice(index + 1, index + 10).find(entry => /^\s+name: /.test(entry));
    assert.ok(nameLine, `upload step at line ${index + 1} declares no artifact name`);
    names.push(...expandMatrix(nameLine.replace(/^\s+name: /, '').trim(), text));
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
  const os = condition.match(/^runner\.os (==|!=) '(\w+)'$/);
  if (os) return (os[1] === '==') === (context.runnerOs === os[2]);
  // `*` not `+`: `inputs.x != ''` is how this repo spells "was anything passed",
  // and a `+` cannot match the empty literal at all.
  const input = condition.match(/^inputs\.(\w+) (==|!=) '([\w-]*)'$/);
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
    .map(step => substitute(scalar(step, 'name'), inputs));
}

function substitute(value, inputs) {
  return value.replace(/\$\{\{\s*inputs\.(\w+)\s*\}\}/g, (_, name) => {
    assert.ok(inputs.has(name), `no value for inputs.${name}`);
    return inputs.get(name);
  });
}

test('source-build workflow connects every native runner to its LLVM and std artifact', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const fixed = await fs.readFile(path.join(root, '.github/workflows/build-fixed-llc.yml'), 'utf8');
  const cells = [
    ['linux-aarch64', 'ubuntu-24.04-arm', 'linux_aarch64'],
    ['darwin-arm64', 'macos-15', 'darwin_aarch64'],
    ['darwin-x64', 'macos-15-intel', 'darwin_x86_64'],
    ['linux-x64', 'ubuntu-22.04', 'linux_x86_64'],
  ];
  for (const [target, runner, llvmPlatform] of cells) {
    // Whole-tuple equality: a row that pairs the right target with the wrong
    // runner has to fail, which is why this compares the entry and not three
    // independent substring hits.
    const row = planTable(workflow).find(entry => entry.target === target);
    assert.ok(row, `srcbuild plan has no row for ${target}`);
    assert.equal(row.runner, runner, `${target} runner`);
    assert.equal(row.llvm_platform, llvmPlatform, `${target} llvm_platform`);
    const tuple = planTable(fixed).find(entry => entry.platform === llvmPlatform);
    assert.ok(tuple, `fixed-llc plan has no tuple for ${llvmPlatform}`);
    assert.equal(tuple.runner, runner, `${llvmPlatform} runner`);
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
    'Build compiler oracle', 'Build runtime from source', 'Build stdlib from source',
    'Build stage 1 compiler', 'Build stage 2 compiler', 'Build stage 3 compiler and final std',
    'Upload final source-built std install root', 'Compose self-hosted SDK', 'Verify self-hosted SDK',
  ].map(name => workflow.indexOf(`name: ${name}`));
  assert.ok(order.every(index => index >= 0));
  assert.deepEqual([...order].sort((a, b) => a - b), order);

  for (const payload of ['llc.gz', 'opt.gz', 'llvm-tools.manifest', 'cjselfhost_llvmshim.o']) {
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
  const callerInputs = new Map([...mapping(block(packageJob, /^\s*with:\s*$/))].map(([key, value]) => [
    key,
    value.replace(/\$\{\{\s*inputs\.(\w+)\s*\}\}/g, (_, name) => {
      const declared = block(armSoak, new RegExp(String.raw`^ {6}${name}:\s*$`));
      assert.ok(declared, `arm-soak declares no dispatch input ${name}`);
      const fallback = scalar(declared, 'default');
      assert.ok(fallback !== undefined, `dispatch input ${name} has no default`);
      return fallback;
    }),
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
  assert.deepEqual(producersOf(demanded), ['srcbuild.yml']);

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

test('source-build cache makes durable GHA writes primary and retains write diagnostics', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  assert.ok(workflow.includes('SCCACHE_MULTILEVEL_CHAIN: "gha"'));
  assert.ok(!workflow.includes('SCCACHE_MULTILEVEL_CHAIN: "disk,gha"'));
  assert.ok(workflow.includes('SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY: "l0"'));
  assert.ok(workflow.includes('SCCACHE_ERROR_LOG=$RUNNER_TEMP/sccache-error.log'));
  assert.ok(workflow.includes('name: Capture sccache diagnostics'));
  assert.ok(workflow.includes('name: sccache-diagnostics-${{ matrix.target }}-${{ github.run_attempt }}'));
  assert.ok(workflow.includes('retention-days: 1'));
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

test('source build keeps a version-matched plain host runtime across both bootstrap halves', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const provision = workflow.indexOf('- name: Provision uncoloured host SDK');
  const compiler = workflow.indexOf('- name: Build compiler oracle');
  assert.ok(provision >= 0 && compiler > provision);
  for (const contract of [
    'export CJCJ_SDK_STOCK_LLC=1',
    'export CJCJ_TOOLCHAIN="nightly-$RUNTIME_VERSION"',
    'CJCJ_SRCBUILD_HOST_SDK=$host_sdk',
  ]) assert.ok(workflow.includes(contract), contract);

  const stdlib = await fs.readFile(path.join(root, 'build/srcbuild/stages/stdlib.mjs'), 'utf8');
  const nativeBuild = stdlib.indexOf("'build', '-t', config.buildType");
  assert.ok(stdlib.indexOf('assertRuntimeSplit({') < stdlib.indexOf("['clean']"));
  assert.ok(stdlib.includes('hostCompilerEnv(config, {hostRuntime: split.hostRuntime})'));
  assert.ok(stdlib.indexOf("['clean']") < nativeBuild);
  assert.ok(nativeBuild < stdlib.indexOf('assertRuntimeCommonCache({'));

  const activation = await fs.readFile(path.join(root, 'ci/srcbuild/steps/activate-source-sdk.mjs'), 'utf8');
  assert.ok(activation.includes('assertRuntimeSplit({'));
  assert.ok(activation.includes('const libraryPath = hostLoaderPath({'));
  assert.ok(!activation.includes('const libraryPath = [llvmLib, runtimeLib, toolsLib'));

  const stdx = await fs.readFile(path.join(root, 'build/srcbuild/stages/stdx.mjs'), 'utf8');
  assert.ok(stdx.includes('STDX_HOST_RUNTIME_LIB_DIR'));
  assert.ok(stdx.includes('hostCompilerEnv(config, {hostRuntime: split.hostRuntime})'));
  assert.ok(stdx.includes('assertRuntimeSplit({'));
  assert.ok(stdx.includes('assertHostRuntimeCommands({'));
});

test('Darwin selfhost link uses the source SDK dylib and libc++', () => {
  const link = assembleCjcLinkOption('darwin', '/source-sdk', 'linux-only');
  assert.match(link, /\/source-sdk\/third_party\/llvm\/lib\/libLLVM\.dylib/);
  assert.match(link, /-lc\+\+/);
  assert.doesNotMatch(link, /libLLVM-15\.so|-lstdc\+\+/);
});

test('Windows final std is cross-built by the stage2 Linux host compiler', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const producer = await fs.readFile(path.join(root, 'ci/srcbuild/steps/build-windows-final-std.mjs'), 'utf8');
  for (const edge of [
    "if: matrix.target == 'linux-x64'",
    'run: npx --yes zx@8 ci/srcbuild/steps/build-windows-final-std.mjs',
    'name: final-std-windows-x64',
    'path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-windows-stage2',
  ]) assert.ok(workflow.includes(edge), edge);
  for (const contract of [
    "getTarget('windows-x64')",
    "path.join(sdk, 'bin', 'cjcj-stage2')",
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
  // release.yml passes cross_std_artifact on two matrix rows and arm-soak.yml passes
  // it on none. build-release-package.yml gates a download on `!= ''`, so the two
  // cases have to come out opposite -- and the omitted one has to come out the same
  // way Actions comes out, which is '' (its declared default), not undefined.
  const consumer = await readWorkflow('build-release-package.yml');
  // failClosedDownloads yields the artifact names the job will demand.
  const gated = 'final-std-windows-x64';
  // Every input the surviving download steps interpolate into their names.
  const base = [
    ['runner', 'ubuntu-24.04-arm'],
    ['platform', 'linux-aarch64'],
    ['llvm_platform', 'linux_aarch64'],
    ['std_artifact', 'final-std-linux-aarch64'],
  ];

  const withCross = failClosedDownloads(consumer,
    new Map([...base, ['cross_std_artifact', 'final-std-windows-x64']]));
  assert.ok(withCross.includes(gated), `passing it should demand the artifact: ${withCross}`);

  const withoutCross = failClosedDownloads(consumer, new Map(base));
  assert.ok(!withoutCross.includes(gated),
    `omitting it must skip that download the way Actions does: ${withoutCross}`);

  // The specific wrong answer this guards: leaving the caller's map alone makes the
  // value undefined, `undefined !== ''` holds, and the step reads as running.
  const resolved = effectiveInputs(consumer, new Map(base));
  assert.equal(resolved.get('cross_std_artifact'), '');
  assert.equal(scalar(block(uncommented(consumer), /^ {6}cross_std_artifact:\s*$/), 'default'), "''");
});

test('an input the caller omits and the workflow does not default is a failure, not a guess', async () => {
  // The unrecognized-condition assert exists so the parser never picks a side it
  // cannot justify; the same has to hold for a value it cannot resolve.
  const declared = ['on:', '  workflow_call:', '    inputs:', '      needed:',
    '        required: true', '        type: boolean'].join('\n');
  assert.throws(() => effectiveInputs(declared, new Map()),
    /input needed is omitted by the caller and declares no default/);
});
