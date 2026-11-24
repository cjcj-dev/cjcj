#!/usr/bin/env node
// Fail-closed release publication contract for .github/workflows/release.yml.
//
//   verify-assets: the merged pkg-* download must be exactly the 15 distinct archiveKeys
//     of build/lib/targets.mjs, four files each (archive, .sha256, .RELEASE-MANIFEST.jsonl,
//     .SHA256SUMS), 60 in total, no pkg-diagnosis-* or other stray file; every digest and
//     the sidecar manifest must match the archive and the manifest packed inside it.
//   verify-needs: both direct `needs` of publish (plan, the 15-cell package matrix)
//     concluded `success`.
//   verify-ci-run: ci_run_id (required unless dry_run) must be a successful ci.yml run of GITHUB_SHA.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {allReleasePlatforms, getReleasePlatform} from '../build/lib/targets.mjs';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';

export const EXPECTED_ARCHIVE_COUNT = 15;
export const FILES_PER_ARCHIVE = 4;
export const EXPECTED_NEEDS = 2;
export const PUBLISH_NEEDS = Object.freeze(['package', 'plan']);

export function expectedArchiveKeys() {
  const keys = [...new Set(allReleasePlatforms().map(getReleasePlatform)
    .filter(platform => !platform.excluded && !platform.crossCompiledHost).map(platform => platform.archiveKey))].sort();
  if (keys.length !== EXPECTED_ARCHIVE_COUNT) throw new Error(`PUBLISH_ARCHIVE_KEYS ${keys.length} != ${EXPECTED_ARCHIVE_COUNT}: ${keys.join(',')}`);
  return keys;
}

const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function run(command, args) {
  const result = spawnSync(command, args, {encoding: 'buffer', maxBuffer: 1 << 30});
  if (result.error || result.status !== 0) {
    throw new Error(`PUBLISH_ARCHIVE_READ ${command} ${args.join(' ')}: ${result.error?.message || result.stderr.toString().trim()}`);
  }
  return result.stdout;
}

// The manifest that the package step packed into the archive; exactly one is allowed.
export function internalManifest(archive) {
  const zip = archive.endsWith('.zip');
  const members = run(zip ? 'unzip' : 'tar', zip ? ['-Z1', archive] : ['-tzf', archive]).toString('utf8')
    .split('\n').map(line => line.trim()).filter(Boolean)
    .filter(member => member === 'RELEASE-MANIFEST.jsonl' || member.endsWith('/RELEASE-MANIFEST.jsonl'));
  if (members.length !== 1) throw new Error(`PUBLISH_INTERNAL_MANIFEST ${path.basename(archive)} has ${members.length} RELEASE-MANIFEST.jsonl`);
  return run(zip ? 'unzip' : 'tar', zip ? ['-p', archive, members[0]] : ['-xOzf', archive, members[0]]);
}

