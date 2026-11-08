#!/usr/bin/env zx
// Persist the exact full native SDK artifact that ci.yml package-tests accepted
// as a new immutable prerelease, read it back through the ordinary consumer
// (download_pinned.mjs) and emit the reviewed registry entry. Publication only
// follows acceptance: the workflow job needs a successful candidate-mode
// package-tests, and this script independently rejects a producer whose
// srcbuild gate job did not succeed (its upload step runs under always()).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {api, asset, digest, verify} from './bootstrap_store.mjs';
import {downloadPinned, nativeSdkPin} from './download_pinned.mjs';
import {unpackNativeSdk} from './receive_native_sdk.mjs';
import {getTarget} from '../../build/lib/targets.mjs';

const VERSION = /^[0-9A-Za-z][0-9A-Za-z._-]*$/;
const ID = /^[1-9][0-9]*$/;
export const artifactName = (target, version) => `cjcj-srcbuild-${target}-${version}`;
const DIGEST = /^sha256:[a-f0-9]{64}$/;
// GitHub rejects release assets of 2 GiB or more; refuse before any transfer.
export const MAX_ASSET_BYTES = 2 * 1024 ** 3 - 1;
// Top-level workflows whose dispatched run reaches srcbuild-target.yml:
// srcbuild.yml itself and the callers that reach it through srcbuild.yml. The
// run event must be workflow_dispatch, so no push, PR or fork run can produce an
// input.
export const PRODUCER_WORKFLOWS = ['.github/workflows/srcbuild.yml', '.github/workflows/release.yml',
  '.github/workflows/release-matrix.yml', '.github/workflows/arm-soak.yml'];

function fail(code, detail = '') { throw new Error(`${code}${detail ? ' ' + detail : ''}`); }

async function status(route) {
  const response = await fetch(`https://api.github.com${route}`, {headers: {Accept: 'application/vnd.github+json',
    ...(process.env.GITHUB_TOKEN ? {Authorization: `Bearer ${process.env.GITHUB_TOKEN}`} : {})}});
  return response.status;
}

async function pages(route, key) {
  const items = [];
  for (let page = 1; page <= 20; page++) {
    const body = await (await api(`${route}${route.includes('?') ? '&' : '?'}per_page=100&page=${page}`)).json();
    const batch = key ? body[key] : body;
    items.push(...batch);
    if (batch.length < 100) return items;
  }
  fail('NATIVE_SDK_PAGINATION_LIMIT', route);
}

// Candidate mode resolves the fresh producer run to its one exact artifact ID;
// the default mode consumes only the committed registry entry.
export async function select(target, env = process.env) {
  getTarget(target);
  const run = env.CANDIDATE_RUN || '';
  const version = env.CANDIDATE_VERSION || '';
  if (!run && !version) {
    const pin = nativeSdkPin('cjcj-dev/cjcj', target);
    return {mode: 'persisted', artifact: pin.artifact, version: pin.version, run: '', tag: pin.tag};
  }
  if (!ID.test(run) || !VERSION.test(version)) fail('NATIVE_SDK_CANDIDATE_INPUT_INCOMPLETE', 'native_sdk_run_id and native_sdk_version are both required');
  const name = artifactName(target, version);
  const listed = await (await api(`/repos/${env.GITHUB_REPOSITORY}/actions/runs/${run}/artifacts?name=${encodeURIComponent(name)}&per_page=100`)).json();
  const matches = (listed.artifacts || []).filter(item => item.name === name);
  if (matches.length !== 1) fail('NATIVE_SDK_CANDIDATE_ARTIFACT_COUNT', `name=${name} run=${run} count=${matches.length}`);
  if (matches[0].expired) fail('NATIVE_SDK_CANDIDATE_ARTIFACT_EXPIRED', `artifact=${matches[0].id}`);
  return {mode: 'candidate', artifact: String(matches[0].id), version, run, tag: ''};
}

