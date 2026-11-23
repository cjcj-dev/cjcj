// Production wiring of the 15 formal release assets onto their real producers in build/sdk/producers.
// The table names, per cross tuple, the source job that builds its final std, the artifact it hands to
// the package job and the producer steps that job runs; checkProductionWiring proves the table against
// the actual workflows: release.yml calls sdk-build.yml once per host (build mode, fanning out to
// sdk-build-target.yml) and once per asset (package mode).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {load} from '../../ci/vendor/js-yaml/js-yaml.mjs';
import {ASSETS, HOSTS} from './targets.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const WORKFLOWS = Object.freeze({release: '.github/workflows/release.yml',
  source: '.github/workflows/sdk-build-target.yml', package: '.github/workflows/sdk-build.yml'});
export const PRODUCERS_DIR = 'build/sdk/producers';
// The whole workflow and composite-action surface; anything else under .github is a stray probe.
export const WORKFLOW_FILES = Object.freeze(['ci.yml', 'release.yml', 'sdk-build-target.yml', 'sdk-build.yml']);
export const ACTION_DIRS = Object.freeze(['native-windows-tools', 'sccache', 'setup-release-sdk']);

// release.yml calls the source workflow once per host carrier.
export const HOST_SOURCE_JOBS = Object.freeze({'linux-x64': 'source-p1-linux-x64', 'linux-aarch64': 'source-p2-linux-aarch64',
  'windows-x64': 'source-p3-windows-x64', 'darwin-arm64': 'source-p4-darwin-arm64', 'darwin-x64': 'source-p5-darwin-x64'});

const P = (host, job, artifact, steps) => Object.freeze({host, job, artifact, steps: Object.freeze(steps)});
const OHOS = ['srcbuild/steps/build-ohos-final-std.mjs'], IOS = ['srcbuild/steps/build-ios-final-std.mjs'];
export const CROSS_PRODUCERS = Object.freeze({
  windows_x86_64_cjnative: P('linux-x64', 'source-windows', 'final-std-windows-x64', ['srcbuild/steps/build-windows-final-std.mjs']),
  linux_x86_64_cjnative: P('linux-x64', 'source-stage3', 'final-std-linux-x64', ['srcbuild/steps/build-stage3.mjs']),
  linux_android_aarch64_cjnative: P('linux-x64', 'source-android', 'final-std-android-aarch64',
    ['srcbuild/steps/build-android-ast.mjs', 'srcbuild/steps/build-android-final-std.mjs']),
  wasi_wasm32_cjnative: P('linux-x64', 'source-wasm', 'final-std-wasm32-wasi', ['srcbuild/steps/build-wasm-final-std.mjs']),
  linux_ohos_aarch64_cjnative: P('linux-x64', 'source-ohos', 'final-std-ohos-aarch64', OHOS),
  linux_ohos_x86_64_cjnative: P('linux-x64', 'source-ohos', 'final-std-ohos-x86-64', OHOS),
  ios_aarch64_cjnative: P('darwin-arm64', 'source-ios', 'final-std-ios-aarch64-cjnative', IOS),
  ios_simulator_aarch64_cjnative: P('darwin-arm64', 'source-ios', 'final-std-ios-simulator-aarch64-cjnative', IOS),
  ios_simulator_x86_64_cjnative: P('darwin-arm64', 'source-ios', 'final-std-ios-simulator-x86-64-cjnative', IOS),
});

function fail(code, detail) { throw new Error(`${code} ${detail}`); }
const runsOf = job => (job?.steps ?? []).map(step => String(step.run ?? '')).join('\n');
const uploadsOf = job => (job?.steps ?? []).filter(step => String(step.uses ?? '').startsWith('actions/upload-artifact'))
  .map(step => String(step.with?.name ?? ''));
const localScripts = text => [...text.matchAll(/(?<![\w./-])((?:build|ci|scripts)\/[\w./-]+\.(?:mjs|sh|py))/g)].map(m => m[1]);