export function verifyAssets({dist, version, keys = expectedArchiveKeys(), readInternal = internalManifest}) {
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$/.test(version || '')) throw new Error(`PUBLISH_VERSION ${version}`);
  const present = fs.readdirSync(dist, {recursive: true, withFileTypes: true})
    .filter(entry => entry.isFile()).map(entry => path.relative(dist, path.join(entry.parentPath ?? entry.path, entry.name))).sort();
  const diagnosis = present.filter(file => /(^|\/)pkg-diagnosis-/.test(file));
  if (diagnosis.length) throw new Error(`PUBLISH_DIAGNOSIS_ASSET ${diagnosis.join(',')}`);
  const expected = [];
  for (const key of keys) {
    const stem = `cjcj-${version}-${key}`;
    const archives = present.filter(file => file === `${stem}.tar.gz` || file === `${stem}.zip`);
    if (archives.length !== 1) throw new Error(`PUBLISH_ARCHIVE_CELL ${key} has ${archives.length} archives`);
    const archive = archives[0];
    const cell = [archive, `${archive}.sha256`, `${stem}.RELEASE-MANIFEST.jsonl`, `${stem}.SHA256SUMS`];
    for (const file of cell) if (!present.includes(file)) throw new Error(`PUBLISH_CELL_FILE ${key} missing ${file}`);
    const digest = sha256(path.join(dist, archive));
    const sidecar = fs.readFileSync(path.join(dist, `${archive}.sha256`), 'utf8').trim().split(/\s+/);
    if (sidecar[0] !== digest || (sidecar[1] && path.basename(sidecar[1].replace(/^\*/, '')) !== archive)) {
      throw new Error(`PUBLISH_SHA256 ${archive}`);
    }
    const sums = fs.readFileSync(path.join(dist, `${stem}.SHA256SUMS`), 'utf8').split('\n').filter(Boolean)
      .map(line => line.trim().split(/\s+/)).filter(([, name]) => name && path.basename(name.replace(/^\*/, '')) === archive);
    if (sums.length !== 1 || sums[0][0] !== digest) throw new Error(`PUBLISH_SHA256SUMS ${archive}`);
    const manifest = fs.readFileSync(path.join(dist, `${stem}.RELEASE-MANIFEST.jsonl`));
    if (!Buffer.from(readInternal(path.join(dist, archive))).equals(manifest)) throw new Error(`PUBLISH_MANIFEST_MISMATCH ${key}`);
    expected.push(...cell);
  }
  const stray = present.filter(file => !expected.includes(file));
  if (stray.length) throw new Error(`PUBLISH_STRAY_ASSET ${stray.join(',')}`);
  if (expected.length !== keys.length * FILES_PER_ARCHIVE) throw new Error(`PUBLISH_ASSET_COUNT ${expected.length}`);
  return expected.map(file => path.join(dist, file));
}

// Each artifact downloads into its own directory (merge-multiple: false), so
// the selection is by artifact name: exactly one pkg-<archiveKey> per key.
// pkg-diagnosis-* (failure evidence of any attempt) is excluded by its name;
// any other artifact, missing key or nested/colliding file fails closed.
export function selectPackageArtifacts({from, to, keys = expectedArchiveKeys()}) {
  const entries = fs.readdirSync(from, {withFileTypes: true});
  const selected = [], excluded = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) throw new Error(`PUBLISH_ARTIFACT_LAYOUT ${entry.name}`);
    if (entry.name.startsWith('pkg-diagnosis-')) { excluded.push(entry.name); continue; }
    if (!entry.name.startsWith('pkg-') || !keys.includes(entry.name.slice(4))) throw new Error(`PUBLISH_ARTIFACT_UNEXPECTED ${entry.name}`);
    selected.push(entry.name);
  }
  const missing = keys.filter(key => !selected.includes(`pkg-${key}`));
  if (missing.length) throw new Error(`PUBLISH_ARTIFACT_MISSING ${missing.join(',')}`);
  if (fs.existsSync(to) && fs.readdirSync(to).length) throw new Error(`PUBLISH_DIST_NOT_EMPTY ${to}`);
  fs.mkdirSync(to, {recursive: true});
  for (const name of selected.sort()) for (const file of fs.readdirSync(path.join(from, name), {withFileTypes: true})) {
    if (!file.isFile()) throw new Error(`PUBLISH_ARTIFACT_LAYOUT ${name}/${file.name}`);
    const destination = path.join(to, file.name);
    if (fs.existsSync(destination)) throw new Error(`PUBLISH_ARTIFACT_COLLISION ${file.name}`);
    fs.copyFileSync(path.join(from, name, file.name), destination);
  }
  return {selected: selected.sort(), excluded: excluded.sort()};
}

export function verifyNeeds(needs) {
  const entries = Object.entries(needs || {});
  if (entries.length !== EXPECTED_NEEDS) throw new Error(`PUBLISH_NEEDS_COUNT ${entries.length} != ${EXPECTED_NEEDS}`);
  const failed = entries.filter(([, value]) => value?.result !== 'success').map(([name, value]) => `${name}=${value?.result}`);
  if (failed.length) throw new Error(`PUBLISH_NEEDS_NOT_SUCCESS ${failed.join(',')}`);
  return entries.length;
}

