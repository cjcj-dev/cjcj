// Port of cangjie-build/src/cangjie_build/config.py.

import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import {ConfigError} from './errors.mjs';
import {getBuildTarget} from './build-target.mjs';
import {resolveSources,nativeSourceSelection} from '../../ci/bootstrap/native-source-selection.mjs';

export const VALID_BUILD_TYPES = Object.freeze(['release', 'debug', 'relwithdebinfo']);
export const DEFAULT_BUILD_TYPE = 'relwithdebinfo';
export const REPO_NAMES = Object.freeze(['compiler', 'runtime', 'tools', 'stdx', 'llvm', 'cjpm']);

const SEMVER_RE = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
const FALLBACK_VERSION = '0.0.0-dev';
const REPO_DEFAULTS = Object.freeze({
  cjpm: ['https://github.com/cjcj-dev/cangjie-tools.git', 'cjpm-source'],
  llvm: ['https://github.com/cjcj-dev/cjcj-llvm.git', 'cangjie_compiler/third_party/llvm-project'],
  compiler: ['https://gitcode.com/Cangjie/cangjie_compiler.git', 'cangjie_compiler'],
  runtime: ['https://gitcode.com/Cangjie/cangjie_runtime.git', 'cangjie_runtime'],
  tools: ['https://gitcode.com/Cangjie/cangjie_tools.git', 'cangjie_tools'],
  stdx: ['https://gitcode.com/Cangjie/cangjie_stdx.git', 'cangjie_stdx'],
});

export function normalizeCangjieVersion(raw) {
  let candidate = String(raw ?? '').trim();
  if (/^[vV]/.test(candidate)) candidate = candidate.slice(1);
  return SEMVER_RE.test(candidate) ? candidate : FALLBACK_VERSION;
}

function absolute(input) {
  const value = String(input);
  const expanded = value === '~' ? os.homedir() : value.startsWith('~/') ? path.join(os.homedir(), value.slice(2)) : value;
  return path.resolve(expanded);
}

// Ordinary workspace source options, not an identity receipt. Default pins are
// deliberately not saved: a changed default must still reject an old checkout.
const SOURCE_SELECTION = '.source-selection.json';
function validateSourceSelection(selection) {
  if (!selection || typeof selection !== 'object' || Array.isArray(selection)) throw new ConfigError('invalid source selection');
  for (const [name, options] of Object.entries(selection)) {
    if (!REPO_NAMES.includes(name) || !options || typeof options !== 'object' || Array.isArray(options)) throw new ConfigError('invalid source selection repo');
    for (const [key, value] of Object.entries(options)) {
      if (!['url', 'tag'].includes(key) || typeof value !== 'string') throw new ConfigError(`invalid source selection ${name}.${key}`);
      if (!value.trim()) throw new ConfigError(`empty ${name} ${key}`);
      // Handoff intentionally excludes credential-bearing Git config. Source
      // options must not reintroduce credentials into its archived workspace.
      if (key === 'url' && /^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
        let url;
        try { url = new URL(value); } catch { throw new ConfigError(`invalid source URL for ${name}`); }
        if (url.password || (url.protocol !== 'ssh:' && url.username) || url.search || url.hash) throw new ConfigError('source URL must not contain credentials/query/fragment; use Git credential configuration');
      }
    }
  }
  return selection;
}
function readSourceSelection(workspace) {
  const file = path.join(workspace, SOURCE_SELECTION);
  if (!fs.existsSync(file)) return {};
  try { return validateSourceSelection(JSON.parse(fs.readFileSync(file, 'utf8'))); }
  catch (error) { throw new ConfigError(`invalid ${file}: ${error.message}`); }
}
export function saveSourceSelection(config) {
  if (process.env.CANGJIE_BUILD_DRY_RUN === '1') return;
  const file = path.join(config.workspace, SOURCE_SELECTION);
  fs.writeFileSync(`${file}.tmp`, `${JSON.stringify(config.sourceSelection, null, 2)}\n`);
  fs.renameSync(`${file}.tmp`, file);
}
export function resolveOfficialSdkRoot(value = process.env.CJCJ_OFFICIAL_SDK_ROOT ?? process.env.CJCJ_SRCBUILD_HOST_SDK) {
  if (value === undefined || value === null) return null;
  if (!String(value).trim()) throw new ConfigError('officialSdkRoot: expected a nonempty path');
  return absolute(value);
}

