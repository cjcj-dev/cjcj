// Ordinary producer facts, like tool-build-inputs at SDK 117e6b5. These are
// observations of one build/install, not a declaration that a SDK is complete.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {BuildError} from '../lib/errors.mjs';

export const STDX_BUILD_INPUTS = 'share/cjcj/build-inputs/stdx.json';
const dry = () => process.env.CANGJIE_BUILD_DRY_RUN === '1';
const relative = (root, file) => path.relative(root, file).split(path.sep).join('/');
const fail = message => { throw new BuildError('stdx.inputs', message); };
function atomicJson(file, value) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  const temporary = file + '.tmp-' + process.pid;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n');
  fs.renameSync(temporary, file);
}
function invalidate(file) {
  // Keep each old fact beside its source. Installation and workspace may be
  // on different filesystems; rename must stay atomic on the source device.
  const previous = file + '.previous-' + Date.now();
  fs.mkdirSync(path.dirname(previous), {recursive: true});
  try { fs.renameSync(file, previous); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
function contained(root, file) {
  const rel = path.relative(root, file);
  if (!rel || rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel))
    fail(`path outside installation: ${file}`);
  return relative(root, file);
}
function sourceState(config) {
  const root = config.repoPath('stdx');
  const git = args => execFileSync('git', ['-C', root, ...args], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).trimEnd();
  if (fs.realpathSync(git(['rev-parse', '--show-toplevel'])) !== fs.realpathSync(root))
    fail('stdx source must be its own Git checkout');
  const commit = git(['rev-parse', '--verify', 'HEAD^{commit}']);
  const tree = git(['rev-parse', '--verify', 'HEAD^{tree}']);
  const origin = spawnSync('git', ['-C', root, 'remote', 'get-url', 'origin'], {encoding: 'utf8'});
  if (origin.status !== 0 && origin.status !== 2) fail('cannot read stdx origin');
  const explicit = config.sourceSelection?.stdx;
  let repository = origin.status === 0 ? origin.stdout.trimEnd() : null;
  let repositorySource = 'origin';
  if (!repository) {
    // Managed object checkouts legitimately omit remote configuration. Only
    // explicit repository + immutable revision options can identify them;
    // config.repo() also contains defaults and must not supply this evidence.
    if (!explicit?.url || !/^[0-9a-f]{40}$/.test(explicit.tag ?? ''))
      fail('originless stdx requires explicit repository and fixed source selection');
    if (explicit.tag !== commit) fail('selected stdx revision differs from actual HEAD');
    repository = explicit.url;
    repositorySource = 'sourceSelection';
  } else if (explicit?.url && explicit.url !== repository) {
    fail('selected stdx repository differs from actual origin');
  }
  const selected = config.repo('stdx').tag;
  if (selected && git(['rev-parse', '--verify', selected + '^{commit}']) !== commit)
    fail('selected stdx revision differs from actual HEAD');
  if (!/^[0-9a-f]{40}$/.test(commit) || !repository) fail('unresolved stdx source');
  return {status: 'resolved', repository, repositorySource, commit, tree,
    checkout: fs.realpathSync(root)};
}
function configuration(directory) {
  const text = fs.readFileSync(path.join(directory, 'CMakeCache.txt'), 'utf8');
  const values = Object.fromEntries(text.split(/\r?\n/)
    .filter(line => /^[^/#][^:]*:[^=]+=/.test(line))
    .map(line => [line.slice(0, line.indexOf(':')), line.slice(line.indexOf('=') + 1)]));
  return {values};
}
export function beginStdxBuild(config, {directory, installRoot, prefix, argv, installArgv, environment}) {
  if (dry()) return null;
  const record = path.join(config.workspace, 'build/stdx/build-inputs.json');
  invalidate(record);
  // Remove only this producer's prior facts; preserve them and the old bytes
  // as evidence. A failed attempt cannot leave a current successful row.
  invalidate(path.join(installRoot, STDX_BUILD_INPUTS));
  const source = sourceState(config);
  const env = Object.fromEntries(['CC', 'CXX', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'PATH',
    'CANGJIE_HOME', 'CANGJIE_STDX_PATH', 'STDX_HOST_CANGJIE_HOME', 'LD_LIBRARY_PATH',
    'DYLD_LIBRARY_PATH', 'CANGJIE_BUILD_JOBS', 'CMAKE_BUILD_PARALLEL_LEVEL', 'MAKEFLAGS',
    'CJC_HEAP_SIZE', 'CJ_HEAP_SIZE', 'CANGJIE_HEAP_SIZE']
    .filter(key => environment[key] != null).map(key => [key, String(environment[key])]));
  return {record, directory, installRoot, prefix, source, installArgv,
    build: {directory: relative(config.repoPath('stdx'), directory), argv,
      platform: config.target.spec.llvmPlatform, requestedProfile: config.stdxProfile ?? 'full',
      buildType: config.target.spec.crossCompile ? config.crossBuildType : config.buildType,
      mode: config.stdxBuildMode ?? 'clean', environment: env}};
}

export function prepareStdxInstall(attempt) {
  if (!attempt) return;
  // build.py install iterates every configured build directory. Reject an
  // unrelated cached directory rather than silently omitting its installation.
  const parent = path.dirname(attempt.directory);
  for (const entry of fs.readdirSync(parent, {withFileTypes: true})) {
    const directory = path.join(parent, entry.name);
    if (entry.isDirectory() && directory !== attempt.directory &&
        fs.existsSync(path.join(directory, 'CMakeCache.txt')))
      fail(`additional native install build directory: ${directory}`);
  }
  invalidate(path.join(attempt.directory, 'install_manifest.txt'));
}

export function finishStdxBuild(config, attempt) {
  if (!attempt) return;
  const cache = configuration(attempt.directory);
  const limited = attempt.build.requestedProfile === 'sdk-tools';
  const expected = {CANGJIE_BUILD_WITHOUT_CHIR: limited ? 'ON' : 'OFF',
    CANGJIE_BUILD_WITHOUT_SYNTAX: limited ? 'ON' : 'OFF',
    CANGJIE_BUILD_WITHOUT_EFFECT_HANDLERS: limited ? 'ON' : 'OFF',
    CANGJIE_BUILD_WITHOUT_PLUGIN: 'OFF', CANGJIE_BUILD_WITHOUT_ASPECT_CJ: 'OFF'};
  for (const [key, value] of Object.entries(expected)) {
    if (cache.values[key] !== value) fail(`effective configuration mismatch: ${key}=${cache.values[key]}, requested ${value}`);
  }
  if ((cache.values.BUILD_GCC_TOOLCHAIN ?? '') !== (config.stdxGccToolchain ?? ''))
    fail('effective configuration mismatch: BUILD_GCC_TOOLCHAIN differs from selected native GCC toolchain');
  if (path.resolve(cache.values.CMAKE_HOME_DIRECTORY) !== path.resolve(config.repoPath('stdx')))
    fail('CMake source directory differs from selected stdx source');
  if (limited && path.resolve(cache.values.CMAKE_INSTALL_PREFIX) !== path.resolve(attempt.prefix))
    fail('subset native install prefix differs from recorded installation');
  attempt.build = {...attempt.build, rc: 0, configuration: cache};
  atomicJson(attempt.record, {component: 'stdx', source: attempt.source, build: attempt.build});
}

export function finishStdxInstall(config, attempt) {
  if (!attempt) return;
  if (attempt.build.rc !== 0) fail('stdx build did not finish');
  const manifestFile = path.join(attempt.directory, 'install_manifest.txt');
  const text = fs.readFileSync(manifestFile, 'utf8');
  const installed = [...new Set(text.split(/\r?\n/).filter(Boolean).map(file => path.resolve(file)))].sort();
  if (!installed.length) fail('empty native install manifest');
  const artifacts = installed.map(file => {
    const name = contained(attempt.installRoot, file);
    contained(attempt.prefix, file);
    contained(fs.realpathSync(attempt.installRoot), fs.realpathSync(file));
    const stat = fs.statSync(file);
    if (!stat.isFile()) fail(`installed product is not a file: ${file}`);
    return {path: name, size: stat.size,
      ...(fs.lstatSync(file).isSymbolicLink() ? {link: fs.readlinkSync(file)} : {})};
  });
  const facts = {component: 'stdx', source: attempt.source, build: attempt.build,
    install: {argv: attempt.installArgv, rc: 0, prefix: relative(attempt.installRoot, attempt.prefix) || '.',
      manifest: {path: relative(config.repoPath('stdx'), manifestFile)}}, artifacts};
  atomicJson(attempt.record, facts);
  atomicJson(path.join(attempt.installRoot, STDX_BUILD_INPUTS), facts);
}