export function verifyCiRun(run, sha) {
  if (!/^[0-9a-f]{40}$/.test(sha || '')) throw new Error(`PUBLISH_CI_SHA ${sha}`);
  if (run?.head_sha !== sha) throw new Error(`PUBLISH_CI_HEAD_SHA ${run?.head_sha} != ${sha}`);
  if (run?.status !== 'completed' || run?.conclusion !== 'success') throw new Error(`PUBLISH_CI_CONCLUSION ${run?.status}/${run?.conclusion}`);
  if (run?.path && run.path !== '.github/workflows/ci.yml') throw new Error(`PUBLISH_CI_WORKFLOW ${run.path}`);
  return run.id;
}

// Static contract of release.yml, used by ci/release-publish.test.mjs and its red cuts.
// Four stages, each fully parallel: plan -> source (one sdk-build.yml call for every
// host) -> package (one 15-cell sdk-package.yml matrix) -> publish.
export function releaseWorkflowProblems(text) {
  const workflow = loadYaml(text);
  const problems = [];
  const inputs = workflow?.on?.workflow_dispatch?.inputs || {};
  if (inputs.phase) problems.push('phase must not exist: prepare.yml owns the native inputs');
  if (inputs.ci_run_id?.type !== 'string' || inputs.ci_run_id?.required) problems.push('ci_run_id must be an optional string');
  const jobs = workflow?.jobs || {};
  if (JSON.stringify(Object.keys(jobs).sort()) !== JSON.stringify(['package', 'plan', 'publish', 'source']))
    problems.push(`release jobs must be exactly plan, source, package, publish: ${Object.keys(jobs).sort()}`);
  const plan = jobs.plan;
  const planScript = (plan?.steps || []).map(step => step.run || '').join('\n');
  if (!plan || plan.if !== undefined || plan.needs !== undefined) problems.push('plan must run unconditionally first');
  for (const [needle, label] of [
    ['target-matrix.mjs --targets all --require-ready', 'every source target ready'],
    ['PUBLISH_CI_RUN_ID_REQUIRED', 'ci_run_id required unless dry_run'],
    ['node ci/release-publish.mjs verify-ci-run', 'ci_run_id verification'],
  ]) if (!planScript.includes(needle)) problems.push(`plan lacks ${label}`);
  const source = jobs.source;
  if (source?.uses !== './.github/workflows/sdk-build.yml' || source?.needs !== 'plan' || source?.if !== undefined)
    problems.push('source must be one unconditional sdk-build.yml call that needs plan');
  if (source?.with?.targets !== 'all') problems.push('source must build every target in one call (targets: all)');
  for (const key of ['build_android', 'build_wasm', 'build_ohos', 'build_ios'])
    if (source?.with?.[key] !== true) problems.push(`source must set ${key}: true`);
  const pkg = jobs.package;
  const rows = pkg?.strategy?.matrix?.include || [];
  if (pkg?.uses !== './.github/workflows/sdk-package.yml' || pkg?.needs !== 'source' || pkg?.if !== undefined)
    problems.push('package must be one unconditional sdk-package.yml matrix that needs source');
  if (pkg?.strategy?.['fail-fast'] !== false || pkg?.strategy?.['max-parallel'] !== undefined)
    problems.push('package must run every cell in parallel with fail-fast: false');
  const keys = rows.map(row => row.release_key).sort();
  const expected = allReleasePlatforms().filter(key => { const platform = getReleasePlatform(key); return !platform.excluded && !platform.crossCompiledHost; }).sort();
  if (rows.length !== EXPECTED_ARCHIVE_COUNT || JSON.stringify(keys) !== JSON.stringify(expected))
    problems.push(`package matrix must hold the ${EXPECTED_ARCHIVE_COUNT} release keys: ${keys}`);
  for (const field of ['runner', 'platform', 'llvm_platform', 'sdk_runtime_dir', 'release_key', 'std_artifact', 'cross_std_artifacts'])
    if (pkg?.with?.[field] !== `\${{ matrix.${field} }}`) problems.push(`package does not pass matrix.${field}`);
  const publish = jobs.publish;
  if (!publish) return [...problems, 'publish job missing'];
  const condition = String(publish.if || '');
  if (/always\(\)|cancelled\(\)|failure\(\)/.test(condition)) problems.push('publish must not use always()/cancelled()/failure()');
  if (!condition.includes('!inputs.dry_run')) problems.push('publish must require !inputs.dry_run');
  const needs = [...(publish.needs || [])].sort();
  if (JSON.stringify(needs) !== JSON.stringify(PUBLISH_NEEDS)) problems.push(`publish needs ${needs}, expected ${PUBLISH_NEEDS}`);
  const script = (publish.steps || []).map(step => step.run || '').join('\n');
  for (const [needle, label] of [
    ['node ci/release-publish.mjs verify-needs', 'explicit needs success check'],
    ['node ci/release-publish.mjs verify-assets', 'asset verification'],
    ['node ci/release-publish.mjs verify-ci-run', 'ci_run_id verification'],
    ['node ci/release-publish.mjs select-packages', 'name-based package artifact selection'],
    ['-f sha="$GITHUB_SHA"', 'atomic tag claim at GITHUB_SHA'],
    ['flags=(--verify-tag ', '--verify-tag release creation on the claimed tag'],
    ['--prerelease --latest=false', '--prerelease --latest=false'],
    ['PUBLISH_FORMAL_RELEASE_NOT_AUTHORIZED', 'formal release refusal'],
    ['RELEASE_ALREADY_EXISTS', 'fail-closed existing release check'],
    ['TAG_ALREADY_EXISTS', 'fail-closed existing tag check'],
    ['PUBLISH_READBACK_TAG', 'tag readback'],
    ['PUBLISH_READBACK_RELEASE', 'release readback'],
  ]) if (!script.includes(needle)) problems.push(`publish lacks ${label}`);
  const download = (publish.steps || []).find(step => String(step.uses || '').startsWith('actions/download-artifact@'));
  if (download?.with?.pattern !== 'pkg-*' || download?.with?.['merge-multiple'] !== false)
    problems.push('publish must download pkg-* into per-artifact directories');
  if (!publish.environment) problems.push('publish must run in a deployment environment (manual approval entry)');
  for (const [name, job] of [['source', source], ['package', pkg]]) {
    for (const key of ['native_runtime_artifact', 'native_llvm_ref', 'native_runtime_ref', 'native_host_version']) {
      if (job?.with?.[key] !== `\${{ inputs.${key} }}`) problems.push(`${name} does not pass ${key}`);
    }
  }
  return problems;
}

