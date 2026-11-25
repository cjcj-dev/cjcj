#!/usr/bin/env node
// Source jobs retain absolute SDK bindings and verify the producer before use.
// Like bootstrap_store.acquire, nothing is consumable until its manifest checks.
import fs from 'node:fs/promises';
import {verifyNativeToolHandoff} from '../../../../ci/bootstrap/native-tool-input.mjs';
import {readHleDependencies} from '../../../../ci/bootstrap/hle-input.mjs';
import {resolveRuntimeSource} from '../../../../ci/runtime-pin.mjs';
import {createReadStream} from 'node:fs';
import crypto from 'node:crypto';
import {stageSdkHandoff} from './stage-sdk-handoff.mjs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {checkoutExactSource} from '../../../lib/git.mjs';
import {VERSION_SOURCE, applyCangjieVersion, injectedCangjieVersion, injectCangjieVersion} from './steps/inject-version-lib.mjs';

const [mode, phase, directory] = process.argv.slice(2);
if (!['pack', 'restore'].includes(mode) || !/^[a-z0-9-]+$/.test(phase || '') || !directory) {
  throw new Error('usage: job-handoff.mjs pack|restore PHASE DIRECTORY');
}
const required = name => {
  if (!process.env[name]) throw new Error(`missing ${name}`);
  return process.env[name];
};
const root = path.resolve(required('GITHUB_WORKSPACE'));
const identity = {
  version: 1, phase, target: required('CJCJ_SRCBUILD_TARGET'),
  commit: required('GITHUB_SHA'), run: required('GITHUB_RUN_ID'),
  workspace: root,
};
const dir = path.resolve(directory);
const archive = path.join(dir, 'payload.tar');
const manifest = path.join(dir, 'manifest.json');
const hash = async file => {
  const h = crypto.createHash('sha256');
  for await (const chunk of createReadStream(file)) h.update(chunk);
  return h.digest('hex');
};
const tar = args => {
  const result = spawnSync('tar', args, {stdio: 'inherit'});
  if (result.error || result.status !== 0) throw new Error(`handoff tar failed: ${result.error || result.status}`);
};
// Deliberately exclude PATH, cache launchers, tokens and runner command files.
// Every consuming job installs its own dependencies and starts its own cache.
const allowed = name => /^(CJCJ_NATIVE_(CJDB_INSTALL|RUNTIME_INSTALL|RUNTIME_SOURCE|RUNTIME_REF|LLVM_REF|HOST_VERSION)|CJCJ_HLE_DEPENDENCIES|CJCJ_BOOTSTRAP_(?!WORK$|BASE$)[A-Z0-9_]+|CJCJ_SRCBUILD_HOST_SDK|CJCJ_OFFICIAL_SDK_ROOT|CJCJ_TOOLCHAIN|CJCJ_ACTUAL_HOST_TOOLCHAIN|CANGJIE_HOME|CANGJIE_STDX_PATH|LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|G2_IDENTITY|SOURCE_SDK_VERSION|CJCJ_RUNTIME_REF_OVERRIDE|CJCJ_ALLOW_RUNTIME_OVERRIDE|COLOUR_RT_(RUN_ID|RUN_ATTEMPT|ARTIFACT_ID|MANIFEST_SHA256)|RUNTIME_SRC_URL|TOOLS_REF|TOOLS_SRC_URL|STDX_REF|STDX_SRC_URL|CANGJIE_COMPILER_SHA|COMPILER_SRC_URL|LLVM_TUPLE_SUMS_SHA)$/.test(name);
// MinGW is an independent producer. Its overlay must not replace the native
// SDK, injected source version or environment when Windows std joins both arms.
const roots = phase === 'mingw' ? ['.srcbuild/buildtools/llvm-mingw-w64']
  : ['.srcbuild', 'packages', 'runtime_shim', 'cjpm.toml'];
const optional = phase === 'mingw' ? [] : ['cjpm.lock', 'target'];
async function verifyHleHandoff(environment) {
  const file=environment.CJCJ_HLE_DEPENDENCIES;
  if(!file)return; // Phases before the native input selection have no tools input.
  const archived=path.join(root,'.srcbuild')+path.sep;
  for(const item of [file,...Object.values(await readHleDependencies(file)).filter(row=>row?.path).map(row=>row.path)]) {
    if(!path.resolve(item).startsWith(archived)||!(await fs.realpath(item)).startsWith(archived))
      throw new Error('handoff HLE dependency outside archived inputs');
  }
}
async function verifyRuntimeHandoff(environment) {
  const selected = await resolveRuntimeSource(environment);
  const pin = environment.CJCJ_BOOTSTRAP_RUNTIME_PIN;
  if (selected.overrideRef && !pin) throw new Error('handoff candidate runtime pin missing');
  if (pin) {
    const archived = path.join(root, '.srcbuild') + path.sep;
    if (!path.resolve(pin).startsWith(archived) || !String(await fs.realpath(pin)).startsWith(archived)) {
      throw new Error('handoff runtime pin outside archived inputs');
    }
  }
}