// The exact artifact by ID: identity, expiry, recorded digest and size are
// checked before any byte is transferred.
async function exactArtifact(repository, artifactId, name, run) {
  const artifact = await (await api(`/repos/${repository}/actions/artifacts/${artifactId}`)).json();
  if (String(artifact.id) !== artifactId || artifact.name !== name || String(artifact.workflow_run?.id) !== run || artifact.expired) {
    fail('NATIVE_SDK_ARTIFACT_IDENTITY_MISMATCH', `artifact=${artifactId} name=${artifact.name} run=${artifact.workflow_run?.id} expired=${artifact.expired}`);
  }
  if (!DIGEST.test(artifact.digest || '')) fail('NATIVE_SDK_ARTIFACT_DIGEST_MISSING', `artifact=${artifactId}`);
  if (!Number.isSafeInteger(artifact.size_in_bytes) || artifact.size_in_bytes < 1 || artifact.size_in_bytes > MAX_ASSET_BYTES) {
    fail('NATIVE_SDK_ARTIFACT_SIZE_INVALID', `artifact=${artifactId} size=${artifact.size_in_bytes} limit=${MAX_ASSET_BYTES}`);
  }
  return artifact;
}

async function artifactZip(repository, artifact) {
  const zip = Buffer.from(await (await api(`/repos/${repository}/actions/artifacts/${artifact.id}/zip`)).arrayBuffer());
  const actual = `sha256:${digest(zip)}`;
  if (actual !== artifact.digest) fail('NATIVE_SDK_ARTIFACT_DIGEST_MISMATCH', `artifact=${artifact.id} recorded=${artifact.digest} actual=${actual}`);
  return zip;
}

// The producer is an allowed dispatch-only workflow of this repository. Its
// current attempt ran the target's srcbuild gate job (package-install,
// source-tool install, verify) to success, and the artifact was created inside
// that job execution, so bytes uploaded by a failed earlier attempt under the
// same name are refused. The producer commit must be in the accepting history.
async function producerBinding(repository, run, target, artifact, accepted) {
  const producerRun = await (await api(`/repos/${repository}/actions/runs/${run}`)).json();
  const attempt = producerRun.run_attempt;
  if (String(producerRun.id) !== run || !PRODUCER_WORKFLOWS.includes(producerRun.path) || producerRun.event !== 'workflow_dispatch'
      || producerRun.status !== 'completed' || producerRun.head_repository?.full_name !== repository
      || !/^[a-f0-9]{40}$/.test(producerRun.head_sha || '') || !Number.isSafeInteger(attempt) || attempt < 1) {
    fail('NATIVE_SDK_PRODUCER_RUN_NOT_ALLOWED', `run=${run} workflow=${producerRun.path} event=${producerRun.event} status=${producerRun.status}`);
  }
  if (artifact.workflow_run?.head_sha !== producerRun.head_sha) fail('NATIVE_SDK_PRODUCER_PROVENANCE_MISMATCH');
  const jobs = (await pages(`/repos/${repository}/actions/runs/${run}/attempts/${attempt}/jobs`, 'jobs'))
    .filter(job => job.name === `${target} / srcbuild` || job.name.endsWith(` / ${target} / srcbuild`));
  const job = jobs[0];
  if (jobs.length !== 1 || String(job.run_id) !== run || job.run_attempt !== attempt || job.head_sha !== producerRun.head_sha
      || job.status !== 'completed' || job.conclusion !== 'success') {
    fail('NATIVE_SDK_PRODUCER_GATE_NOT_PASSED', `attempt=${attempt} jobs=${JSON.stringify(jobs.map(item => [item.name, item.run_attempt, item.conclusion]))}`);
  }
  const created = Date.parse(artifact.created_at);
  if (!(Date.parse(job.started_at) <= created && created <= Date.parse(job.completed_at))) {
    fail('NATIVE_SDK_ARTIFACT_ATTEMPT_MISMATCH', `artifact=${artifact.id} created=${artifact.created_at} job=${job.id} attempt=${attempt} window=${job.started_at}..${job.completed_at}`);
  }
  const compare = await (await api(`/repos/${repository}/compare/${producerRun.head_sha}...${accepted}`)).json();
  if (!['identical', 'ahead'].includes(compare.status)) {
    fail('NATIVE_SDK_PRODUCER_HEAD_NOT_ANCESTOR', `producer=${producerRun.head_sha} accepted=${accepted} status=${compare.status}`);
  }
  return {run: Number(run), attempt, commit: producerRun.head_sha, workflow: producerRun.path, event: producerRun.event,
    job: {id: job.id, name: job.name, attempt: job.run_attempt, url: job.html_url, conclusion: job.conclusion,
      started_at: job.started_at, completed_at: job.completed_at}};
}

