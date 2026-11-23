#!/usr/bin/env node
// phase=prepare producer contract. Five native hosts each build, from fixed Git
// sources, the two input sets a later phase=publish consumes:
//   native-runtime-install-<llvm_platform>  paired runtime + boundscheck install
//   native-inputs-<target>                  host SDK + N/R/AST installs + locations.json
// This module is the single source of the host set and assembles the
// native-inputs root on the producing runner. It never invents a component:
// a missing installation fails closed. N/LLVM and AST are built on each host by
// the public in-repo producers and installed here (install-llvm / install-ast);
// no private tools adapter is part of any native input.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {sdkPlatform, stdxChirMembers} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {readHostToolchainPin} from '../../../../ci/host-toolchain-pin.mjs';
import {workflowSourceSelection} from '../srcbuild/source-selection.mjs';
import {baseSdkDownload} from '../../../lib/release-component-provenance.mjs';
import {allTargets, getTarget} from '../../../lib/targets.mjs';

import {prepareHostSdk} from './bootstrap_host_sdk.mjs';
import {load as loadYaml} from '../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {g4SourcePhases} from '../../../../ci/release-gates.mjs';

export const PREPARE_HOSTS = Object.freeze([
  Object.freeze({target: 'linux-x64', llvm_platform: 'linux_x86_64', runner: 'ubuntu-22.04'}),
  Object.freeze({target: 'linux-aarch64', llvm_platform: 'linux_aarch64', runner: 'ubuntu-24.04-arm'}),
  Object.freeze({target: 'windows-x64', llvm_platform: 'windows_x86_64', runner: 'windows-2025'}),
  Object.freeze({target: 'darwin-arm64', llvm_platform: 'darwin_aarch64', runner: 'macos-15'}),
  Object.freeze({target: 'darwin-x64', llvm_platform: 'darwin_x86_64', runner: 'macos-15-intel'}),
]);
export const PROVENANCE_KEYS = Object.freeze(['producer_sha', 'run_id', 'run_attempt', 'native_llvm_ref',
  'native_runtime_ref', 'compiler_ref', 'tools_ref', 'stdx_ref']);
const SHA40 = /^[0-9a-f]{40}$/;
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');

export function prepareHost(target) {
  const host = PREPARE_HOSTS.find(row => row.target === target);
  if (!host) throw new Error(`PREPARE_HOST_UNKNOWN ${target}`);
  return host;
}

function readEnvFile(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split('\n')
    .map(line => line.trim()).filter(line => line && !line.startsWith('#') && line.includes('='))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}

// Every identity is a 40-hex commit or a positive run number; nothing defaults.
export function prepareProvenance(env = process.env, pins = readEnvFile(path.join(repoRoot, 'ci/source_pin.env'))) {
  const record = {
    producer_sha: env.GITHUB_SHA, run_id: env.GITHUB_RUN_ID, run_attempt: env.GITHUB_RUN_ATTEMPT,
    native_llvm_ref: env.CJCJ_NATIVE_LLVM_REF, native_runtime_ref: env.CJCJ_NATIVE_RUNTIME_REF,
    compiler_ref: pins.COMPILER_REF, tools_ref: pins.TOOLS_REF, stdx_ref: pins.STDX_REF,
  };
  for (const key of PROVENANCE_KEYS) {
    const value = String(record[key] ?? '');
    const ok = key === 'run_id' || key === 'run_attempt' ? /^[1-9][0-9]*$/.test(value) : SHA40.test(value);
    if (!ok) throw new Error(`PREPARE_PROVENANCE ${key}`);
  }
  return record;
}

const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function installation(root, name, manifest) {
  const install = path.join(root, name), buildResult = path.join(install, manifest);
  if (!fs.existsSync(buildResult)) throw new Error(`NATIVE_INPUTS_COMPONENT_MISSING ${name}`);
  const facts = JSON.parse(fs.readFileSync(buildResult, 'utf8'));
  return {install: name, buildResult: `${name}/${manifest}`, configuration: facts.configuration ?? null,
    sha256: sha256(buildResult)};
}