// The real plan producer (target-matrix.mjs) gives the matrices the source jobs expand.
export function planOutputs(target, repo = REPO) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-wiring-plan-')), out = path.join(dir, 'out');
  try {
    const r = spawnSync(process.execPath, [path.join(repo, PRODUCERS_DIR, 'srcbuild/target-matrix.mjs'), '--targets', target],
      {cwd: repo, encoding: 'utf8', env: {...process.env, GITHUB_OUTPUT: out}});
    if (r.status !== 0) return {planned: false, error: (r.stderr || r.stdout).trim().split('\n').pop()};
    return {planned: true, ...Object.fromEntries(fs.readFileSync(out, 'utf8').trim().split('\n')
      .map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))};
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

// Names a job uploads once `${{ matrix.KEY }}` is expanded over its static or planned matrix.
function expandedUploads(job, plan) {
  const m = job?.strategy?.matrix;
  let rows = [{}];
  if (typeof m === 'string') {
    const key = /needs\.plan\.outputs\.(\w+)/.exec(m)?.[1];
    // The full `cells` table (runnable and blocked) proves the wiring; readiness is reported separately.
    rows = key ? JSON.parse(plan[key === 'matrix' ? 'cells' : key] ?? '{"include":[]}').include : [];
  } else if (m?.include) rows = m.include;
  return new Set(uploadsOf(job).flatMap(name => rows.map(row => name.replace(/\$\{\{\s*matrix\.(\w+)\s*\}\}/g, (_, k) => row[k] ?? `<${k}>`))));
}

export function loadWorkflows(repo = REPO) {
  return Object.fromEntries(Object.entries(WORKFLOWS).map(([k, f]) => [k, load(fs.readFileSync(path.join(repo, f), 'utf8'))]));
}