// Candidate acceptance consumes the exact selected artifact ID (never a name
// lookup) after the same producer binding the publisher applies, and reports the
// digest of the bytes it unpacked; publication must then match that digest.
export async function receiveCandidate(target, dest, env = process.env) {
  getTarget(target);
  const repository = env.GITHUB_REPOSITORY;
  const artifactId = env.CANDIDATE_ARTIFACT || '';
  const run = env.CANDIDATE_RUN || '';
  const version = env.CANDIDATE_VERSION || '';
  if (!ID.test(artifactId) || !ID.test(run) || !VERSION.test(version) || !/^[a-f0-9]{40}$/.test(env.GITHUB_SHA || '')) {
    fail('NATIVE_SDK_CANDIDATE_INPUT_INCOMPLETE', 'selected artifact, run, version and GITHUB_SHA are required');
  }
  if (fs.existsSync(dest) && fs.readdirSync(dest).length) fail('NATIVE_SDK_CANDIDATE_DEST_NOT_EMPTY', dest);
  const artifact = await exactArtifact(repository, artifactId, artifactName(target, version), run);
  const producer = await producerBinding(repository, run, target, artifact, env.GITHUB_SHA);
  const zip = await artifactZip(repository, artifact);
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'native-sdk-candidate-'));
  try {
    const zipFile = path.join(scratch, 'artifact.zip');
    fs.writeFileSync(zipFile, zip);
    fs.mkdirSync(dest, {recursive: true});
    if (spawnSync('unzip', ['-q', zipFile, '-d', dest]).status !== 0) fail('NATIVE_SDK_ARTIFACT_ZIP_INVALID');
  } finally { fs.rmSync(scratch, {recursive: true, force: true}); }
  console.error(`NATIVE_SDK_CANDIDATE_RECEIVED artifact=${artifactId} digest=${artifact.digest} run=${run} attempt=${producer.attempt} job=${producer.job.id}`);
  return {digest: artifact.digest};
}

