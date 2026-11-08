#!/usr/bin/env node
// Source jobs retain absolute SDK bindings and verify the producer before use.
// Like bootstrap_store.acquire, nothing is consumable until its manifest checks.
import fs from 'node:fs/promises';
import {verifyNativeToolHandoff} from '../bootstrap/native-tool-input.mjs';
import {readHleDependencies} from '../bootstrap/hle-input.mjs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {buildConfig} from '../../build/lib/config.mjs';
import {run as fetchSources} from '../../build/srcbuild/stages/fetch.mjs';
import {readNativeToolDependencies} from '../../build/srcbuild/native-tool-dependencies.mjs';
import {injectCangjieVersion} from './steps/inject-version-lib.mjs';
import {createReadStream} from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

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
  version: 2, phase, target: required('CJCJ_SRCBUILD_TARGET'),
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
const allowed = name => /^(CJCJ_NATIVE_(CJDB_INSTALL|TOOL_DEPENDENCIES|RUNTIME_INSTALL|RUNTIME_SOURCE|RUNTIME_REF|LLVM_REF|HOST_VERSION)|CJCJ_SDK_TARGETS|CJCJ_SDK_INPUTS|CJCJ_HLE_DEPENDENCIES|CJCJ_BOOTSTRAP_[A-Z0-9_]+|CJCJ_SRCBUILD_(HOST_SDK|BOOTSTRAP_SDK)|CJCJ_TOOLCHAIN|CJCJ_ACTUAL_HOST_TOOLCHAIN|CANGJIE_HOME|CANGJIE_STDX_PATH|LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|G2_IDENTITY|G2_CAMPAIGN_DIR|SOURCE_SDK_VERSION|CJCJ_RUNTIME_REF_OVERRIDE|CJCJ_ALLOW_RUNTIME_OVERRIDE|COLOUR_RT_(RUN_ID|RUN_ATTEMPT|ARTIFACT_ID|MANIFEST_SHA256)|RUNTIME_SRC_URL|TOOLS_REF|TOOLS_SRC_URL|STDX_REF|STDX_SRC_URL|CANGJIE_COMPILER_SHA|CANGJIE_COMPILER_URL|LLVM_TUPLE_SUMS_SHA)$/.test(name);
// MinGW is an independent producer. Its overlay must not replace the native
// SDK, injected source version or environment when Windows std joins both arms.
const roots = phase === 'mingw' ? ['.srcbuild/buildtools/llvm-mingw-w64']
  : ['.srcbuild'];
