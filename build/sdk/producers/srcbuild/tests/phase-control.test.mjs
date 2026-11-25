import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from '../../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {allReleasePlatforms, finalStdArtifact, getReleasePlatform, getTarget, releasePlatformReadiness, sourceBuildCells, CROSS_STD_BUILDS} from '../../../../lib/targets.mjs';

const root = path.resolve(import.meta.dirname, '..', '..', '..', '..', '..');
const readWorkflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');

// The five native hosts. release.yml used to run them as five serial phases
// (ci/docs/dryrun-execution-policy.md 3); it now runs four stages, each fully
// parallel: plan -> source (one sdk-build.yml call, every host and cross std) ->
// package (one sdk-package.yml matrix) -> publish. The stop-loss that survives
// is stage-shaped: nothing starts before plan admits the run, no package starts
// before every source cell succeeded, and publish needs every package cell.
const PHASES = ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64'];
const SOURCE_WORKFLOW = './.github/workflows/sdk-build.yml';
const PACKAGE_WORKFLOW = './.github/workflows/sdk-package.yml';
const NATIVE_KEYS = ['linux-x64', 'linux-arm64', 'win32-x64', 'darwin-arm64', 'darwin-x64'];
const needsList = job => [job?.needs ?? []].flat();

const uncommented = text => text.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n');