function zipList(file) {
  const result = spawnSync('unzip', ['-Z1', file], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  if (result.status !== 0) fail('NATIVE_SDK_ARTIFACT_ZIP_INVALID');
  return result.stdout.split('\n').filter(Boolean);
}
function zipMember(file, member) {
  const result = spawnSync('unzip', ['-p', file, member], {maxBuffer: 4 * 1024 * 1024 * 1024});
  if (result.status !== 0) fail('NATIVE_SDK_ARTIFACT_MEMBER_MISSING', member);
  return result.stdout;
}

async function upload(release, name, bytes, contentType) {
  if (bytes.length > MAX_ASSET_BYTES) fail('NATIVE_SDK_ASSET_TOO_LARGE', `${name} size=${bytes.length} limit=${MAX_ASSET_BYTES}`);
  const response = await fetch(`${release.upload_url.split('{')[0]}?name=${encodeURIComponent(name)}`, {method: 'POST',
    headers: {Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, 'Content-Type': contentType}, body: bytes});
  if (!response.ok) fail('NATIVE_SDK_UPLOAD_FAILED', `${response.status} ${name}`);
  const uploaded = await response.json();
  const readback = await asset(process.env.GITHUB_REPOSITORY, uploaded.id);
  verify(readback, digest(bytes), name);
  return {name, id: uploaded.id, sha256: digest(readback), size: readback.length};
}

export async function publish(target, outdir, env = process.env) {
  const spec = getTarget(target).spec;
  const repository = env.GITHUB_REPOSITORY;
  const artifactId = env.NATIVE_SDK_ARTIFACT_ID || '';
  const run = env.NATIVE_SDK_RUN_ID || '';
  const version = env.NATIVE_SDK_VERSION || '';
  const accepted = env.NATIVE_SDK_ACCEPTED_DIGEST || '';
  if (repository !== 'cjcj-dev/cjcj' || !ID.test(artifactId) || !ID.test(run) || !VERSION.test(version) || !DIGEST.test(accepted)
      || !ID.test(env.GITHUB_RUN_ID || '') || !ID.test(env.GITHUB_RUN_ATTEMPT || '') || !/^[a-f0-9]{40}$/.test(env.GITHUB_SHA || '')) {
    fail('NATIVE_SDK_PERSIST_INPUT_INVALID');
  }
  fs.mkdirSync(outdir, {recursive: true});
  const name = artifactName(target, version);
  const provenance = {version: 1, kind: 'cjcj-full-native-sdk', target, sdk_version: version,
    acceptance: {repository, run: Number(env.GITHUB_RUN_ID), attempt: Number(env.GITHUB_RUN_ATTEMPT), commit: env.GITHUB_SHA,
      job: env.ACCEPTANCE_JOB || 'package-tests', workflow: env.GITHUB_WORKFLOW_REF || '', digest: accepted}};
  const record = () => fs.writeFileSync(path.join(outdir, 'provenance.json'), `${JSON.stringify(provenance, null, 2)}\n`);
  record();

  // 1. The accepted bytes: the exact artifact ID package-tests downloaded, with
  // the digest it recorded; nothing is re-resolved by name.
  const artifact = await exactArtifact(repository, artifactId, name, run);
  if (artifact.digest !== accepted) fail('NATIVE_SDK_ACCEPTED_DIGEST_MISMATCH', `artifact=${artifactId} recorded=${artifact.digest} accepted=${accepted}`);
  // 2. The producer gate: allowed workflow, exact attempt, successful srcbuild
  // job execution that created this artifact; artifact existence is not enough.
  const producer = await producerBinding(repository, run, target, artifact, env.GITHUB_SHA);
  provenance.producer = {...producer, artifact: {id: Number(artifactId), name, digest: artifact.digest, size: artifact.size_in_bytes,
    created_at: artifact.created_at, expires_at: artifact.expires_at}};
  record();

  // 3. Download the original artifact ZIP and require the packaged SDK inside it.
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'native-sdk-persist-'));
  try {
    const zip = await artifactZip(repository, artifact);
    const sha256 = digest(zip);
    const zipFile = path.join(scratch, 'artifact.zip');
    fs.writeFileSync(zipFile, zip);
    const members = zipList(zipFile);
    const archiveName = new RegExp(`^cangjie-sdk-${spec.sdkName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-${version.replace(/\./g, '\\.')}-cjcj\\.(tar\\.gz|zip)$`);
    const archives = members.filter(member => archiveName.test(member));
    if (archives.length !== 1 || !members.includes(`${archives[0]}.sha256`)) {
      fail('NATIVE_SDK_ARTIFACT_PACKAGE_MISSING', `members=${JSON.stringify(members)}`);
    }
    const sidecar = zipMember(zipFile, `${archives[0]}.sha256`).toString('utf8').trim();
    if (sidecar !== `${digest(zipMember(zipFile, archives[0]))}  ${archives[0]}`) fail('NATIVE_SDK_ARTIFACT_SIDECAR_MISMATCH');
    provenance.package = {archive: archives[0], sidecar, artifact_zip_sha256: sha256, members};
    record();

    // 4. Unique immutable tag; never reuse or overwrite a tag, release or asset.
    const tag = `native-sdk-${target}-${version}-${artifactId}-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}-prerelease`;
    const releases = await pages(`/repos/${repository}/releases`);
    if (releases.some(item => item.tag_name === tag) || await status(`/repos/${repository}/git/ref/tags/${tag}`) !== 404) {
      fail('NATIVE_SDK_TAG_EXISTS', tag);
    }
    const release = await (await api(`/repos/${repository}/releases`, {method: 'POST', body: JSON.stringify({
      tag_name: tag, target_commitish: producer.commit, name: tag, draft: true, prerelease: true, make_latest: 'false',
      body: `Temporary full native SDK prerelease for ${target} ${version}. Producer run ${run} attempt ${producer.attempt} job ${producer.job.id}; `
        + `accepted by run ${env.GITHUB_RUN_ID} attempt ${env.GITHUB_RUN_ATTEMPT} (${provenance.acceptance.job}). `
        + 'Current only while ci/bootstrap_artifacts_pin.json names it as the native_sdk entry for this target.'})})).json();
    provenance.release = {id: release.id, tag, assets: []};
    record();
    // Gate logs and source provenance are separate small assets, independent of the bulk SDK bytes.
    const logs = members.filter(member => member !== archives[0] && member !== `${archives[0]}.sha256`);
    provenance.release.assets.push(await upload(release, `${name}.zip`, zip, 'application/zip'));
    if (logs.length) {
      const logDir = path.join(scratch, 'logs');
      if (spawnSync('unzip', ['-q', zipFile, ...logs, '-d', logDir]).status !== 0) fail('NATIVE_SDK_LOG_EXTRACT_FAILED');
      const logZip = path.join(scratch, 'gate-logs.zip');
      if (spawnSync('zip', ['-q', '-r', logZip, '.'], {cwd: logDir}).status !== 0) fail('NATIVE_SDK_LOG_ARCHIVE_FAILED');
      provenance.release.assets.push(await upload(release, `${name}.gate-logs.zip`, fs.readFileSync(logZip), 'application/zip'));
    }
    record();
    const sdkAsset = provenance.release.assets[0];
    if (`sha256:${sdkAsset.sha256}` !== accepted) fail('NATIVE_SDK_PUBLISHED_DIGEST_MISMATCH', `asset=${sdkAsset.id} accepted=${accepted}`);
    const entry = {repository, asset: sdkAsset.id, release_sha256: sdkAsset.sha256, prerelease: true, tag,
      native_sdk: {target, version, producer_run: Number(run), acceptance_run: Number(env.GITHUB_RUN_ID)}};
    provenance.release.assets.push(await upload(release, `${name}.provenance.json`,
      Buffer.from(`${JSON.stringify({...provenance, registry_entry: {[artifactId]: entry}}, null, 2)}\n`), 'application/json'));
    record();

    // 5. Consumer readback before the draft becomes visible: the selection a
    // consumer performs after the registry switch, then the existing downloader
    // and package-fact unpack on the returned bytes.
    const registryFile = path.join(scratch, 'candidate-registry.json');
    const current = JSON.parse(fs.readFileSync(env.BOOTSTRAP_ARCHIVES_PIN || new URL('../bootstrap_artifacts_pin.json', import.meta.url), 'utf8'));
    const replaced = Object.entries(current.artifacts).filter(([, pin]) => pin?.native_sdk?.target === target).map(([id, pin]) => ({artifact: id, tag: pin.tag}));
    const artifacts = Object.fromEntries(Object.entries(current.artifacts).filter(([, pin]) => pin?.native_sdk?.target !== target));
    fs.writeFileSync(registryFile, JSON.stringify({...current, artifacts: {...artifacts, [artifactId]: entry}}));
    const childEnv = {...env, BOOTSTRAP_ARCHIVES_PIN: registryFile};
    const saved = process.env.BOOTSTRAP_ARCHIVES_PIN;
    process.env.BOOTSTRAP_ARCHIVES_PIN = registryFile;
    try {
      const chosen = nativeSdkPin(repository, target);
      if (chosen.artifact !== artifactId || chosen.version !== version) fail('NATIVE_SDK_READBACK_SELECTION_MISMATCH');
      const readZip = path.join(scratch, 'readback.zip');
      downloadPinned(repository, artifactId, readZip);
      const readDir = path.join(scratch, 'readback');
      if (spawnSync('unzip', ['-q', readZip, '-d', readDir]).status !== 0) fail('NATIVE_SDK_READBACK_EXTRACT_FAILED');
      const {facts} = await unpackNativeSdk(readDir, path.join(scratch, 'readback-install'), target, {...childEnv, CJCJ_NATIVE_SDK_VERSION: version});
      provenance.readback = {selected: chosen, facts: {target: facts.target, version: facts.version, consumption: facts.consumption}};
    } finally {
      if (saved === undefined) delete process.env.BOOTSTRAP_ARCHIVES_PIN; else process.env.BOOTSTRAP_ARCHIVES_PIN = saved;
    }
    record();

    // 6. Publish as prerelease only; never latest, never a formal release.
    await api(`/repos/${repository}/releases/${release.id}`, {method: 'PATCH', body: JSON.stringify({draft: false, prerelease: true, make_latest: 'false'})});
    const published = await (await api(`/repos/${repository}/releases/${release.id}`)).json();
    const names = (published.assets || []).map(item => `${item.id}:${item.name}`).sort();
    const expected = provenance.release.assets.map(item => `${item.id}:${item.name}`).sort();
    if (published.draft !== false || published.prerelease !== true || published.tag_name !== tag || JSON.stringify(names) !== JSON.stringify(expected)) {
      fail('NATIVE_SDK_RELEASE_STATE_MISMATCH');
    }
    if (await status(`/repos/${repository}/releases/latest`) === 200) {
      const latest = await (await api(`/repos/${repository}/releases/latest`)).json();
      if (latest.id === release.id) fail('NATIVE_SDK_BECAME_LATEST');
    }
    // 7. Retention: report-only. The old release is retired by a maintainer only
    // after the registry switch is on master, consumers pass on the new entry, and
    // no active branch or frozen evidence still references the old artifact ID.
    const retire = releases.filter(item => item.tag_name.startsWith(`native-sdk-${target}-`) && item.tag_name !== tag)
      .map(item => ({id: item.id, tag: item.tag_name, current: replaced.some(pin => pin.tag === item.tag_name)}));
    provenance.retention = {policy: 'single current native_sdk entry per target; retire manually after switch verification', candidates: retire};
    record();
    fs.writeFileSync(path.join(outdir, 'registry-entry.json'), `${JSON.stringify({[artifactId]: entry}, null, 2)}\n`);
    for (const item of retire) console.log(`NATIVE_SDK_RETIRE_CANDIDATE tag=${item.tag} release=${item.id} current=${item.current} action=kept`);
    console.log(`NATIVE_SDK_PERSISTED tag=${tag} release=${release.id} artifact=${artifactId} asset=${sdkAsset.id} sha256=${sdkAsset.sha256}`);
    return {tag, entry, artifactId};
  } finally { fs.rmSync(scratch, {recursive: true, force: true}); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, target, outdir, ...extra] = process.argv.slice(2);
  try {
    if (command === 'select' && target && !outdir) {
      const selected = await select(target);
      for (const [key, value] of Object.entries(selected)) process.stdout.write(`${key}=${value}\n`);
      console.error(`NATIVE_SDK_SELECTED mode=${selected.mode} artifact=${selected.artifact} version=${selected.version}`);
    } else if (command === 'receive-candidate' && target && outdir && !extra.length) {
      const received = await receiveCandidate(target, outdir);
      process.stdout.write(`digest=${received.digest}\n`);
    } else if (command === 'publish' && target && outdir && !extra.length) {
      await publish(target, outdir);
    } else {
      throw new Error('usage: persist_native_sdk.mjs select TARGET | receive-candidate TARGET DEST | publish TARGET OUTDIR');
    }
  } catch (error) { console.error(error.stack || String(error)); process.exitCode = 1; }
}