export function checkProductionWiring({workflows = loadWorkflows(), exists = f => fs.existsSync(path.join(REPO, f)),
  plan = planOutputs} = {}) {
  const {release, source} = workflows, jobs = release?.jobs ?? {}, plans = new Map();
  const planFor = host => { if (!plans.has(host)) plans.set(host, plan(host)); return plans.get(host); };
  const callsSdkBuild = j => String(j?.uses ?? '').endsWith('/sdk-build.yml');
  const packages = Object.entries(jobs).filter(([, j]) => callsSdkBuild(j) && j.with?.mode === 'package');
  const pkgJob = workflows.package?.jobs?.package;
  if (!/inputs\.mode == 'package'/.test(String(pkgJob?.if ?? '')) || !(pkgJob?.steps ?? []).length)
    fail('WIRING_PACKAGE_JOB', `${WORKFLOWS.package} jobs.package`);
  if (!String(workflows.package?.jobs?.srcbuild?.uses ?? '').endsWith('/sdk-build-target.yml'))
    fail('WIRING_SOURCE_CALL', `${WORKFLOWS.package} jobs.srcbuild`);
  const keys = packages.map(([, j]) => j.with?.release_key);
  for (const asset of ASSETS) if (!keys.includes(asset.key)) fail('WIRING_PACKAGE_MISSING', asset.key);
  if (packages.length !== ASSETS.length || new Set(keys).size !== keys.length) fail('WIRING_PACKAGE_SET', keys.join(','));
  const publishNeeds = new Set([].concat(jobs.publish?.needs ?? []));
  const before = name => { const seen = new Set(), todo = [].concat(jobs[name]?.needs ?? []);
    while (todo.length) { const n = todo.pop(); if (!seen.has(n)) { seen.add(n); todo.push(...[].concat(jobs[n]?.needs ?? [])); } }
    return seen; };
  const result = [];
  for (const [name, job] of packages) {
    const asset = ASSETS.find(a => a.key === job.with.release_key);
    if (!publishNeeds.has(name)) fail('WIRING_PUBLISH_NEEDS', name);
    const hostJob = HOST_SOURCE_JOBS[asset.host];
    if (!callsSdkBuild(jobs[hostJob]) || (jobs[hostJob]?.with?.mode ?? 'build') !== 'build' || jobs[hostJob]?.with?.targets !== asset.host)
      fail('WIRING_HOST_SOURCE', `${asset.key} ${hostJob}`);
    if (!publishNeeds.has(hostJob)) fail('WIRING_PUBLISH_NEEDS', hostJob);
    if (!before(name).has(hostJob)) fail('WIRING_PRODUCER_NEEDS', `${name} ${hostJob}`);
    const std = String(job.with.std_artifact ?? '');
    if (std !== `\${{ needs.${hostJob}.outputs.std_artifact }}` && planFor(asset.host).planned) {
      const hostPlan = planFor(asset.host), made = new Set(['source-stage3', 'native-windows-sdk']
        .flatMap(j => [...expandedUploads(source?.jobs?.[j], hostPlan)]));
      if (!made.has(std)) fail('WIRING_HOST_STD_UNPRODUCED', `${asset.key} ${std}`);
    }
    const cross = JSON.parse(job.with.cross_std_artifacts ?? '[]');
    const tuples = cross.map(c => c.tuple);
    if (JSON.stringify([...tuples].sort()) !== JSON.stringify([...asset.crossTuples].sort()))
      fail('WIRING_CROSS_TUPLES', `${asset.key} release=${tuples} table=${asset.crossTuples}`);
    const producers = [];
    for (const {tuple, artifact} of cross) {
      const p = CROSS_PRODUCERS[tuple];
      if (!p || p.artifact !== artifact) fail('WIRING_ARTIFACT_NAME', `${asset.key} ${tuple} ${artifact}`);
      const producer = HOST_SOURCE_JOBS[p.host];
      if (!before(name).has(producer)) fail('WIRING_PRODUCER_NEEDS', `${name} ${producer}`);
      const sjob = source?.jobs?.[p.job];
      if (!planFor(p.host).planned) fail('WIRING_PRODUCER_UNPLANNED', `${p.host} ${planFor(p.host).error}`);
      if (!expandedUploads(sjob, planFor(p.host)).has(artifact)) fail('WIRING_ARTIFACT_UNPRODUCED', `${p.job} ${artifact}`);
      const runs = runsOf(sjob);
      for (const step of p.steps) {
        const file = `${PRODUCERS_DIR}/${step}`;
        if (!exists(file)) fail('WIRING_STEP_MISSING', file);
        if (!runs.includes(file)) fail('WIRING_STEP_NOT_RUN', `${p.job} ${file}`);
      }
      producers.push({tuple, artifact, job: p.job, source: producer, steps: p.steps.map(s => `${PRODUCERS_DIR}/${s}`)});
    }
    const hp = planFor(asset.host), cell = hp.planned ? JSON.parse(hp.cells).include.find(c => c.target === asset.host) : null;
    const readiness = hp.planned ? {status: cell?.status ?? 'absent', reasons: cell?.reasons ?? []} : {status: 'unplanned', reasons: [hp.error]};
    result.push({asset: asset.key, host: asset.host, runner: HOSTS[asset.host].runner, package: name, source: hostJob, std, readiness, producers});
  }
  // No production workflow may run a script that is gone or still lives in a retired producer tree.
  for (const [kind, doc] of Object.entries(workflows)) for (const job of Object.values(doc?.jobs ?? {})) for (const file of localScripts(runsOf(job))) {
    if (/^ci\/(srcbuild|release|platform_matrix|platform_tuples)\//.test(file)) fail('WIRING_RETIRED_TREE', `${kind} ${file}`);
    if (!exists(file)) fail('WIRING_SCRIPT_MISSING', `${kind} ${file}`);
  }
  return result;
}