function jobs(text) {
  const body = uncommented(text).split('\njobs:\n')[1];
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

const scalar = (text, key) => text?.match(new RegExp(String.raw`^\s*${key}:\s*(.+?)\s*$`, 'm'))?.[1];

function needsOf(job) {
  const raw = scalar(job, 'needs');
  if (raw === undefined) return [];
  return raw.startsWith('[') ? raw.slice(1, -1).split(',').map(entry => entry.trim()).filter(Boolean) : [raw];
}

// Every `if:` on a job, including the folded `>-` form release.yml uses for publish.
function jobCondition(job) {
  const inline = job.match(/^\s*if:\s*(?!>)(.+?)\s*$/m);
  if (inline) return inline[1];
  const folded = job.match(/^\s*if:\s*>[-+]?\s*\n([\s\S]*?)(?=\n\s*[a-z_-]+:\s|\n?$)/m);
  return folded ? folded[1].replace(/\s+/g, ' ').trim() : undefined;
}

// A job is skipped when a job it needs fails or is skipped -- unless its own
// condition opts out of that. These are the only forms that opt out.
const OVERRIDES = /\b(always|cancelled|failure)\s*\(/;

// GitHub job status functions for a run that is not cancelled: success() and
// failure() read the direct needs; cancelled() is false.
function evalSourceCondition(condition, inputs, needs) {
  const results = Object.values(needs).map(item => item.result);
  return Function('inputs', 'needs', 'always', 'cancelled', 'success', 'failure', 'contains', 'return (' +
    condition.replace(/needs\.([\w-]+)/g, 'needs["$1"]') + ')')(
    inputs, needs, () => true, () => false, () => results.every(result => result === 'success'),
    () => results.includes('failure'), (value, part) => value.includes(part));
}
// Any status function replaces the implicit success() requirement.
const STATUS_FUNCTION = /\b(always|cancelled|failure|success)\s*\(/;

function sourceOutcomes(workflow, cell, inputs) {
  const seen = new Map([['plan', {result:'success',outputs:{llvm_platforms:cell.llvm_platform}}]]);
  function visit(id, stack = []) {
    assert.ok(workflow.jobs[id], 'unknown source dependency ' + id);
    assert.ok(!stack.includes(id), 'source dependency cycle: ' + [...stack,id].join(' -> '));
    if (seen.has(id)) return seen.get(id);
    const job = workflow.jobs[id];
    const needs = Object.fromEntries([job.needs ?? []].flat().map(parent => [parent, visit(parent,[...stack,id])]));
    const success = Object.values(needs).every(item => item.result === 'success');
    const allowed = (success || STATUS_FUNCTION.test(job.if || '')) &&
      (!job.if || evalSourceCondition(job.if, inputs, needs));
    const row = {result: allowed ? 'success' : 'skipped'};
    seen.set(id,row);
    return row;
  }
  for (const id of Object.keys(workflow.jobs)) visit(id);
  return seen;
}

async function artifactUploads(name) {
  const workflow = loadYaml(await readWorkflow(name));
  const found = [];
  for (const [id, job] of Object.entries(workflow.jobs)) {
    for (const step of job.steps || []) {
      if (!step.uses?.startsWith('actions/upload-artifact@')) continue;
      const artifact = step.with?.name;
      if (!artifact) continue;
      if (artifact.includes('matrix.artifact')) {
        const family = job.strategy.matrix.match(/outputs\.(ohos|ios)_matrix/)?.[1];
        assert.ok(family, `${name}/${id}: dynamic cross artifacts require the source matrix`);
        for (const row of CROSS_STD_BUILDS.filter(row => row.family === family)) {
          found.push([artifact.replace(/\$\{\{ matrix\.artifact \}\}/g, row.artifact), `${name}/${id}`]);
        }
      } else if (name === 'sdk-build-target.yml' && job.strategy?.matrix === '${{ fromJson(needs.plan.outputs.matrix) }}') {
        // The target workflow is invoked for a single cell. Expand addressable
        // names only for jobs that can actually coexist in the release run.
        const inputs = {build_ios:true,build_ohos:true,build_android:true,native_runtime_artifact:'fixture',native_build_inputs_artifact:'fixture'};
        for (const cell of sourceBuildCells({nativeInputs:true})) {
          if (sourceOutcomes(workflow,cell,inputs).get(id).result !== 'success') continue;
          const targetGuard = step.if?.match(/^(?:always\(\) && )?matrix\.target == '([\w-]+)'(?: && [^|]+)?$/);
          if (targetGuard && cell.target !== targetGuard[1]) continue;
          const resolved = artifact.replace(/\$\{\{ matrix\.(\w+) \}\}/g, (_,field) => {
            assert.ok(cell[field], `${id} missing ${field} for ${cell.target}`);
            return cell[field];
          });
          found.push([resolved, `${name}/${id}/${cell.target}`]);
        }
      } else found.push([artifact, `${name}/${id}`]);
    }
  }
  return found;
}

test('Windows and optional iOS source paths reach only their own packaging jobs', async () => {
  const workflow = loadYaml(await readWorkflow('sdk-build-target.yml'));
  const cells = sourceBuildCells({nativeInputs:true});
  const results = ['success','skipped','failure','cancelled'];
  for (const cell of cells) for (const build_ios of [false,true]) {
    const inputs = {build_ios,native_runtime_artifact:'fixture',native_build_inputs_artifact:'fixture'};
    const windows = cell.target === 'windows-x64', ios = cell.target === 'darwin-arm64' && build_ios;
    const outcome = sourceOutcomes(workflow,cell,inputs);
    for (const [job,expected] of [['native-windows-sdk',windows],['source-stage3',!windows],
      ['srcbuild',!windows],['source-ios',ios],['source-windows',cell.target === 'linux-x64']])
      assert.equal(outcome.get(job).result,expected ? 'success' : 'skipped',cell.target+' '+job);
    for (const [winResult,iosResult] of results.flatMap(w => results.map(i => [w,i]))) {
      const needs = {plan:{result:'success',outputs:{llvm_platforms:cell.llvm_platform}},
        'source-stage3':{result:windows?'skipped':'success'},'source-windows':{result:winResult},'source-ios':{result:iosResult},
        // Android is not requested here (inputs.build_android unset): its skip admits srcbuild.
        'source-android':{result:'skipped'}};
      assert.equal(evalSourceCondition(workflow.jobs.srcbuild.if,inputs,needs),
        !windows && (winResult==='success' || winResult==='skipped' && cell.target!=='linux-x64') && (iosResult==='success' || iosResult==='skipped'&&!ios));
    }
  }
});

test('policy contract 1: the five native packages are rows of one parallel package stage', async () => {
  const release = loadYaml(await readWorkflow('release.yml'));
  const calls = Object.entries(release.jobs).filter(([, job]) => job.uses === PACKAGE_WORKFLOW);
  assert.deepEqual(calls.map(([id]) => id), ['package'], 'one sdk-package.yml call carries every package');
  const [[, pkg]] = calls;
  const rows = pkg.strategy?.matrix?.include;
  assert.ok(Array.isArray(rows) && rows.length > 0, 'the package stage is a static include matrix');
  assert.equal(new Set(rows.map(row => row.release_key)).size, rows.length, 'release_key is unique per package row');
  // release_key selects the package variant; platform alone also matches the
  // Android packages running on these hosts (package-key.mjs consumes both).
  const native = rows.filter(row => NATIVE_KEYS.includes(row.release_key));
  assert.deepEqual(native.map(row => row.platform).sort(), [...PHASES].sort(),
    `expected one native package row per host, found ${native.map(row => row.release_key)}`);
  // Parallel, but not careless: one dying cell must not cancel the evidence of
  // the others, and nothing throttles the stage back into a hidden order.
  assert.equal(pkg.strategy['fail-fast'], false, 'a failing package cell cancels its siblings');
  assert.equal(pkg.strategy['max-parallel'], undefined, 'max-parallel reintroduces a serial package order');
  assert.deepEqual(needsList(pkg), ['source'], 'packages start only after the whole source stage succeeded');
  for (const [id, job] of Object.entries(release.jobs)) {
    if (id === 'publish') continue;
    assert.ok(!needsList(job).includes('package'), `${id} hangs off the package stage, serializing it`);
  }
});

test('policy contract 2: one source call builds every host and cross std at once, after plan', async () => {
  const release = loadYaml(await readWorkflow('release.yml'));
  const sources = Object.entries(release.jobs).filter(([, job]) => job.uses === SOURCE_WORKFLOW);
  assert.deepEqual(sources.map(([id]) => id), ['source'], 'release.yml makes exactly one sdk-build.yml call');
  const [[, source]] = sources;
  assert.equal(source.with?.targets, 'all', 'the source call must build every target');
  for (const family of ['android', 'wasm', 'ohos', 'ios'])
    assert.equal(source.with?.[`build_${family}`], true, `the source call must build the ${family} cross std`);
  assert.deepEqual(needsList(source), ['plan'], 'source starts only after plan admitted the run');
  assert.deepEqual(sourceBuildCells({nativeInputs:true}).map(cell => cell.target).sort(), [...PHASES].sort(),
    'the source fan-out covers exactly the five native hosts');
  const sdkBuild = loadYaml(await readWorkflow('sdk-build.yml'));
  const nested = Object.entries(sdkBuild.jobs).filter(([, job]) => job.uses);
  assert.deepEqual(nested.map(([id, job]) => [id, job.uses]), [['srcbuild', './.github/workflows/sdk-build-target.yml']],
    'sdk-build.yml fans out through exactly one nested call');
  const [[, fan]] = nested;
  assert.equal(fan.strategy?.matrix, '${{ fromJson(needs.plan.outputs.matrix) }}', 'the fan-out is the planned target matrix');
  assert.equal(fan.strategy?.['fail-fast'], false, 'a failing source cell cancels its siblings');
  assert.equal(fan.strategy?.['max-parallel'], undefined, 'max-parallel reintroduces a serial source order');
  assert.equal(fan.with?.targets, '${{ matrix.target }}', 'each cell builds only its own target');
  assert.deepEqual(needsList(fan), ['plan']);
});

test('policy contract 3: nothing, Windows included, starts before plan, and Windows consumes its native std', async () => {
  const release = loadYaml(await readWorkflow('release.yml'));
  const reaches = (from, to, seen = new Set()) => needsList(release.jobs[from]).some(need =>
    need === to || (!seen.has(need) && (seen.add(need), reaches(need, to, seen))));
  for (const id of Object.keys(release.jobs)) {
    if (id === 'plan') continue;
    assert.ok(reaches(id, 'plan'), `${id} starts with no gate: it can run before plan checked the release inputs`);
  }
  const windows = release.jobs.package.strategy.matrix.include.filter(row => row.platform === 'windows-x64');
  assert.ok(windows.length > 0, 'no Windows package rows found');
  for (const row of windows) {
    assert.equal(row.std_artifact, finalStdArtifact('windows-x64', 'windows-x64'),
      `${row.release_key}: Windows packages consume the native Windows final std, not the Linux cross std`);
    assert.equal(row.runner.startsWith('windows-'), true, `${row.release_key}: Windows packages run on Windows`);
  }
});

test('policy contract 4: a STOP leaves later phases skipped, with no condition that overrides it', async () => {
  // Actions skips a job whose needs did not succeed. That is the stop-loss, and
  // always()/cancelled()/failure() are the three ways to lose it -- release.yml
  // uses always() on the package matrix today, which is exactly the hole.
  const release = jobs(await readWorkflow('release.yml'));
  const offenders = [];
  for (const [name, job] of release) {
    if (name === 'publish') continue; // publish is allowed to report on a stopped run
    const condition = jobCondition(job);
    if (condition && OVERRIDES.test(condition)) offenders.push(`${name}: if: ${condition.slice(0, 60)}`);
  }
  assert.deepEqual(offenders, [],
    `these jobs run even when what they need did not succeed:\n  ${offenders.join('\n  ')}`);
});

test('policy contract 5: each artifact name has exactly one producer in the run', async () => {
  const produced = [];
  for (const workflow of ['release.yml', 'sdk-build.yml', 'sdk-build-target.yml', 'sdk-package.yml']) {
    produced.push(...await artifactUploads(workflow));
  }
  const counts = new Map();
  for (const [artifact, source] of produced) {
    counts.set(artifact, [...(counts.get(artifact) || []), source]);
  }
  const duplicated = [...counts].filter(([, sources]) => sources.length > 1);
  assert.deepEqual(duplicated, [],
    `upload-artifact rejects a name already uploaded in the same run: ${JSON.stringify(duplicated)}`);

  // Counting upload steps in files misses the way phase control reintroduces the
  // collision: one workflow called several times in the same run uploads its
  // names once per call. Each repeated call has to differ in what it is asked to
  // produce, or two of them race for the same artifact name.
  const release = jobs(await readWorkflow('release.yml'));
  const callers = new Map();
  for (const [name, job] of release) {
    const used = job.match(/uses:\s*(\.\/\.github\/workflows\/\S+)/);
    if (used) callers.set(name, used[1]);
  }
  const byWorkflow = new Map();
  for (const [name, workflow] of callers) {
    byWorkflow.set(workflow, [...(byWorkflow.get(workflow) || []), name]);
  }
  for (const [workflow, jobNames] of byWorkflow) {
    if (jobNames.length < 2) continue;
    const selectors = jobNames.map(name => {
      const withBlock = release.get(name).split(/\n\s*with:\s*\n/)[1] || '';
      return withBlock.split('\n').filter(line => /^\s{6}\S/.test(line)).sort().join('|');
    });
    assert.equal(new Set(selectors).size, jobNames.length,
      `${workflow} is called ${jobNames.length} times (${jobNames}) with inputs that do not distinguish them`);
  }

  // The parallel form of the same collision: one call fanned out as a matrix
  // uploads its names once per row. Every sdk-package.yml upload is keyed by
  // the package identity, and package-key.mjs gives each row a distinct one.
  const packageWorkflow = loadYaml(await readWorkflow('sdk-package.yml'));
  const uploads = packageWorkflow.jobs.package.steps.filter(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.ok(uploads.length > 0, 'sdk-package.yml uploads nothing');
  for (const step of uploads)
    assert.match(step.with.name, /\$\{\{ (env\.PACKAGE_KEY|inputs\.release_key \|\| inputs\.platform) \}\}/,
      `${step.name}: an upload name that ignores the package identity collides across matrix rows`);
  const rows = loadYaml(await readWorkflow('release.yml')).jobs.package.strategy.matrix.include;
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'package-key-rows-'));
  const keys = [];
  try {
    for (const [index, row] of rows.entries()) {
      const envFile = path.join(dir, `${index}.env`);
      const run = spawnSync(process.execPath, [path.join(root, 'build/sdk/producers/release/package-key.mjs')], {
        // release.yml hands every cell the prepare.yml native inputs, which is what
        // gives the Windows rows their source producer.
        encoding: 'utf8', env: {...process.env, CJCJ_NATIVE_RUNTIME_ARTIFACT: 'fixture',
          RELEASE_PLATFORM: row.platform, RELEASE_KEY: row.release_key, GITHUB_ENV: envFile}});
      assert.equal(run.status, 0, `${row.release_key}: ${run.stderr}`);
      keys.push((await fs.readFile(envFile, 'utf8')).trim());
    }
  } finally {
    await fs.rm(dir, {recursive: true, force: true});
  }
  assert.equal(new Set(keys).size, rows.length, `package rows share a PACKAGE_KEY: ${keys}`);
});

// The other half of EXECUTION_BLOCKED_BY_PHASE_CONTROL_AND_FAILURE_CAPTURE: a
// phase that dies has to leave something to read, or the stop-loss buys a stop
// with no diagnosis.
test('policy failure capture: a package cell that dies leaves evidence behind', async () => {
  const text = uncommented(await readWorkflow('sdk-package.yml'));
  assert.match(text, /if:\s*failure\(\)\s*\n\s*uses:\s*actions\/upload-artifact@/,
    'no failure-only upload: the pkg-* upload runs only after everything before it succeeded');
  const upload = text.split(/\n\s*- name: /).find(step => step.startsWith('Upload failure diagnostics\n'));
  assert.ok(upload, 'failure diagnostics upload step is missing');
  assert.match(upload, /if:\s*failure\(\)\s*\n\s*uses:\s*actions\/upload-artifact@/);
  assert.equal(scalar(upload, 'name'), 'pkg-diagnosis-${{ env.PACKAGE_KEY }}-${{ github.run_attempt }}',
    'failure diagnostics must be named per package and run attempt');
  for (const evidence of ['dist/**/*.json', 'dist/**/*.jsonl', 'dist/**/*.log', '.platform-ci/installed-sdk-check/**']) {
    assert.ok(upload.includes(evidence), `failure diagnostics must retain ${evidence}`);
  }
});

test('policy failure capture: smoke workspaces survive the failure that needs them', async () => {
  const text = (await Promise.all(['sdk-build.yml', 'sdk-package.yml'].map(readWorkflow))).map(uncommented).join('\n');
  // `trap '... rm -rf ...' EXIT` fires on the failure path too, so the evidence
  // is gone before any upload step can see it.
  const unconditional = [...text.matchAll(/trap\s+'([^']*)'\s+EXIT/g)]
    .map(match => match[1])
    .filter(handler => /\brm\s+-rf/.test(handler));
  assert.deepEqual(unconditional, [],
    `these EXIT traps delete the smoke workspace whatever happened: ${JSON.stringify(unconditional)}`);
});

// Execute the same CLI that the workflow uses, and read its GITHUB_ENV output;
// stdout alone would miss a broken producer-to-Actions environment handoff.
for (const hasProducer of [true, false]) test(`policy failure capture: package identity ${hasProducer ? 'reaches GITHUB_ENV for declared SDK producers' : 'rejects cells without a complete SDK producer'}`, async t => {
  const workflow = uncommented(await readWorkflow('sdk-package.yml'));
  assert.match(workflow, /RELEASE_PLATFORM:\s*\$\{\{ inputs\.platform \}\}/);
  assert.match(workflow, /RELEASE_KEY:\s*\$\{\{ inputs\.release_key \}\}/);
  assert.ok(workflow.indexOf('run: node build/sdk/producers/release/package-key.mjs') > 0);
  assert.ok(workflow.indexOf('run: node build/sdk/producers/release/package-key.mjs') < workflow.indexOf('Upload failure diagnostics'));
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'package-key-contract-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const declared = [
    ...PHASES.map(host => ({host, key: '', archiveKey: host})),
    ...allReleasePlatforms().map(getReleasePlatform),
  ];
  // A package/tuple declaration is not a whole SDK source producer. Keep every
  // cell in the contract, including Windows and excluded cells, and derive the
  // expected branch from the same public source declarations as the workflow.
  const cells = declared.filter(cell => Boolean(releasePlatformReadiness(
    cell.key || getTarget(cell.host).spec.packageHost.join('-')).sdkSourceTarget) === hasProducer);
  if (!cells.length) return t.skip('no declared cells in this producer branch');
  for (const [index, cell] of cells.entries()) {
    const envFile = path.join(dir, `${index}.env`);
    const run = spawnSync(process.execPath, [path.join(root, 'build/sdk/producers/release/package-key.mjs')], {
      encoding: 'utf8', env: {...process.env, RELEASE_PLATFORM: cell.host,
        RELEASE_KEY: cell.key, GITHUB_ENV: envFile},
    });
    assert.equal(run.signal, null);
    assert.ifError(run.error);
    if (!hasProducer) {
      assert.equal(run.status, 1, `SDK_PRODUCER_REJECTION ${cell.key || cell.host}: ${run.stderr}`);
      assert.ok(run.stderr.includes(`NATIVE_SDK_PRODUCER_MISSING ${cell.host}:`), run.stderr);
      await assert.rejects(fs.readFile(envFile), {code: 'ENOENT'},
        'a rejected SDK producer must not publish package identity');
      console.log(`ASSERT_SDK_PRODUCER_REJECTION ${cell.key || cell.host}: rc=${run.status}`);
      continue;
    }
    assert.equal(run.status, 0, run.stderr);
    const output = await fs.readFile(envFile, 'utf8');
    assert.equal(output, `PACKAGE_KEY=${cell.archiveKey}\n`,
      `package identity must reach GITHUB_ENV for ${cell.key || cell.host}`);
    console.log(`ASSERT_PACKAGE_KEY ${cell.key || cell.host}: ${output.trim()}`);
  }
});

function diagnosticNames(template, cells) {
  const names = cells.flatMap(cell => [1, 2].map(attempt => {
    const values = {'env.PACKAGE_KEY': cell.archiveKey, 'inputs.platform': cell.host,
      'github.run_attempt': String(attempt)};
    return template.replace(/\$\{\{\s*([\w.]+)\s*\}\}/g, (_, key) => {
      assert.ok(Object.hasOwn(values, key), `unknown artifact expression ${key}`);
      return values[key];
    });
  }));
  assert.equal(new Set(names).size, names.length,
    'failure diagnostics collide across package cells or run attempts');
  return names;
}

test('policy failure capture: diagnostic names distinguish same-host packages and attempts', async () => {
  const text = uncommented(await readWorkflow('sdk-package.yml'));
  const upload = text.split(/\n\s*- name: /).find(step => step.startsWith('Upload failure diagnostics\n'));
  const names = diagnosticNames(scalar(upload, 'name'), allReleasePlatforms().map(getReleasePlatform));
  assert.ok(names.includes('pkg-diagnosis-linux-x64-android-1'));
  assert.ok(names.includes('pkg-diagnosis-linux-x64-1'));
});

test('policy failure capture: collision controls reject host-only, omitted-key and omitted-attempt names', () => {
  for (const template of ['pkg-diagnosis-${{ inputs.platform }}-${{ github.run_attempt }}',
    'pkg-diagnosis-${{ github.run_attempt }}', 'pkg-diagnosis-${{ env.PACKAGE_KEY }}']) {
    assert.throws(() => diagnosticNames(template, allReleasePlatforms().map(getReleasePlatform)),
      /failure diagnostics collide across package cells or run attempts/);
  }
});
