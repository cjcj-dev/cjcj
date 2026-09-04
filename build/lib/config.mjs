// Port of cangjie-build/src/cangjie_build/config.py.

import os from 'node:os';
import path from 'node:path';
import {ConfigError} from './errors.mjs';
import {getTarget} from './targets.mjs';

export const VALID_BUILD_TYPES = Object.freeze(['release', 'debug', 'relwithdebinfo']);
export const DEFAULT_BUILD_TYPE = 'relwithdebinfo';
export const REPO_NAMES = Object.freeze(['compiler', 'runtime', 'tools', 'stdx']);

const SEMVER_RE = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
const FALLBACK_VERSION = '0.0.0-dev';
const REPO_DEFAULTS = Object.freeze({
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

export function makeRepos({globalTag, overrides = {}} = {}) {
  const repos = {};
  for (const name of REPO_NAMES) {
    const [defaultUrl, dirName] = REPO_DEFAULTS[name];
    const override = overrides[name] ?? {};
    repos[name] = Object.freeze({
      name,
      url: override.url || defaultUrl,
      tag: override.tag || globalTag || null,
      dirName,
    });
  }
  return Object.freeze(repos);
}

export function buildConfig({
  workspace,
  buildRoot,
  officialSdkRoot,
  targetKey = 'linux-x64',
  buildType = DEFAULT_BUILD_TYPE,
  cangjieVersion,
  stdxVersion = 1,
  globalTag,
  repoOverrides,
} = {}) {
  if (!VALID_BUILD_TYPES.includes(buildType)) {
    throw new ConfigError(`invalid build_type '${buildType}'; valid: ${VALID_BUILD_TYPES.join(', ')}`);
  }
  const target = getTarget(targetKey);
  const workspacePath = absolute(workspace || process.env.CANGJIE_WORKSPACE || path.join(process.cwd(), 'workspace'));
  const buildRootPath = absolute(buildRoot || process.env.CANGJIE_BUILD_ROOT || path.join(process.cwd(), 'buildtools'));
  const rawVersion = cangjieVersion || process.env.CANGJIE_VERSION || globalTag || '';
  const repos = makeRepos({globalTag, overrides: repoOverrides});

  const config = {
    workspace: workspacePath,
    buildRoot: buildRootPath,
    target,
    buildType,
    cangjieVersion: normalizeCangjieVersion(rawVersion),
    stdxVersion: Number(stdxVersion),
    repos,
    softwareDir: path.join(workspacePath, 'software'),
    officialSdkRoot: officialSdkRoot ? absolute(officialSdkRoot) : null,
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
    officialSdkRoot: config.officialSdkRoot,
    repoOverrides: Object.fromEntries(REPO_NAMES.map(name => [name, config.repos[name]])),
  });
}