export function makeRepos({globalTag, overrides = {}} = {}) {
  if (globalTag !== undefined && !String(globalTag).trim()) throw new ConfigError('empty global tag');
  const pins = Object.fromEntries((fs.readFileSync(new URL('../../ci/runtime_pin.env', import.meta.url), 'utf8')+'\n'+fs.readFileSync(new URL('../../ci/source_pin.env', import.meta.url), 'utf8')+'\n'+fs.readFileSync(new URL('../../ci/cjpm_pin.env', import.meta.url),'utf8'))
    .split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => {
      const separator = line.indexOf('=');
      if (separator < 1) throw new ConfigError(`invalid source pin line: ${line}`);
      return [line.slice(0, separator), line.slice(separator + 1)];
    }));
  pins.CJPM_REF=pins.CJPM_FORK_REF;pins.CJPM_SRC_URL=pins.CJPM_FORK_URL;
  const pair=process.env.CJCJ_NATIVE_LLVM_REF||process.env.CJCJ_NATIVE_RUNTIME_REF
    ? {llvm:process.env.CJCJ_NATIVE_LLVM_REF,runtime:process.env.CJCJ_NATIVE_RUNTIME_REF}:null;
  if(pair&&![pair.llvm,pair.runtime].every(value=>/^[a-f0-9]{40}$/.test(value??'')))throw new ConfigError('NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED');
  if(process.env.CJCJ_NATIVE_RUNTIME_INSTALL&&!pair)throw new ConfigError('NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED');
  const native=nativeSourceSelection(process.env,pair).selection;
  pins.LLVM_REF=native.llvm.commit;pins.LLVM_SRC_URL=native.llvm.repository;
  if(pair){pins.RUNTIME_REF=native.runtime.commit;pins.RUNTIME_SRC_URL=native.runtime.repository;}
  const repos = {};
  for (const name of REPO_NAMES) {
    const [defaultUrl, dirName] = REPO_DEFAULTS[name];
    const override = overrides[name] ?? {};
    if(pair&&['llvm','runtime'].includes(name)&&((override.tag??globalTag??native[name].commit)!==native[name].commit||(override.url??native[name].repository)!==native[name].repository))throw new ConfigError('NATIVE_COMPONENT_SOURCE_CONFLICT '+name);
    const prefix = name.toUpperCase();
    const pinnedRef = pins[`${prefix}_REF`];
    if (!/^[0-9a-f]{40}$/.test(pinnedRef ?? '')) throw new ConfigError(`invalid ${prefix}_REF`);
    for (const key of ['url', 'tag']) {
      if (override[key] !== undefined && !String(override[key]).trim()) throw new ConfigError(`empty ${name} ${key}`);
    }
    repos[name] = Object.freeze({
      name,
      url: override.url ?? pins[`${prefix}_SRC_URL`] ?? defaultUrl,
      tag: override.tag ?? globalTag ?? pinnedRef,
      dirName,
    });
  }
  // Public fetch/build and bootstrap share the source resolver. Tags remain
  // public fetch options here; gitInput records their actual commits once the
  // normal fetch has materialized them.
  const resolved=resolveSources(Object.fromEntries(Object.entries(repos).map(([name,row])=>[name,{repository:row.url,commit:row.tag}])),{},
    {allowUnresolved:['runtime']});
  for(const [name,row]of Object.entries(resolved))repos[name]=Object.freeze({...repos[name],url:row.repository,tag:row.commit});
  return Object.freeze(repos);
}