// Fixed source identities of one host's N/LLVM + AST build. All three are
// explicit 40-hex commits (LLVM fork, its paired runtime, the compiler that owns
// the AST support target); nothing defaults.
export function componentCommits(env = process.env) {
  const commits = {llvm: env.PREPARE_LLVM_COMMIT, runtime: env.PREPARE_RUNTIME_COMMIT, compiler: env.PREPARE_COMPILER_COMMIT};
  for (const [name, value] of Object.entries(commits))
    if (!SHA40.test(String(value ?? ''))) throw new Error(`PREPARE_COMPONENT_COMMIT ${name}`);
  return commits;
}
function freshComponent(root, name) {
  const install = path.join(root, name);
  if (fs.existsSync(install)) throw new Error(`NATIVE_INPUTS_COMPONENT_EXISTS ${name}`);
  fs.mkdirSync(install, {recursive: true});
  return install;
}
function copyMember(from, rel, install, to = rel) {
  const source = path.join(from, rel);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile() || !fs.statSync(source).size)
    throw new Error(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ${rel}`);
  const destination = path.join(install, to);
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.copyFileSync(source, destination);
  return {sha256: sha256(destination), bytes: fs.statSync(destination).size};
}

// The consumer (ci/bootstrap/sdk-inputs.mjs shapes.llvm) requires the in-process
// library and these executables of the same build in third_party/llvm/bin.
export const PREPARE_LLVM_TOOLS = Object.freeze(['llc', 'llvm-as', 'llvm-dis']);
const SYSTEM_TAR = () => process.platform === 'win32'
  ? path.join(process.env.SystemRoot || process.env.SYSTEMROOT || 'C:\\Windows', 'System32', 'tar.exe') : 'tar';

// Install the in-process LLVM library and its tools built on this host by the
// one LLVM_BUILD_LLVM_DYLIB CMake build of the pinned fork (all five hosts,
// Windows under MSYS2 MINGW64; build_prepare_llvm.mjs) at the location every
// native reader resolves: llvm/third_party/llvm/<llvmDirectory>/<llvmLibrary>,
// llvm/third_party/llvm/bin/<tool> + llvm/BUILD-INPUTS.json.
export const PREPARE_SHIM_OBJECT = 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
export function installLlvm({root, target, from, commits, producer, shimCommit}) {
  if (!SHA40.test(String(shimCommit ?? ''))) throw new Error('PREPARE_COMPONENT_COMMIT shim');
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const install = freshComponent(root, 'llvm');
  const file = `third_party/llvm/${native.llvmDirectory}/${native.llvmLibrary}`;
  const row = copyMember(from, native.llvmLibrary, install, file);
  const tools = {};
  for (const tool of PREPARE_LLVM_TOOLS) {
    const rel = `third_party/llvm/bin/${tool}${native.exe}`;
    tools[rel] = copyMember(from, `bin/${tool}${native.exe}`, install, rel);
    if (native.os !== 'win32') fs.chmodSync(path.join(install, rel), 0o755);
  }
  // The compiler-owned LLVM shim object of this LLVM build (build_prepare_llvm.mjs
  // shim) at the path ci/bootstrap/native-shim-inputs.mjs reads, with its record.
  const shimRecordFile = path.join(from, 'fixed-llc/SHIM-BUILD.json');
  if (!fs.existsSync(shimRecordFile)) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING fixed-llc/SHIM-BUILD.json');
  const shimRecord = JSON.parse(fs.readFileSync(shimRecordFile, 'utf8'));
  const shim = copyMember(from, 'fixed-llc/cjselfhost_llvmshim.o', install, PREPARE_SHIM_OBJECT);
  if (shimRecord.sha256 !== shim.sha256 || shimRecord.bytes !== shim.bytes || !shimRecord.symbols?.length)
    throw new Error('PREPARE_SHIM_BUILD_RECORD');
  // cjdb is the lldb executable of the same CMake build, installed with its
  // liblldb at the tools/bin location of sdk-inputs.mjs shapes.llvm.
  const cjdbFile = `tools/bin/cjdb${native.exe}`;
  const cjdb = copyMember(from, `bin/lldb${native.exe}`, install, cjdbFile);
  if (native.os !== 'win32') fs.chmodSync(path.join(install, cjdbFile), 0o755);
  const lldbDir = path.join(from, 'lldb-lib');
  const lldbNames = fs.existsSync(lldbDir) ? fs.readdirSync(lldbDir).sort() : [];
  if (!lldbNames.length) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-lib');
  const libraries = {};
  for (const name of lldbNames) {
    const rel = `tools/${native.os === 'win32' ? 'bin' : 'lib'}/${name}`;
    libraries[rel] = copyMember(from, `lldb-lib/${name}`, install, rel);
  }
  const facts = {schema: 'cjcj-prepare-llvm-v1', platform, commits: {...commits, shim: shimCommit},
    configuration: {producer, library: file, targets: 'X86;ARM;AArch64', tools: PREPARE_LLVM_TOOLS, projects: 'clang;lldb'},
    llvmLibrary: {file, sha256: row.sha256}, tools,
    nativeShim: {source: {commit: shimCommit, file: 'runtime_shim/cjselfhost_llvmshim.cpp'},
      compiler: {commit: commits.compiler, schema: 'schema/CjoFormat.fbs'}, llvm: {commit: commits.llvm},
      object: {path: PREPARE_SHIM_OBJECT, ...shim}, symbols: shimRecord.symbols,
      configuration: {producer: 'build/sdk/producers/release/build_prepare_llvm.mjs shim', argv: shimRecord.argv}},
    cjdb: {file: cjdbFile, ...cjdb, libraries, configuration: {projects: 'clang;lldb', target: 'lldb'}}};
  fs.writeFileSync(path.join(install, 'BUILD-INPUTS.json'), JSON.stringify(facts, null, 2) + '\n');
  return facts;
}

// Install the ci/build_ast_support.sh output (cangjie-ast-support, std
// support ON) in the shape readInstalledNativeAst consumes after transport.
export function installAst({root, target, from, commits}) {
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const install = freshComponent(root, 'ast');
  const library = `lib/${native.tuple}/libcangjie-ast-support.a`;
  const flatc = `third_party/flatbuffers/bin/flatc${native.exe}`;
  const files = {[library]: copyMember(from, 'libcangjie-ast-support.a', install, library)};
  for (const rel of ['schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h', ...stdxChirMembers, flatc])
    files[rel] = copyMember(from, rel, install);
  const build = {target: 'cangjie-ast-support', configuration: {stdSupport: 'ON', producer: 'ci/build_ast_support.sh'}};
  const facts = {schema: 'cjcj-prepare-ast-v1', platform, commits: {compiler: commits.compiler, llvm: commits.llvm},
    configuration: build.configuration,
    astInstallation: {platform, source: {commit: commits.compiler}, library, files, build}};
  fs.writeFileSync(path.join(install, 'BUILD-INPUTS.json'), JSON.stringify(facts, null, 2) + '\n');
  return facts;
}

// Host SDK: the official archive is the identity the consumers verify
// (select-native-host.mjs -> verifyOfficialSdkIdentity needs the original
// archive name, size and SHA-256), so prepare keeps that file, not a re-tar
// of an installed toolchain. The pair rule is the consumer's nativePair rule:
// an explicit LLVM/runtime pair needs an explicit host; an empty selection uses
// the checked-in pin. Only the pinned identity can be prepared here.
export function prepareHostVersion(target, env = process.env) {
  const platform = prepareHost(target).llvm_platform;
  const pinned = readHostToolchainPin(platform).replace(/^nightly-/, '');
  const requested = env.CJCJ_NATIVE_HOST_VERSION || '';
  if ((env.CJCJ_NATIVE_LLVM_REF || env.CJCJ_NATIVE_RUNTIME_REF) && !requested)
    throw new Error('NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED');
  const version = requested || pinned;
  if (version !== pinned) throw new Error(`PREPARE_HOST_VERSION_UNPINNED ${version} != ${pinned}`);
  return version;
}
function targetKey(platform) {
  const found = allTargets().map(getTarget).find(({spec}) => spec.llvmPlatform === platform);
  if (!found) throw new Error(`PREPARE_HOST_TARGET ${platform}`);
  return found.spec.key;
}
export async function installHost({root, target, env = process.env, prepare = prepareHostSdk}) {
  const host = prepareHost(target), version = prepareHostVersion(target, env);
  const expected = baseSdkDownload(targetKey(host.llvm_platform), version);
  const install = path.join(root, 'host'), archives = path.join(root, 'host-archive');
  for (const name of ['host', 'host-archive', 'HOST-INPUT.json'])
    if (fs.existsSync(path.join(root, name))) throw new Error(`NATIVE_INPUTS_COMPONENT_EXISTS ${name}`);
  const work = path.join(root, '.host-download');
  fs.mkdirSync(work, {recursive: true});
  try {
    const sdk = await prepare(host.llvm_platform, work);
    if (path.basename(sdk.archive) !== expected.archive || sdk.sha256 !== expected.sha256
      || fs.statSync(sdk.archive).size !== expected.size) throw new Error('PREPARE_HOST_ARCHIVE_IDENTITY');
    fs.renameSync(sdk.path, install);
    fs.mkdirSync(archives);
    const archive = path.join(archives, expected.archive);
    if (path.dirname(path.resolve(sdk.archive)) === path.resolve(work)) fs.renameSync(sdk.archive, archive);
    else fs.copyFileSync(sdk.archive, archive);
    if (sha256(archive) !== expected.sha256) throw new Error('PREPARE_HOST_ARCHIVE_IDENTITY');
    const record = {schema: 'cjcj-prepare-host-v1', platform: host.llvm_platform, version, install: 'host',
      archive: {file: `host-archive/${expected.archive}`, sha256: expected.sha256, size: expected.size, url: expected.url}};
    fs.writeFileSync(path.join(root, 'HOST-INPUT.json'), JSON.stringify(record, null, 2) + '\n');
    return record;
  } finally { fs.rmSync(work, {recursive: true, force: true}); }
}
function recordedHost(root, platform, hostVersion) {
  const file = path.join(root, 'HOST-INPUT.json');
  if (!fs.existsSync(file)) throw new Error('NATIVE_INPUTS_COMPONENT_MISSING host');
  const record = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (record.schema !== 'cjcj-prepare-host-v1' || record.platform !== platform || record.install !== 'host')
    throw new Error('PREPARE_HOST_RECORD');
  if (hostVersion !== undefined && hostVersion !== record.version) throw new Error('PREPARE_HOST_VERSION');
  const archive = path.join(root, record.archive?.file || '');
  if (!/^host-archive\/[^/\\]+$/.test(record.archive?.file || '') || !fs.existsSync(archive)
    || fs.statSync(archive).size !== record.archive.size || sha256(archive) !== record.archive.sha256)
    throw new Error('PREPARE_HOST_ARCHIVE_IDENTITY');
  if (!fs.existsSync(path.join(root, 'host'))) throw new Error('NATIVE_INPUTS_COMPONENT_MISSING host');
  return {install: 'host', archive: record.archive.file, version: record.version};
}

// The compiler source of the AST build is the one the consumer job selects:
// its "Resolve actual source selection" step (workflowSourceSelection over the
// same CJCJ_SOURCE_SELECTION) exports CANGJIE_COMPILER_URL/SHA, which the
// consumers' buildConfig then compares the AST facts with.
export function compilerSource(env = process.env) {
  const selected = workflowSourceSelection(env);
  const source = {repository: selected.CANGJIE_COMPILER_URL, commit: selected.CANGJIE_COMPILER_SHA};
  if (!SHA40.test(source.commit || '') || !source.repository) throw new Error('PREPARE_COMPILER_SOURCE');
  return source;
}

// HLE dependency package read by ci/bootstrap/hle-input.mjs configureHleInput and
// build/srcbuild/hle-dependencies.mjs: this runner's own Node executable, the npm
// tree of the pinned tools dtsparser package.json (--ignore-scripts: its
// postinstall download is replaced by the pinned cjbind below) and the public
// cjbind-cangjie release that consumer accepts. That release has no darwin-x64
// asset, so that host fails closed instead of carrying a foreign cjbind: the
// tag commit's build matrix has no darwin-x64 cell and its four assets embed
// four different Cangjie toolchains, none from that commit's own build, so no
// darwin-x64 build can be verified as the same release.
export const HLE_CJBIND = Object.freeze({version: 'v1.1.0-alpha.53.1',
  base: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie/releases/download/v1.1.0-alpha.53.1/',
  assets: Object.freeze({
    linux_x86_64: Object.freeze({name: 'cjbind-linux-x64', size: 90753504, sha256: '71bf15dbd18a343c366a923a5b25766a373af5d1709a59c25ced545ebc88f21e'}),
    linux_aarch64: Object.freeze({name: 'cjbind-linux-arm64', size: 82689672, sha256: '18fee7c8d63722f0eb990a5640d877212b195c5d994d78df29e65434d21bb579'}),
    windows_x86_64: Object.freeze({name: 'cjbind-windows-x64.exe', size: 77087232, sha256: '417c6aac0d2ff448490c2027bbbd619cf09d10b207e1513ebff369d69db9935e'}),
    darwin_aarch64: Object.freeze({name: 'cjbind-darwin-arm64', size: 92136544, sha256: '4da660c010203be14660edb5ee0e76f4a894214ca7a7c383702159d2f9d4005b'}),
  })});
export const HLE_DESCRIPTOR = 'hle/hle-dependencies.json';
export function hleCjbindAsset(platform) {
  const asset = HLE_CJBIND.assets[platform];
  if (!asset) throw new Error(`HLE_CJBIND_UNAVAILABLE ${platform}`);
  return {...asset, version: HLE_CJBIND.version, url: HLE_CJBIND.base + asset.name};
}
export function hleModuleSpecs(parser) {
  const manifest = JSON.parse(fs.readFileSync(path.join(parser, 'package.json'), 'utf8'));
  const rows = Object.entries(manifest.dependencies || {});
  if (!rows.length) throw new Error('HLE_PARSER_DEPENDENCIES');
  return rows.map(([name, wanted]) => ({name, wanted: String(wanted).trim(), version: String(wanted).trim().replace(/^npm:[^@]+@/, '')}));
}
function npmInstall(prefix, specs) {
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const argv = ['install', '--prefix', prefix, '--ignore-scripts', '--no-save', '--no-package-lock', '--no-audit', '--no-fund', ...specs];
  const result = spawnSync(npm, argv, {stdio: 'inherit', shell: process.platform === 'win32'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`HLE_MODULES_INSTALL_RC ${result.status}`);
  return ['npm', ...argv.filter(arg => arg !== prefix && arg !== '--prefix')];
}
async function downloadAsset(url, file) {
  const response = await fetch(url, {redirect: 'follow'});
  if (!response.ok) throw new Error(`HLE_CJBIND_DOWNLOAD ${response.status} ${url}`);
  fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
}
export async function installHle({root, target, parser, node = process.execPath, cjbindFile,
  installModules = npmInstall, download = downloadAsset, asset: pinned}) {
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const asset = pinned ?? hleCjbindAsset(platform), specs = hleModuleSpecs(parser);
  const hle = freshComponent(root, 'hle');
  const nodeRel = `node/node${native.exe}`, cjbindRel = `cjbind/cjbind${native.exe}`;
  fs.mkdirSync(path.join(hle, 'node'));
  fs.copyFileSync(node, path.join(hle, nodeRel));
  const nodeVersion = String(spawnSync(node, ['--version'], {encoding: 'utf8'}).stdout || '').trim();
  if (!/^v\d+\.\d+\.\d+$/.test(nodeVersion)) throw new Error('HLE_NODE_VERSION');
  fs.mkdirSync(path.join(hle, 'cjbind'));
  const cjbind = path.join(hle, cjbindRel);
  if (cjbindFile) fs.copyFileSync(cjbindFile, cjbind); else await download(asset.url, cjbind);
  if (fs.statSync(cjbind).size !== asset.size || sha256(cjbind) !== asset.sha256) throw new Error('HLE_CJBIND_IDENTITY');
  if (native.os !== 'win32') for (const rel of [nodeRel, cjbindRel]) fs.chmodSync(path.join(hle, rel), 0o755);
  const work = path.join(hle, '.modules');
  fs.mkdirSync(work);
  fs.writeFileSync(path.join(work, 'package.json'), '{}\n');
  const command = installModules(work, specs.map(({name, wanted}) => `${name}@${wanted}`));
  if (!fs.existsSync(path.join(work, 'node_modules'))) throw new Error('HLE_MODULES_MISSING');
  fs.renameSync(path.join(work, 'node_modules'), path.join(hle, 'modules'));
  fs.rmSync(work, {recursive: true, force: true});
  // The consumer installs the tree without .bin (its cjbind is the one above).
  fs.rmSync(path.join(hle, 'modules/.bin'), {recursive: true, force: true});
  const packages = {};
  for (const {name, version} of specs) {
    const file = path.join(hle, 'modules', name, 'package.json');
    const actual = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
    if (actual.name !== name || actual.version !== version) throw new Error(`HLE_MODULES_VERSION ${name}`);
    packages[name] = version;
  }
  const descriptor = {schema: 'cjcj-prepare-hle-v1', platform,
    node: {path: nodeRel, version: nodeVersion, source: `prepare runner Node ${nodeVersion} ${process.platform}-${process.arch}`,
      sha256: sha256(path.join(hle, nodeRel))},
    modules: {path: 'modules', version: Object.entries(packages).map(([name, version]) => `${name}@${version}`).join(' '),
      source: `npm registry: ${command.join(' ')}`, packages},
    cjbind: {path: cjbindRel, version: asset.version, source: asset.url, sha256: asset.sha256, size: asset.size}};
  fs.writeFileSync(path.join(root, HLE_DESCRIPTOR), JSON.stringify(descriptor, null, 2) + '\n');
  return descriptor;
}

// Actions artifacts do not keep POSIX modes, so a native-inputs root travels as
// one tar made here; the consumer (ci/bootstrap/native-artifact-archive.mjs)
// requires that single archive and extracts it before any member is executed.
export function packNativeInputs({root, out}) {
  root = path.resolve(root); out = path.resolve(out);
  if (out.startsWith(root + path.sep)) throw new Error('NATIVE_INPUTS_ARCHIVE_INSIDE_ROOT');
  if (fs.existsSync(out)) throw new Error('NATIVE_INPUTS_ARCHIVE_EXISTS');
  const result = spawnSync(SYSTEM_TAR(), ['-cf', path.basename(out), '-C', path.relative(path.dirname(out), root) || '.', '.'],
    {cwd: path.dirname(out), stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`NATIVE_INPUTS_ARCHIVE_RC ${result.status}`);
  return {file: out, sha256: sha256(out), bytes: fs.statSync(out).size};
}

// No native input carries a tools adapter: the retired private
// ts/src/sharedbuild modules are not an input of any host, and a stray
// adapter directory fails closed instead of being forwarded.
export function assembleNativeInputs({root, target, hostVersion, env = process.env, pins}) {
  const host = prepareHost(target);
  const provenance = prepareProvenance(env, pins);
  if (hostVersion !== undefined && !/^[0-9A-Za-z.+-]+$/.test(hostVersion)) throw new Error('PREPARE_HOST_VERSION');
  const selectedHost = recordedHost(root, host.llvm_platform, hostVersion);
  if (fs.existsSync(path.join(root, 'adapter'))) throw new Error('NATIVE_TOOLS_ADAPTER_UNEXPECTED');
  if (!fs.existsSync(path.join(root, HLE_DESCRIPTOR))) throw new Error('NATIVE_INPUTS_COMPONENT_MISSING hle');
  const llvm = installation(root, 'llvm', 'BUILD-INPUTS.json');
  if (!JSON.parse(fs.readFileSync(path.join(root, llvm.buildResult), 'utf8')).nativeShim)
    throw new Error('NATIVE_INPUTS_COMPONENT_MISSING shim');
  const locations = {
    platform: host.llvm_platform,
    host: selectedHost,
    hleDependencies: HLE_DESCRIPTOR,
    installations: {
      llvm,
      runtime: installation(root, 'runtime', 'NATIVE-INPUTS.json'),
      ast: installation(root, 'ast', 'BUILD-INPUTS.json'),
      // The shim object is a member of the same N install (native-shim-inputs.mjs).
      shim: {install: 'llvm'},
    },
    tools: {},
  };
  fs.writeFileSync(path.join(root, 'locations.json'), JSON.stringify(locations, null, 2) + '\n');
  const record = {schema: 'cjcj-prepare-native-inputs-v1', target, llvm_platform: host.llvm_platform, runner: host.runner,
    ...provenance, locations_sha256: sha256(path.join(root, 'locations.json'))};
  fs.writeFileSync(path.join(root, 'PREPARE-PROVENANCE.json'), JSON.stringify(record, null, 2) + '\n');
  return {locations, record};
}

// Static wiring contract of release.yml -> sdk-build.yml -> sdk-build-target.yml
// for phase=prepare: the five hosts, both artifact families, and no route into
// plan/source/package/publish. Returns a list of problems; empty means wired.
export function prepareWorkflowProblems({release, sdkBuild, target}) {
  const problems = [...g4SourcePhases(release).problems];
  const rel = loadYaml(release)?.jobs || {}, sdk = loadYaml(sdkBuild)?.jobs || {}, tgt = loadYaml(target)?.jobs || {};
  const producer = Object.entries(rel).find(([, job]) => job?.with?.mode === 'prepare');
  if (!producer || producer[1].uses !== './.github/workflows/sdk-build.yml') problems.push('release.yml lacks the mode=prepare sdk-build call');
  const call = sdk.prepare;
  if (call?.if !== "inputs.mode == 'prepare'" || call?.uses !== './.github/workflows/sdk-build-target.yml' || call?.with?.prepare_native !== true)
    problems.push('sdk-build.yml prepare does not call sdk-build-target.yml with prepare_native');
  if (!/inputs\.mode != 'prepare'/.test(String(sdk.plan?.if ?? ''))) problems.push('sdk-build.yml plan runs in mode=prepare');
  if (!/inputs\.prepare_native != true/.test(String(tgt.plan?.if ?? ''))) problems.push('sdk-build-target.yml plan runs with prepare_native');
  const job = tgt['prepare-native'];
  if (!job || job.if !== 'inputs.prepare_native') { problems.push('sdk-build-target.yml lacks prepare-native'); return problems; }
  const rows = job.strategy?.matrix?.include || [];
  const key = row => `${row.target}|${row.llvm_platform}|${row.runner}`;
  const want = PREPARE_HOSTS.map(key), got = rows.map(key);
  for (const host of want) if (!got.includes(host)) problems.push(`prepare-native lacks host ${host}`);
  for (const host of got) if (!want.includes(host)) problems.push(`prepare-native has unexpected host ${host}`);
  if (job['runs-on'] !== '${{ matrix.runner }}') problems.push('prepare-native does not run on the native host runner');
  const uploads = (job.steps || []).filter(step => String(step.uses || '').startsWith('actions/upload-artifact@'));
  // Each family travels as the one mode-preserving tar its consumer unpacks.
  for (const [name, file] of [['native-runtime-install-${{ matrix.llvm_platform }}', 'runtime-install.tar'],
    ['native-inputs-${{ matrix.target }}', 'native-inputs.tar']]) {
    const upload = uploads.find(step => step.with?.name === name);
    if (!upload) problems.push(`prepare-native does not upload ${name}`);
    else if (path.posix.basename(String(upload.with.path || '')) !== file) problems.push(`prepare-native uploads ${name} without ${file}`);
  }
  const text = JSON.stringify(job.steps || []);
  for (const program of ['build/sdk/producers/platform_matrix/build_runtime.mjs', 'build/sdk/producers/platform_matrix/native_runtime_package.mjs',
    'build/sdk/producers/release/prepare_native_inputs.mjs install-host', 'build/sdk/producers/release/prepare_native_inputs.mjs assemble',
    'build/sdk/producers/release/prepare_native_inputs.mjs pack', 'build/sdk/producers/release/prepare_native_inputs.mjs install-hle'])
    if (!text.includes(program)) problems.push(`prepare-native does not run ${program}`);
  problems.push(...prepareComponentProblems(job.steps || []));
  // The host is the original official archive; a cjv install (ci/setup_sdk.mjs,
  // Unix-only) re-tarred under a directory locator is not a host identity.
  if (/ci\/setup_sdk\.mjs|host-sdk\.tar/.test(text)) problems.push('prepare-native provisions the host from an installed toolchain');
  if (/deploy-native-tools|sharedbuild|privateRoot/.test(text)) problems.push('prepare-native consumes the retired private tools adapter');
  if (/gh release|softprops\/action-gh-release|ci\/release-publish\.mjs/.test(text)) problems.push('prepare-native publishes');
  return problems;
}

// Per-host N/LLVM and AST producers. A step applies to a host when its `if`
// is empty or a plain runner.os (in)equality that admits the host's OS; every
// host needs its producer markers and the install step in its applicable steps.
export const PREPARE_COMPONENT_STEPS = Object.freeze({
  // One in-process LLVM producer on every host: the static platform_tuples
  // build has no libLLVM-15.dll, so Windows runs the same dylib build.
  llvm: Object.freeze({
    Linux: ['build/sdk/producers/release/build_prepare_llvm.mjs --platform', 'prepare_native_inputs.mjs install-llvm'],
    macOS: ['build/sdk/producers/release/build_prepare_llvm.mjs --platform', 'prepare_native_inputs.mjs install-llvm'],
    Windows: ['build/sdk/producers/release/build_prepare_llvm.mjs --platform', 'prepare_native_inputs.mjs install-llvm'],
  }),
  shim: Object.freeze({
    Linux: ['build/sdk/producers/release/build_prepare_llvm.mjs shim', '--shim-commit'],
    macOS: ['build/sdk/producers/release/build_prepare_llvm.mjs shim', '--shim-commit'],
    Windows: ['build/sdk/producers/release/build_prepare_llvm.mjs shim', '--shim-commit'],
  }),
  hle: Object.freeze({
    Linux: ['prepare_native_inputs.mjs install-hle'],
    macOS: ['prepare_native_inputs.mjs install-hle'],
    Windows: ['prepare_native_inputs.mjs install-hle'],
  }),
  ast: Object.freeze({
    Linux: ['ci/build_ast_support.sh', 'prepare_native_inputs.mjs install-ast'],
    macOS: ['ci/build_ast_support.sh', 'prepare_native_inputs.mjs install-ast'],
    Windows: ['ci/build_ast_support.sh', 'prepare_native_inputs.mjs install-ast'],
  }),
});
const hostOs = target => target.startsWith('windows-') ? 'Windows' : target.startsWith('darwin-') ? 'macOS' : 'Linux';
export function stepAppliesTo(step, os) {
  const condition = String(step?.if ?? '').trim();
  if (!condition) return true;
  const match = /^runner\.os (==|!=) '(Linux|macOS|Windows)'$/.exec(condition);
  if (!match) return false;
  return match[1] === '==' ? match[2] === os : match[2] !== os;
}
export function prepareComponentProblems(steps) {
  const problems = [];
  for (const host of PREPARE_HOSTS) {
    const os = hostOs(host.target);
    const text = steps.filter(step => stepAppliesTo(step, os)).map(step => String(step.run ?? '')).join('\n');
    for (const [component, markers] of Object.entries(PREPARE_COMPONENT_STEPS))
      for (const marker of markers[os])
        if (!text.includes(marker)) problems.push(`prepare-native host ${host.target} lacks ${component} producer ${marker}`);
  }
  return problems;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, ...rest] = process.argv.slice(2);
    const option = name => { const i = rest.indexOf(`--${name}`); return i >= 0 ? rest[i + 1] : undefined; };
    if (command === 'provenance') console.log(JSON.stringify(prepareProvenance()));
    else if (command === 'assemble') console.log(JSON.stringify(assembleNativeInputs({root: path.resolve(option('root') || ''),
      target: option('target'), hostVersion: option('host-version') || undefined}).record));
    else if (command === 'install-host') console.log(JSON.stringify(await installHost({root: path.resolve(option('root') || ''),
      target: option('target')})));
    else if (command === 'compiler-source') {
      const source = compilerSource();
      const output = `COMPILER_SRC_URL=${source.repository}\nCOMPILER_REF=${source.commit}\n`;
      if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV, `PREPARE_COMPILER_COMMIT=${source.commit}\n`);
      process.stdout.write(output);
    }
    else if (command === 'pack') console.log(JSON.stringify(packNativeInputs({root: option('root') || '', out: option('out') || ''})));
    else if (command === 'install-llvm') console.log(JSON.stringify(installLlvm({root: path.resolve(option('root') || ''),
      target: option('target'), from: path.resolve(option('from') || ''), commits: componentCommits(), producer: option('producer'), shimCommit: option('shim-commit')})));
    else if (command === 'install-hle') console.log(JSON.stringify(await installHle({root: path.resolve(option('root') || ''),
      target: option('target'), parser: path.resolve(option('parser') || ''), cjbindFile: option('cjbind-file')})));
    else if (command === 'install-ast') console.log(JSON.stringify(installAst({root: path.resolve(option('root') || ''),
      target: option('target'), from: path.resolve(option('from') || ''), commits: componentCommits()})));
    else throw new Error('usage: prepare_native_inputs.mjs provenance | install-host --root DIR --target T'
      + ' | assemble --root DIR --target T [--host-version V] | install-llvm|install-ast --root DIR --target T --from DIR'
      + ' | compiler-source | pack --root DIR --out FILE');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