function option(argv, name) {
  const index = argv.indexOf(`--${name}`);
  return index >= 0 ? argv[index + 1] : undefined;
}

function main(argv) {
  const command = argv[0];
  if (command === 'select-packages') {
    const result = selectPackageArtifacts({from: option(argv, 'from'), to: option(argv, 'to')});
    console.log(`PUBLISH_PACKAGES_SELECTED ${result.selected.length} excluded=${result.excluded.join(',') || 'none'}`);
  } else if (command === 'verify-assets') {
    const assets = verifyAssets({dist: option(argv, 'dist'), version: option(argv, 'version')});
    fs.writeFileSync(option(argv, 'output'), assets.join('\n') + '\n');
    console.log(`PUBLISH_ASSETS_VERIFIED archives=${assets.length / FILES_PER_ARCHIVE} files=${assets.length}`);
  } else if (command === 'verify-needs') {
    console.log(`PUBLISH_NEEDS_VERIFIED ${verifyNeeds(JSON.parse(process.env.PUBLISH_NEEDS_JSON || 'null'))}`);
  } else if (command === 'verify-ci-run') {
    const run = JSON.parse(fs.readFileSync(option(argv, 'run-json'), 'utf8'));
    console.log(`PUBLISH_CI_RUN_VERIFIED ${verifyCiRun(run, option(argv, 'sha'))}`);
  } else if (command === 'check-workflow') {
    const problems = releaseWorkflowProblems(fs.readFileSync(option(argv, 'workflow') || '.github/workflows/release.yml', 'utf8'));
    for (const problem of problems) console.error(`RELEASE_WORKFLOW ${problem}`);
    return problems.length ? 1 : 0;
  } else {
    console.error('usage: release-publish.mjs select-packages|verify-assets|verify-needs|verify-ci-run|check-workflow');
    return 2;
  }
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  try { process.exitCode = main(process.argv.slice(2)); } catch (error) { console.error(`FATAL: ${error.message}`); process.exitCode = 1; }
}