const optional = phase === 'mingw' ? [] : ['cjpm.lock', 'target'];
const git = (source, args) => {
  const result=spawnSync('git',['-C',source,...args],{encoding:'utf8'});
  if(result.error||result.status!==0)throw Error(`handoff git failed: ${source} ${args.join(' ')} ${result.stderr||result.error}`);
  return result.stdout.trim();
};
const exists = file => fs.lstat(file).then(()=>true,error=>{if(error.code==='ENOENT')return false;throw error;});
// Source locations already belong to the ordinary workspace and SDK configs.
// The existing handoff records only their fixed Git selection. Each new job
// fetches these objects itself; no checkout or Git object travels in payload.tar.
async function selectedSources(environment) {
  const sources=new Map();
  async function add(source,commit) {
    if(!source||!await exists(source))return;
    source=path.resolve(source);
    if(source===root)return; // actions/checkout prepares GITHUB_SHA in every job.
    if(!source.startsWith(path.join(root,'.srcbuild')+path.sep))throw Error('handoff source outside workspace '+source);
    if(git(source,['rev-parse','--show-toplevel'])!==source)throw Error('handoff source is not Git root '+source);
    const head=git(source,['rev-parse','HEAD']);
    if(!/^[a-f0-9]{40}$/.test(head)||commit&&head!==commit)throw Error('handoff source commit '+source);
    const repository=git(source,['remote','get-url','origin']);
    const previous=sources.get(source);
    if(previous&&(previous.commit!==head||previous.repository!==repository))throw Error('handoff source selection changed '+source);
    sources.set(source,{path:source,repository,commit:head});
  }
  if(environment.CJCJ_SDK_INPUTS) {
    const inputs=JSON.parse(await fs.readFile(environment.CJCJ_SDK_INPUTS,'utf8'));
    for(const name of ['compiler','runtime','stdlib','llvm','ast','h1']) {
      const row=inputs[name];if(row)await add(row.repository,row.commit);
    }
  }
  if(environment.CJCJ_SDK_TARGETS) {
    const targets=JSON.parse(await fs.readFile(environment.CJCJ_SDK_TARGETS,'utf8'));
    for(const row of Object.values(targets.repos||{})) {
      if(row.archive)throw Error('handoff source archive forbidden');
      await add(row.root,row.commit);await add(row.checkout,row.commit);
    }
  }
  if(environment.CJCJ_NATIVE_TOOL_DEPENDENCIES)
    for(const row of Object.values(await readNativeToolDependencies(environment.CJCJ_NATIVE_TOOL_DEPENDENCIES,['cjlint'])))
      await add(row.path,row.commit);
  if(process.env.CANGJIE_WORKSPACE) {
    const config=buildConfig({workspace:process.env.CANGJIE_WORKSPACE,targetKey:identity.target,env:{...process.env,...environment}});
    for(const row of Object.values(config.repos))await add(config.repoPath(row.name),row.tag);
  }
  return [...sources.values()];
}
async function restoreSources(sources,environment) {
  if(!Array.isArray(sources))throw Error('handoff fixed sources missing');
  // Official ephemeral jobs alone may fetch. Local/kkk2 callers keep using
  // canonical cjops sync; this receiver cannot become an alternate transport.
  if(sources.length&&process.env.GITHUB_ACTIONS!=='true')throw Error('handoff source fetch requires official Actions runner');
  const pending=new Map(sources.map(row=>[row.path,row]));
  for(const row of sources) {
    if(typeof row.path!=='string'||!row.path.startsWith(path.join(root,'.srcbuild')+path.sep)
      ||path.resolve(row.path)!==row.path||typeof row.repository!=='string'||!/^[a-f0-9]{40}$/.test(row.commit||''))throw Error('handoff fixed source selection');
  }
  while(pending.size) {
    let changed=false;
    for(const [source,row]of pending) {
      if(path.isAbsolute(row.repository)&&pending.has(row.repository))continue;
      if(await exists(source))throw Error('handoff source unexpectedly archived '+source);
      await fs.mkdir(path.dirname(source),{recursive:true});
      if(path.isAbsolute(row.repository)) {
        // Normal SDK writable checkouts share their selected source's objects.
        git(row.repository,['worktree','add','--detach',source,row.commit]);
      } else {
        await fs.mkdir(source);git(source,['init']);
        git(source,['remote','add','origin',row.repository]);
        git(source,['fetch','--depth=1','origin',row.commit]);
        git(source,['checkout','--detach',row.commit]);
      }
      if(git(source,['rev-parse','HEAD'])!==row.commit)throw Error('handoff fetched source commit '+source);
      pending.delete(source);changed=true;
    }
    if(!changed)throw Error('handoff cyclic source locations');
  }
  if(process.env.CANGJIE_WORKSPACE) {
    const config=buildConfig({workspace:process.env.CANGJIE_WORKSPACE,targetKey:identity.target,env:{...process.env,...environment}});
    if(Object.values(config.repos).every(row=>sources.some(source=>source.path===config.repoPath(row.name))))await fetchSources(config);
  }
  if(environment.SOURCE_SDK_VERSION&&await exists(path.join(root,'packages/basic/src/Version.cj')))
    await injectCangjieVersion(root,environment.SOURCE_SDK_VERSION);
}
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
if (mode === 'pack') {
  await fs.mkdir(dir, {recursive: true});
  if (dir === root || roots.some(entry => dir.startsWith(path.join(root, entry) + path.sep))) {
    throw new Error('handoff output must be outside archived trees');
  }
  const environment = phase === 'mingw' ? {}
    : Object.fromEntries(Object.entries(process.env).filter(([key]) => allowed(key)));
  if (phase !== 'mingw') { await verifyRuntimeHandoff(environment); await verifyHleHandoff(environment); await verifyNativeToolHandoff({root,environment}); }
  for (const [key, value] of Object.entries(environment)) {
    if (/[\r\n]/.test(value)) throw new Error(`multiline handoff environment: ${key}`);
  }
  const entries = [...roots];
  if(phase!=='mingw'&&await exists(path.join(root,'runtime_shim')))
    for(const name of await fs.readdir(path.join(root,'runtime_shim')))
      if(/\.(?:o|obj|d)$/.test(name))entries.push('runtime_shim/'+name);
  for (const entry of optional) {
    try { await fs.lstat(path.join(root, entry)); entries.push(entry); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const sources=phase==='mingw'?[]:await selectedSources(environment);
  // Installed SDK scripts/headers remain installation payloads. The selected
  // project checkouts, their build-tree copies and all Git metadata are excluded.
  tar(['-cf', archive, '--exclude=.git', '--exclude=*/.git',
    ...sources.map(row=>'--exclude='+path.relative(root,row.path)),
    '--exclude=*/stage0depot', '-C', root, ...entries]);
  const record = {...identity, environment, entries, sources, sha256: await hash(archive)};
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
  tar(['-xf', archive, '-C', root]);
  if(phase!=='mingw')await restoreSources(record.sources,record.environment);
  if (phase !== 'mingw') { await verifyRuntimeHandoff(record.environment); await verifyHleHandoff(record.environment); await verifyNativeToolHandoff({root,environment:record.environment}); }
  await fs.appendFile(required('GITHUB_ENV'), Object.entries(record.environment)
    .map(([key, value]) => `${key}=${value}\n`).join(''));
  const sdk = record.environment.CANGJIE_HOME;
  if (sdk) await fs.appendFile(required('GITHUB_PATH'), `${sdk}/bin\n${sdk}/tools/bin\n`);
  console.log(`BOOTSTRAP_VERIFIED handoff/${phase} ${record.sha256}`);
}