export function buildConfig({
  workspace,
  buildRoot,
  officialSdkRoot = process.env.CJCJ_OFFICIAL_SDK_ROOT ?? process.env.CJCJ_SRCBUILD_HOST_SDK,
  consumerSdk = process.env.CJCJ_SRCBUILD_CONSUMER_SDK,
  targetKey = 'linux-x64',
  buildType = DEFAULT_BUILD_TYPE,
  cangjieVersion,
  stdxVersion = 1,
  stdxProfile = 'full',
  stdxBuildMode = 'clean',
  toolsBuildMode = 'clean',
  toolsBuildSet = 'all',
  toolsDependencies = process.env.CJCJ_NATIVE_TOOL_DEPENDENCIES,
  toolsPhase = 'all',
  jobs,
  toolsPackageJobs = 4,
  globalTag,
  repoOverrides,
  useSavedSources = true,
} = {}) {
  if (!['full','sdk-tools'].includes(stdxProfile)) throw new ConfigError('invalid stdx profile: '+stdxProfile);
  if (!['all','build','install'].includes(toolsPhase)) throw new ConfigError('invalid tools phase: '+toolsPhase);
  for (const [key,value] of [['jobs',jobs],['tools-package-jobs',toolsPackageJobs]]) {
    if(value!==undefined&&(!/^[1-9][0-9]*$/.test(String(value))||!Number.isSafeInteger(Number(value)))) throw new ConfigError('invalid '+key+': '+value);
  }
  if(Number(toolsPackageJobs)>4)throw new ConfigError('tools-package-jobs exceeds the four heavy C2 package limit');
  const toolNames=['cjpm','cjfmt','hle','lsp','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat'];
  const selectedTools=String(toolsBuildSet).split(',');
  if(toolsBuildSet!=='all'&&(!selectedTools.every(name=>toolNames.includes(name))||new Set(selectedTools).size!==selectedTools.length))
    throw new ConfigError('invalid tools build set: '+toolsBuildSet);
  if (!['clean','incremental'].includes(toolsBuildMode)) throw new ConfigError('invalid tools build mode: '+toolsBuildMode);
  if (!['clean','incremental'].includes(stdxBuildMode)) throw new ConfigError('invalid stdx build mode: '+stdxBuildMode);
  if (!VALID_BUILD_TYPES.includes(buildType)) {
    throw new ConfigError(`invalid build_type '${buildType}'; valid: ${VALID_BUILD_TYPES.join(', ')}`);
  }
  if (officialSdkRoot !== undefined && officialSdkRoot !== null && !String(officialSdkRoot).trim()) {
    throw new ConfigError('officialSdkRoot: expected a nonempty path');
  }
  const target = getBuildTarget(targetKey);
  const workspacePath = absolute(workspace || process.env.CANGJIE_WORKSPACE || path.join(process.cwd(), 'workspace'));
  const buildRootPath = absolute(buildRoot || process.env.CANGJIE_BUILD_ROOT || path.join(process.cwd(), 'buildtools'));
  const rawVersion = cangjieVersion || process.env.CANGJIE_VERSION || globalTag || '';
  const sourceSelection = useSavedSources ? readSourceSelection(workspacePath) : {};
  for (const name of REPO_NAMES) {
    const selected = {...(sourceSelection[name] ?? {})};
    if (globalTag !== undefined) selected.tag = globalTag;
    for (const [key, value] of Object.entries(repoOverrides?.[name] ?? {})) {
      if (['url', 'tag'].includes(key) && value !== undefined && value !== null) selected[key] = value;
    }
    if (Object.keys(selected).length) sourceSelection[name] = selected;
  }
  validateSourceSelection(sourceSelection);
  const repos = makeRepos({globalTag, overrides: sourceSelection});

  const config = {
    workspace: workspacePath,
    buildRoot: buildRootPath,
    target,
    buildType,
    cangjieVersion: normalizeCangjieVersion(rawVersion),
    stdxVersion: Number(stdxVersion),
    stdxProfile,
    stdxBuildMode,
    toolsBuildMode,
    toolsBuildSet,
    toolsDependencies: toolsDependencies ? absolute(toolsDependencies) : null,
    toolsPhase,
    jobs: jobs===undefined?undefined:Number(jobs),
    toolsPackageJobs:Number(toolsPackageJobs),
    repos,
    sourceSelection,
    softwareDir: path.join(workspacePath, 'software'),
    consumerSdk: consumerSdk ? absolute(consumerSdk) : null,
    nativeRuntime: process.env.CJCJ_NATIVE_RUNTIME_INSTALL?{install:absolute(process.env.CJCJ_NATIVE_RUNTIME_INSTALL),
      sourceRoot:process.env.CJCJ_NATIVE_RUNTIME_SOURCE,llvmCommit:repos.llvm.tag,runtimeCommit:repos.runtime.tag,hostVersion:process.env.CJCJ_NATIVE_HOST_VERSION}:null,
    sources: Object.freeze(Object.fromEntries(Object.entries(repos).map(([name,row])=>[name,Object.freeze({repository:row.url,commit:row.tag})]))),
    officialSdkRoot: resolveOfficialSdkRoot(officialSdkRoot),
    crossBuildType: target.spec.crossCompile ? 'release' : buildType,
    repo(name) {
      if (!REPO_NAMES.includes(name)) throw new ConfigError(`unknown repo '${name}'`);
      return repos[name];
    },
    repoPath(name) {
      return path.join(workspacePath, this.repo(name).dirName);
    },
  };
  return Object.freeze(config);
}

export function withBuildType(config, buildType) {
  if (!VALID_BUILD_TYPES.includes(buildType)) throw new ConfigError(`invalid build_type '${buildType}'`);
  return buildConfig({
    workspace: config.workspace,
    buildRoot: config.buildRoot,
    targetKey: config.target.spec.key,
    buildType,
    cangjieVersion: config.cangjieVersion,
    stdxVersion: config.stdxVersion,
    stdxProfile: config.stdxProfile,
    stdxBuildMode: config.stdxBuildMode,
    toolsBuildMode: config.toolsBuildMode,
    toolsBuildSet: config.toolsBuildSet,
    toolsDependencies: config.toolsDependencies,
    toolsPhase: config.toolsPhase,
    jobs: config.jobs,
    toolsPackageJobs: config.toolsPackageJobs,
    officialSdkRoot: config.officialSdkRoot,
    consumerSdk: config.consumerSdk,
    repoOverrides: config.sourceSelection,
  });
}