// Source never crosses a job boundary. The workflow checkout and every nested
// source checkout under .srcbuild are identified by a 40-hex commit (and the
// nested origin URL); the consuming runner obtains them by pinned Git checkout.
// The payload holds only paths Git does not track: build outputs, installs,
// .cjo/libraries and manifests. A tracked file edited by an earlier build step
// (for example the injected product version) crosses only as a digest-bound
// overlay row; a verbatim tracked file is source and is always rejected.
const SHA40 = /^[0-9a-f]{40}$/;
const git = (cwd, args) => spawnSync('git', ['-C', cwd, ...args], {encoding: 'utf8', maxBuffer: 1 << 30});
const checkoutHead = dir => {
  const r = git(dir, ['rev-parse', '--verify', 'HEAD^{commit}']);
  return r.status === 0 ? r.stdout.trim() : null;
};
const trackedPaths = dir => {
  const r = git(dir, ['ls-files', '-z']);
  if (r.status !== 0) throw new Error(`handoff cannot list tracked source in ${dir}`);
  return new Set(r.stdout.split('\0').filter(Boolean));
};
const modifiedPaths = dir => {
  const r = git(dir, ['diff', '--name-only', '-z', 'HEAD']);
  if (r.status !== 0) throw new Error(`handoff cannot compare checkout with HEAD: ${dir}`);
  return r.stdout.split('\0').filter(Boolean);
};
const posix = rel => rel.split(path.sep).join('/');
async function exists(file) {
  try { await fs.lstat(file); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}
// Edited tracked files: the injected product version crosses as data (the
// value and the digest of the re-derived file), never as Version.cj bytes;
// only build manifests (cjpm.toml/cjpm.lock) may cross as digest-bound bytes.
// Any other edited tracked file is source and fails the pack.
const OVERLAY_MANIFEST = /(^|\/)cjpm\.(toml|lock)$/;
// A new untracked source file inside a tracked directory of the workflow
// checkout (workspace root, packages/, runtime_shim/) is source the pinned
// commit does not have; build outputs live in untracked directories or are not
// source files (objects, .cjo, libraries).
const SOURCE_FILE = /\.(cj|c|cc|cpp|cxx|h|hh|hpp|hxx)$/i;
const trackedDirectories = tracked => {
  const dirs = new Set(['']);
  for (const rel of tracked) for (let dir = path.posix.dirname(rel); dir !== '.' && !dirs.has(dir); dir = path.posix.dirname(dir)) dirs.add(dir);
  return dirs;
};
// A tracked source directory (one holding tracked source files) owns its whole
// subtree: a new untracked source file at any depth below it (e.g. a new
// directory under a package's src/) is source the pinned commit does not have.
const sourceDirectories = tracked => new Set([...tracked].filter(rel => SOURCE_FILE.test(rel))
  .map(rel => path.posix.dirname(rel) === '.' ? '' : path.posix.dirname(rel)));
const underSourceDirectory = (directories, rel) => {
  for (let dir = path.posix.dirname(rel); ; dir = path.posix.dirname(dir)) {
    if (directories.has(dir === '.' ? '' : dir)) return true;
    if (dir === '.' || dir === '/' || dir === '') return false;
  }
};
const headBlob = (dir, rel) => {
  const r = spawnSync('git', ['-C', dir, 'show', `HEAD:${rel}`], {encoding: 'utf8', maxBuffer: 1 << 30});
  if (r.status !== 0) throw new Error(`handoff cannot read pinned ${rel}`);
  return r.stdout;
};
async function payloadPlan(root, entries, excluded) {
  const head = checkoutHead(root);
  if (!head || !SHA40.test(head)) throw new Error('handoff workspace is not a pinned Git checkout');
  const repos = [{prefix: '', tracked: trackedPaths(root)}];
  const workflowDirectories = trackedDirectories(repos[0].tracked), workflowSources = sourceDirectories(repos[0].tracked);
  const checkouts = [], files = [], overlay = new Map(), derivations = [];
  const addOverlay = async (prefix, dir) => {
    for (const rel of modifiedPaths(dir)) {
      const full = prefix ? prefix + '/' + rel : rel;
      // A deleted tracked file would silently reappear from the pinned checkout
      // on the consumer, so the producer's tree could not be reproduced.
      if (!await exists(path.join(root, full))) throw new Error(`handoff deleted tracked source: ${full}`);
      if (full === VERSION_SOURCE) {
        const current = await fs.readFile(path.join(root, full), 'utf8'), version = injectedCangjieVersion(current);
        if (!version || applyCangjieVersion(headBlob(dir, rel), version) !== current)
          throw new Error(`handoff modified tracked source: ${full}`);
        derivations.push({path: full, kind: 'cangjie-version', version, sha256: await hash(path.join(root, full))});
      } else if (OVERLAY_MANIFEST.test(full)) overlay.set(full, await hash(path.join(root, full)));
      else throw new Error(`handoff modified tracked source: ${full}`);
    }
  };
  await addOverlay('', root);
  const tracked = rel => !overlay.has(rel) && repos.some(repo => (repo.prefix === '' || rel.startsWith(repo.prefix + '/'))
    && repo.tracked.has(repo.prefix === '' ? rel : rel.slice(repo.prefix.length + 1)));
  const skip = rel => excluded.some(pattern => pattern.test(rel));
  async function walk(rel) {
    if (skip(rel)) return;
    const file = path.join(root, rel);
    const stat = await fs.lstat(file);
    if (!stat.isDirectory()) {
      if (tracked(rel)) return;
      const owner = repos.filter(repo => repo.prefix === '' || rel.startsWith(repo.prefix + '/'))
        .sort((a, b) => b.prefix.length - a.prefix.length)[0];
      if (owner?.prefix === '' && SOURCE_FILE.test(rel) && (workflowDirectories.has(path.posix.dirname(rel) === '.' ? '' : path.posix.dirname(rel))
        || underSourceDirectory(workflowSources, rel)))
        throw new Error(`handoff untracked source: ${rel}`);
      files.push(rel);
      return;
    }
    if (path.basename(rel) === '.git') return;
    if (rel !== '' && await exists(path.join(file, '.git'))) {
      const commit = checkoutHead(file);
      const url = git(file, ['remote', 'get-url', 'origin']);
      if (!commit || !SHA40.test(commit)) throw new Error(`handoff nested checkout has no commit: ${rel}`);
      if (url.status !== 0 || !url.stdout.trim()) throw new Error(`handoff nested checkout has no origin: ${rel}`);
      checkouts.push({path: rel, commit, url: url.stdout.trim()});
      repos.push({prefix: rel, tracked: trackedPaths(file)});
      await addOverlay(rel, file);
    } else if (rel !== '' && tracked(rel)) {
      return;
    }
    files.push(rel);
    for (const name of (await fs.readdir(file)).sort()) await walk(posix(path.join(rel, name)));
  }
  for (const entry of entries) await walk(entry);
  const kept = files.filter(rel => !tracked(rel));
  const included = new Set(kept);
  return {commit: head, checkouts, files: kept, derivations,
    overlay: [...overlay].filter(([rel]) => included.has(rel)).map(([rel, sha256]) => ({path: rel, sha256}))};
}
// After extraction the checkout must differ from its pinned commits in
// exactly the recorded overlay and derivation paths: overlay bytes match their
// digests, and each derivation is re-applied to the clean pinned file.
async function restoreEdits(root, record) {
  if (!Array.isArray(record.derivations)) throw new Error('handoff manifest lacks derivation rows');
  for (const row of record.overlay) {
    if (!OVERLAY_MANIFEST.test(String(row?.path || ''))) throw new Error(`handoff overlay is not a build manifest: ${row?.path}`);
    if (!await exists(path.join(root, row.path)) || await hash(path.join(root, row.path)) !== row.sha256)
      throw new Error(`handoff overlay bytes mismatch: ${row.path}`);
  }
  for (const row of record.derivations) {
    if (row?.path !== VERSION_SOURCE || row.kind !== 'cangjie-version' || !/^[a-f0-9]{64}$/.test(row.sha256 || ''))
      throw new Error(`handoff derivation row invalid: ${row?.path}`);
    if (row.version !== record.environment?.SOURCE_SDK_VERSION) throw new Error(`handoff derivation version is not SOURCE_SDK_VERSION: ${row.path}`);
    if (modifiedPaths(root).includes(row.path)) throw new Error(`handoff derivation target is not the pinned file: ${row.path}`);
    await injectCangjieVersion(root, row.version);
    if (await hash(path.join(root, row.path)) !== row.sha256) throw new Error(`handoff derivation digest mismatch: ${row.path}`);
  }
  // MinGW is restored over an already restored stage3 workspace and archives
  // only its toolchain tree; the checkout-wide comparison belongs to the
  // phase that owns the workspace.
  if (phase === 'mingw') return;
  const expected = new Set([...record.overlay.map(row => row.path), ...record.derivations.map(row => row.path)]);
  const actual = new Set([...modifiedPaths(root),
    ...record.checkouts.flatMap(row => modifiedPaths(path.join(root, row.path)).map(rel => row.path + '/' + rel))]);
  const differs = [...new Set([...expected, ...actual])].filter(rel => expected.has(rel) !== actual.has(rel)).sort();
  if (differs.length) throw new Error(`handoff restored checkout differs from its manifest: ${differs.join(',')}`);
}
async function assertNoSourcePayload(members, root, checkouts, overlay) {
  if (!Array.isArray(overlay)) throw new Error('handoff manifest lacks overlay rows');
  const edited = new Map(overlay.map(row => [String(row?.path || ''), row?.sha256]));
  for (const [rel, sha256] of edited) {
    // An overlay row must differ from the pinned checkout; equal bytes would be source.
    if (!/^[a-f0-9]{64}$/.test(sha256 || '') || (await exists(path.join(root, rel)) && await hash(path.join(root, rel)) === sha256))
      throw new Error(`handoff payload carries source: ${rel}`);
  }
  const repos = [{prefix: '', tracked: trackedPaths(root)},
    ...checkouts.map(row => ({prefix: row.path, tracked: trackedPaths(path.join(root, row.path))}))];
  for (const raw of members) {
    const rel = raw.replace(/^\.\//, '').replace(/\/$/, '');
    if (!rel) continue;
    if (rel.split('/').includes('.git')) throw new Error(`handoff payload carries source: ${rel}`);
    for (const repo of repos) {
      const inside = repo.prefix === '' ? rel : rel.startsWith(repo.prefix + '/') ? rel.slice(repo.prefix.length + 1) : null;
      if (inside !== null && repo.tracked.has(inside) && !edited.has(rel)) throw new Error(`handoff payload carries source: ${rel}`);
    }
  }
}
async function restoreCheckouts(root, record) {
  if (!SHA40.test(record.commit || '') || checkoutHead(root) !== record.commit)
    throw new Error('handoff checkout SHA mismatch: workspace');
  if (!Array.isArray(record.checkouts)) throw new Error('handoff manifest lacks pinned checkouts');
  for (const row of record.checkouts) {
    const rel = String(row?.path || '');
    if (!rel.startsWith('.srcbuild/') || rel.split('/').includes('..') || path.isAbsolute(rel)
      || !SHA40.test(row.commit || '') || typeof row.url !== 'string' || !row.url)
      throw new Error(`handoff checkout row invalid: ${rel}`);
    const dest = path.join(root, rel);
    if (!await exists(path.join(dest, '.git'))) await checkoutExactSource(row.url, dest, row.commit);
    if (checkoutHead(dest) !== row.commit) throw new Error(`handoff checkout SHA mismatch: ${rel}`);
  }
}
const sdkRel='.srcbuild/workspace/software/cangjie';
const separateSdk=phase==='stage3'&&identity.target==='linux-x64';
async function handoffEntries() {
  const entries = [...roots];
  for (const entry of optional) {
    try { await fs.lstat(path.join(root, entry)); entries.push(entry); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return entries;
}
const handoffExcluded = [/(^|\/)cjcj-src-stage[01]\/target$/, /(^|\/)stage0depot$/,
  ...(separateSdk ? [new RegExp('^' + sdkRel.replace(/[.]/g, '\\.') + '$')] : [])];
if (mode === 'pack') {
  await fs.mkdir(dir, {recursive: true});
  if (dir === root || roots.some(entry => dir.startsWith(path.join(root, entry) + path.sep))) {
    throw new Error('handoff output must be outside archived trees');
  }
  const environment = phase === 'mingw' ? {}
    : Object.fromEntries(Object.entries(process.env).filter(([key]) => allowed(key)));
  if (phase !== 'mingw') { await verifyRuntimeHandoff(environment); await verifyHleHandoff(environment); await verifyNativeToolHandoff(root); }
  for (const [key, value] of Object.entries(environment)) {
    if (/[\r\n]/.test(value)) throw new Error(`multiline handoff environment: ${key}`);
  }
  const entries = await handoffEntries();
  // tar preserves modes and links that upload-artifact's zip cannot preserve.
  // A checkout copied by bootstrap may contain Git's credential-bearing config;
  // retain its object identity, never that config or Actions command files.
  const sdkSha256=separateSdk?await stageSdkHandoff('pack',path.join(root,sdkRel),dir):undefined;
  const plan = await payloadPlan(root, entries, handoffExcluded);
  if (plan.commit !== identity.commit) throw new Error('handoff checkout SHA mismatch: workspace');
  for (const row of plan.derivations)
    if (row.version !== environment.SOURCE_SDK_VERSION) throw new Error(`handoff derivation version is not SOURCE_SDK_VERSION: ${row.path}`);
  const list = path.join(dir, 'payload.list');
  await fs.writeFile(list, plan.files.map(rel => rel + '\0').join(''));
  try { tar(['-cf', archive, '--null', '--no-recursion', '-C', root, '-T', list]); }
  finally { await fs.rm(list, {force: true}); }
  const record = {...identity, environment, entries, sourcePolicy: 'pinned-git-checkout', checkouts: plan.checkouts, overlay: plan.overlay,
    derivations: plan.derivations, sdkSha256, sha256: await hash(archive)};
  await fs.writeFile(manifest, `${JSON.stringify(record, null, 2)}\n`);
  console.log(`BOOTSTRAP_HANDOFF phase=${phase} sha256=${record.sha256}`);
} else {
  const record = JSON.parse(await fs.readFile(manifest, 'utf8'));
  for (const [key, value] of Object.entries(identity)) {
    if (record[key] !== value) throw new Error(`handoff identity mismatch: ${key}`);
  }
  if (!/^[a-f0-9]{64}$/.test(record.sha256 || '') || await hash(archive) !== record.sha256) {
    throw new Error('handoff payload SHA256 mismatch');
  }
  if (!record.environment || Object.entries(record.environment).some(([key, value]) =>
    !allowed(key) || typeof value !== 'string' || /[\r\n]/.test(value))) {
    throw new Error('invalid handoff environment');
  }
  // The artifact is selected by same-run target/phase name; the identity above
  // also rejects accidental cross-target or stale-run selection before unpack.
  if (phase !== 'mingw') await resolveRuntimeSource(record.environment, null);
  if(separateSdk&&(!record.sdkSha256||record.sdkSha256!==(await fs.readFile(path.join(dir,'stage3-sdk.tar.sha256'),'utf8')).trim()))throw Error('STAGE_SDK_HANDOFF_HASH');
  if (record.sourcePolicy !== 'pinned-git-checkout') throw new Error('handoff manifest lacks pinned checkout policy');
  await restoreCheckouts(root, record);
  const listed = spawnSync('tar', ['-tf', archive], {encoding: 'utf8', maxBuffer: 1 << 30});
  if (listed.error || listed.status !== 0) throw new Error('handoff payload listing failed');
  await assertNoSourcePayload(listed.stdout.split('\n').filter(Boolean), root, record.checkouts, record.overlay);
  tar(['-xf', archive, '-C', root]);
  await restoreEdits(root, record);
  // The restored workspace obeys the pack rule too: an untracked source file the
  // consumer already held beside or below tracked sources (not in the archive,
  // which pack and assertNoSourcePayload already police) is source the pinned
  // commits do not have. Generated sources in untracked build trees and objects pass.
  if (phase !== 'mingw') await payloadPlan(root, await handoffEntries(), handoffExcluded);
  if(separateSdk)await stageSdkHandoff('restore',path.join(root,sdkRel),dir);
  if (phase !== 'mingw') { await verifyRuntimeHandoff(record.environment); await verifyHleHandoff(record.environment); await verifyNativeToolHandoff(root); }
  await fs.appendFile(required('GITHUB_ENV'), Object.entries(record.environment)
    .map(([key, value]) => `${key}=${value}\n`).join(''));
  const sdk = record.environment.CANGJIE_HOME;
  if (sdk) await fs.appendFile(required('GITHUB_PATH'), `${sdk}/bin\n${sdk}/tools/bin\n`);
  console.log(`BOOTSTRAP_VERIFIED handoff/${phase} ${record.sha256}`);
}
