#!/usr/bin/env node
// phase=prepare producer contract. Five native hosts each build, from fixed Git
// sources, the two input sets a later phase=publish consumes:
//   native-runtime-install-<llvm_platform>  paired runtime + boundscheck install
//   native-inputs-<target>                  host SDK + N/R/AST installs + locations.json
// This module is the single source of the host set and assembles the
// native-inputs root on the producing runner. It never invents a component:
// a missing installation fails closed. N/LLVM and AST are built on each host by
// the native-cjdb superbuild and travel as a single prefix;
// no private tools adapter is part of any native input.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {sdkPlatform, stdxChirMembers} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {readHostToolchainPin} from '../../../../ci/host-toolchain-pin.mjs';
import {readSourcePins} from '../../../../ci/native-llvm-inputs.mjs';
import {PREPARE_PYTHON, preparePythonMembers, PREPARE_LLDB_PYTHON_PACKAGE, PREPARE_LLDB_PYTHON_SIX, PREPARE_LLDB_ARGDUMPER, PREPARE_CLANG_RESOURCES,
  clangResourceProblems, PREPARE_COMPILER_RT, PREPARE_LLVM_PROJECTS, compilerRtLibraries, isStaticLibrary} from './build_prepare_llvm.mjs';
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
    compiler_ref: env.CJCJ_SOURCE_SELECTION ? compilerSource(env).commit : pins.COMPILER_REF, tools_ref: pins.TOOLS_REF, stdx_ref: pins.STDX_REF,
  };
  for (const key of PROVENANCE_KEYS) {
    const value = String(record[key] ?? '');
    const ok = key === 'run_id' || key === 'run_attempt' ? /^[1-9][0-9]*$/.test(value) : SHA40.test(value);
    if (!ok) throw new Error(`PREPARE_PROVENANCE ${key}`);
  }
  return record;
}

function sha256(file) {
  // A complete, uncompressed SDK handoff can exceed Node's single Buffer limit.
  const hash = crypto.createHash('sha256'), buffer = Buffer.allocUnsafe(256 * 1024), fd = fs.openSync(file, 'r');
  try {
    let size;
    while ((size = fs.readSync(fd, buffer)) !== 0) hash.update(buffer.subarray(0, size));
    return hash.digest('hex');
  } finally { fs.closeSync(fd); }
}
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
  // The standalone build can be monolithic; preserve the companion from a split Windows build.
  const foundation = native.llvmFoundationLibrary;
  if (foundation && fs.existsSync(path.join(from, foundation)))
    copyMember(from, foundation, install, `third_party/llvm/${native.llvmDirectory}/${foundation}`);
  const tools = {};
  for (const tool of PREPARE_LLVM_TOOLS) {
    const rel = `third_party/llvm/bin/${tool}${native.exe}`;
    tools[rel] = copyMember(from, `bin/${tool}${native.exe}`, install, rel);
    if (native.os !== 'win32') fs.chmodSync(path.join(install, rel), 0o755);
  }
  // The same build's clang resource tree, at the location stage0-run's
  // installation recipe copies as 'N clang resources' (sdk-targets.mjs).
  const clangResources = installClangResources({from, install});
  // N's lib/<tuple>: the compiler-rt libraries every installation recipe copies
  // from stage1-initial on (ci/bootstrap/sdk-targets.mjs installationRecipe).
  const targetLibraries = installCompilerRt({from, install, platform});
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
  // The helper Unix LLDB's Python package links to (lldb/lldb-argdumper ->
  // ../../../../bin/lldb-argdumper, build_prepare_llvm.mjs PREPARE_LLDB_ARGDUMPER), with its mode.
  if (native.os !== 'win32') installArgdumper(from, install);
  const lldbDir = path.join(from, 'lldb-lib');
  const lldbNames = fs.existsSync(lldbDir) ? fs.readdirSync(lldbDir).sort() : [];
  if (!lldbNames.length) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-lib');
  const libraries = {};
  for (const name of lldbNames) {
    const rel = `tools/${native.os === 'win32' ? 'bin' : 'lib'}/${name}`;
    libraries[rel] = copyMember(from, `lldb-lib/${name}`, install, rel);
  }
  // cjdb's Python (build_prepare_llvm.mjs preparePython): the prefix the LLDB
  // build was configured with is installed at third_party/llvm, where the
  // relocated consumer (sdk-cjdb-python.mjs verifyRelocatedCjdbPython) runs it,
  // with its original producer record and the observed CMake configuration.
  const python = installPython({from, install, platform, lldbNames});
  const facts = {schema: 'cjcj-prepare-llvm-v1', platform, commits: {...commits, shim: shimCommit},
    configuration: {producer, library: file, targets: 'X86;ARM;AArch64', tools: PREPARE_LLVM_TOOLS, projects: PREPARE_LLVM_PROJECTS},
    llvmLibrary: {file, sha256: row.sha256}, tools, clangResources, targetLibraries,
    nativeShim: {source: {commit: shimCommit, file: 'runtime_shim/cjselfhost_llvmshim.cpp'},
      compiler: {commit: commits.compiler, schema: 'schema/CjoFormat.fbs'}, llvm: {commit: commits.llvm},
      object: {path: PREPARE_SHIM_OBJECT, ...shim}, symbols: shimRecord.symbols,
      configuration: {producer: 'build/sdk/producers/release/build_prepare_llvm.mjs shim', argv: shimRecord.argv}},
    cjdb: {file: cjdbFile, ...cjdb, libraries, configuration: {projects: PREPARE_LLVM_PROJECTS, target: 'lldb'}},
    ...python};
  fs.writeFileSync(path.join(install, 'BUILD-INPUTS.json'), JSON.stringify(facts, null, 2) + '\n');
  return facts;
}
// Rows as the full N's facts carry them (ci/bootstrap/native-cjdb.mjs
// nativeTargetLibraries), which the installed reader re-checks
// (build/sdk/producers/srcbuild/lib/installed-inputs.mjs targetLibraries).
function installCompilerRt({from, install, platform}) {
  const dir = `lib/${sdkPlatform(platform).tuple}`;
  return compilerRtLibraries(platform).map(({name}) => {
    const rel = `${PREPARE_COMPILER_RT}/${name}`, to = `${dir}/${name}`;
    if (fs.existsSync(path.join(from, rel)) && !isStaticLibrary(path.join(from, rel)))
      throw new Error('PREPARE_COMPILER_RT_NOT_STATIC_LIBRARY ' + rel);
    return {path: to, ...copyMember(from, rel, install, to)};
  });
}
export const PREPARE_CLANG_RESOURCE_DIR = 'third_party/llvm/lib/clang';
function installClangResources({from, install}) {
  const source = path.join(from, PREPARE_CLANG_RESOURCES);
  if (!fs.existsSync(source)) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ' + PREPARE_CLANG_RESOURCES);
  const problems = clangResourceProblems(source);
  if (problems.length) throw new Error('PREPARE_CLANG_RESOURCES ' + problems.join('; '));
  const destination = path.join(install, PREPARE_CLANG_RESOURCE_DIR);
  fs.cpSync(source, destination, {recursive: true, verbatimSymlinks: true, errorOnExist: true, force: false});
  const files = {};
  const walk = rel => {
    for (const entry of fs.readdirSync(path.join(destination, rel), {withFileTypes: true})) {
      const child = rel ? rel + '/' + entry.name : entry.name;
      if (entry.isDirectory()) walk(child);
      else if (entry.isFile()) files[child] = sha256(path.join(destination, child));
      else throw new Error('PREPARE_CLANG_RESOURCES non-regular member ' + child);
    }
  };
  walk('');
  return {path: PREPARE_CLANG_RESOURCE_DIR, version: fs.readdirSync(destination)[0], files};
}
export const PREPARE_PYTHON_RECORD = 'third_party/llvm/PYTHON-BUILD-INPUTS.json';
export const PREPARE_LLDB_ARGDUMPER_FILE = 'third_party/llvm/bin/' + PREPARE_LLDB_ARGDUMPER;
function installArgdumper(from, install) {
  const rel = 'bin/' + PREPARE_LLDB_ARGDUMPER, row = copyMember(from, rel, install, PREPARE_LLDB_ARGDUMPER_FILE);
  const mode = fs.statSync(path.join(from, rel)).mode & 0o777;
  if (!(mode & 0o100)) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MODE ' + rel);
  fs.chmodSync(path.join(install, PREPARE_LLDB_ARGDUMPER_FILE), mode);
  return row;
}
// Every symbolic link under DIR, relative to it.
function packageLinks(dir, rel = '') {
  return fs.readdirSync(path.join(dir, rel), {withFileTypes: true}).flatMap(entry => {
    const child = rel ? rel + '/' + entry.name : entry.name;
    return entry.isSymbolicLink() ? [child] : entry.isDirectory() ? packageLinks(dir, child) : [];
  });
}
// Python and LLVM share bin/ and lib/, but no two inputs may own the same leaf.
function installExclusive(source, destination) {
  const existing = fs.lstatSync(destination, {throwIfNoEntry: false});
  if (!existing) {
    fs.cpSync(source, destination, {recursive: true, verbatimSymlinks: true, errorOnExist: true, force: false});
    return;
  }
  if (!existing.isDirectory() || !fs.lstatSync(source).isDirectory())
    throw new Error('PREPARE_PYTHON_INSTALL_COLLISION ' + destination);
  for (const name of fs.readdirSync(source))
    installExclusive(path.join(source, name), path.join(destination, name));
}
function installPython({from, install, platform, lldbNames}) {
  const record = path.join(from, 'PYTHON-BUILD-INPUTS.json'), configuredFile = path.join(from, 'PYTHON-CONFIGURED.json');
  if (!PREPARE_PYTHON[platform]) {
    if (fs.existsSync(path.join(from, 'python'))) throw new Error('NATIVE_INPUTS_PYTHON_UNPINNED ' + platform);
    return {};
  }
  for (const file of [record, configuredFile, path.join(from, 'python')])
    if (!fs.existsSync(file)) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ' + path.relative(from, file));
  const facts = JSON.parse(fs.readFileSync(record, 'utf8')), pin = PREPARE_PYTHON[platform];
  if (facts.rc !== 0 || facts.target !== platform || facts.source?.url !== pin.url || facts.source?.sha256 !== pin.sha256
    || facts.source?.version !== pin.version || !Object.keys(facts.files || {}).length) throw new Error('PREPARE_PYTHON_RECORD');
  const configured = JSON.parse(fs.readFileSync(configuredFile, 'utf8'));
  for (const key of ['executable', 'include', 'library', 'suffix'])
    if (!configured.selected?.[key] || !configured.actual?.[key]) throw new Error('PREPARE_PYTHON_CONFIGURED ' + key);
  const nativeRoot = path.join(install, 'third_party/llvm');
  for (const name of preparePythonMembers(platform)) {
    const source = path.join(from, 'python', name);
    if (fs.existsSync(source)) installExclusive(source, path.join(nativeRoot, name));
  }
  for (const [rel, row] of Object.entries(facts.files))
    if (sha256(path.join(nativeRoot, rel)) !== row.sha256) throw new Error('PREPARE_PYTHON_PRODUCT_BYTES ' + rel);
  // The lldb package's _lldb binding is the same build's liblldb; both live in
  // the native root the relocated consumer imports from (PYTHONHOME there).
  const pkg = path.join(from, 'lldb-python/lldb');
  if (!fs.existsSync(pkg)) throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-python/lldb');
  // The package imports its sibling six (build_prepare_llvm.mjs PREPARE_LLDB_PYTHON_SIX).
  const six = path.join(from, 'lldb-python', PREPARE_LLDB_PYTHON_SIX);
  if (!fs.existsSync(six) || !fs.lstatSync(six).isFile())
    throw new Error('NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-python/' + PREPARE_LLDB_PYTHON_SIX);
  for (const name of lldbNames) fs.copyFileSync(path.join(from, 'lldb-lib', name), path.join(nativeRoot, 'lib', name));
  const installedPackage = path.join(nativeRoot, PREPARE_LLDB_PYTHON_PACKAGE);
  fs.cpSync(pkg, installedPackage, {recursive: true, verbatimSymlinks: true, errorOnExist: true, force: false});
  fs.copyFileSync(six, path.join(path.dirname(installedPackage), PREPARE_LLDB_PYTHON_SIX), fs.constants.COPYFILE_EXCL);
  verifyPackageLinks(nativeRoot, platform, path.join(from, 'lldb-lib'), lldbNames);
  fs.copyFileSync(record, path.join(install, PREPARE_PYTHON_RECORD));
  return {python: {configured}, pythonInstallationInput: {record: PREPARE_PYTHON_RECORD, sha256: sha256(path.join(install, PREPARE_PYTHON_RECORD))}};
}

export function verifyPackageLinks(nativeRoot, platform, libraryDir, lldbNames) {
  const installedPackage = path.join(nativeRoot, PREPARE_LLDB_PYTHON_PACKAGE);
  // Each link the package carries (Unix _lldb -> liblldb, lldb-argdumper -> bin) resolves inside the native root.
  const nativeReal = fs.realpathSync(nativeRoot);
  for (const link of packageLinks(installedPackage)) {
    const file = path.join(installedPackage, link), target = fs.existsSync(file) && fs.realpathSync(file);
    if (!target || !target.startsWith(nativeReal + path.sep))
      throw new Error('PREPARE_LLDB_PYTHON_LINK ' + path.posix.join(PREPARE_LLDB_PYTHON_PACKAGE, link));
  }
  const binding = fs.readdirSync(installedPackage).find(name => name.startsWith('_lldb'));
  const real = binding && fs.existsSync(path.join(installedPackage, binding)) && fs.realpathSync(path.join(installedPackage, binding));
  // Unix: _lldb links to the same build's liblldb. Windows LLDB copies liblldb.dll
  // to _lldb*.pyd, so there the binding must be that library byte for byte.
  const sameLibrary = real && (sdkPlatform(platform).os === 'win32'
    ? lldbNames.some(name => sha256(path.join(libraryDir, name)) === sha256(real))
    : lldbNames.includes(path.basename(real)));
  if (!real || !real.startsWith(fs.realpathSync(nativeRoot) + path.sep) || !sameLibrary)
    throw new Error('PREPARE_LLDB_PYTHON_BINDING ' + (binding || 'missing'));
}

// Check the existing compiler installation in place. AST and shim keep their
// ordinary build facts; the handoff needs only one physical N prefix.
export function checkSuperbuildInstall(install, platform) {
  const native = sdkPlatform(platform), root = path.join(install, 'third_party/llvm');
  const libDir = path.join(root, native.llvmDirectory);
  const liblldb = 'liblldb' + native.shared;
  const required = [path.join(libDir, liblldb), path.join(install, 'tools/bin/cjdb' + native.exe),
    ...['frontend','lsp'].map(name => path.join(install, 'tools', native.os === 'win32' ? 'bin' : 'lib', 'libcangjie-' + name + native.shared)),
    ...[...PREPARE_LLVM_TOOLS, 'clang', 'lldb-argdumper'].map(name => path.join(root, 'bin', name + native.exe)),
    path.join(install, PREPARE_SHIM_OBJECT), path.join(root, PREPARE_LLDB_PYTHON_PACKAGE, '../six.py'),
    path.join(install,'include/cangjie/Parse/Parser.h'),path.join(install,'include/cangjie/Utils/Casting.h')];
  for (const file of required) if (!fs.statSync(file,{throwIfNoEntry:false})?.isFile() || !fs.statSync(file).size) throw Error('PREPARE_NATIVE_FILE ' + file);
  if (native.os !== 'win32') fs.accessSync(path.join(root, 'bin/lldb-argdumper'), fs.constants.X_OK);
  const headers = clangResourceProblems(path.join(root,'lib/clang'));
  if (headers.length) throw Error('PREPARE_CLANG_RESOURCES ' + headers.join(', '));
  for (const {name} of compilerRtLibraries(platform))
    if (!isStaticLibrary(path.join(install,'lib',native.tuple,name))) throw Error('PREPARE_COMPILER_RT_MISSING ' + name);
  verifyPackageLinks(root, platform, libDir, fs.readdirSync(libDir).filter(n => n === liblldb || n.startsWith(liblldb + '.') || /^liblldb\.[0-9.]+\.dylib$/.test(n)));
}
// std reads the AST installation's include root (ci/bootstrap/sdk-std-resume.mjs
// selectedStdAst) and requires these headers there (sdk-native-stage.mjs
// STD_AST_HEADER); Parse/Parser.h includes the rest of the public tree, so the
// complete include/cangjie tree of the same build (ci/build_ast_support.sh) is installed.
export const PREPARE_AST_HEADER_ROOT = 'include/cangjie';
export const PREPARE_AST_STD_HEADERS = Object.freeze(['include/cangjie/Parse/Parser.h', 'include/cangjie/CHIR/IR/AttributeInfo.h']);
function copyTree(from, rel, install) {
  const source = path.join(from, rel), rows = {};
  if (!fs.existsSync(source) || !fs.lstatSync(source).isDirectory()) throw new Error(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ${rel}`);
  const walk = dir => {
    for (const name of fs.readdirSync(path.join(from, dir)).sort()) {
      const member = `${dir}/${name}`, stat = fs.lstatSync(path.join(from, member));
      if (stat.isDirectory()) walk(member);
      else if (stat.isFile()) rows[member] = copyMember(from, member, install);
      else throw new Error(`NATIVE_INPUTS_PRODUCER_OUTPUT_TYPE ${member}`);
    }
  };
  walk(rel);
  return rows;
}
// Install the ci/build_ast_support.sh output (cangjie-ast-support, std
// support ON) in the shape readInstalledNativeAst consumes after transport.
export function installAst({root, target, from, commits}) {
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const install = freshComponent(root, 'ast');
  const library = `lib/${native.tuple}/libcangjie-ast-support.a`;
  const flatc = `third_party/flatbuffers/bin/flatc${native.exe}`;
  const libraryRow = copyMember(from, 'libcangjie-ast-support.a', install, library);
  for (const rel of PREPARE_AST_STD_HEADERS)
    if (!fs.existsSync(path.join(from, rel)) || !fs.statSync(path.join(from, rel)).isFile())
      throw new Error(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ${rel}`);
  const headerRows = copyTree(from, PREPARE_AST_HEADER_ROOT, install);
  const headers = {root: PREPARE_AST_HEADER_ROOT, files: Object.keys(headerRows).length,
    sha256: crypto.createHash('sha256').update(Object.entries(headerRows).map(([rel, row]) => `${row.sha256}  ${rel}\n`).join('')).digest('hex'),
    std: Object.fromEntries(PREPARE_AST_STD_HEADERS.map(rel => [rel, headerRows[rel]]))};
  const files = {[library]: libraryRow};
  for (const rel of ['schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h', ...stdxChirMembers, flatc])
    files[rel] = copyMember(from, rel, install);
  const build = {target: 'cangjie-ast-support', configuration: {stdSupport: 'ON', producer: 'ci/build_ast_support.sh'}};
  const facts = {schema: 'cjcj-prepare-ast-v1', platform, commits: {compiler: commits.compiler, llvm: commits.llvm},
    configuration: build.configuration,
    astInstallation: {platform, source: {commit: commits.compiler}, library, files, headers, build}};
  fs.writeFileSync(path.join(install, 'BUILD-INPUTS.json'), JSON.stringify(facts, null, 2) + '\n');
  return facts;
}

// Host SDK: the official archive is the identity the consumers verify
// (select-native-host.mjs -> verifyOfficialSdkIdentity needs the original
// archive name, size and SHA-256), so prepare keeps that file, not a re-tar
// of an installed toolchain. The pair rule is the consumer's nativePair rule:
// an explicit LLVM/runtime pair needs an explicit host; an empty selection uses
// the checked-in pin. Only the pinned identity can be prepared here.
// The prepare job's pin step (ci/native-llvm-inputs.mjs) writes the pair it
// resolved into GITHUB_ENV, so a non-empty pair alone does not mean the caller
// chose it: CJCJ_NATIVE_PAIR_SELECTION says which, and 'pinned' is honoured only
// for exactly the checked-in pair. Without the marker a non-empty pair is explicit.
export function nativePairSelection(env = process.env) {
  const marker = env.CJCJ_NATIVE_PAIR_SELECTION || '';
  const llvmRef = env.CJCJ_NATIVE_LLVM_REF || '', runtimeRef = env.CJCJ_NATIVE_RUNTIME_REF || '';
  if (!marker) return llvmRef || runtimeRef ? 'explicit' : 'pinned';
  if (marker === 'explicit') return 'explicit';
  if (marker !== 'pinned') throw new Error(`NATIVE_PAIR_SELECTION_INVALID ${marker}`);
  const {llvm, runtime} = readSourcePins();
  if ((llvmRef && llvmRef !== llvm.LLVM_SHA) || (runtimeRef && runtimeRef !== runtime.RUNTIME_REF))
    throw new Error('NATIVE_PAIR_SELECTION_NOT_PINNED');
  return 'pinned';
}
export function prepareHostVersion(target, env = process.env) {
  const platform = prepareHost(target).llvm_platform;
  const pinned = readHostToolchainPin(platform).replace(/^nightly-/, '');
  const requested = env.CJCJ_NATIVE_HOST_VERSION || '';
  if ((env.CJCJ_NATIVE_LLVM_REF || env.CJCJ_NATIVE_RUNTIME_REF) && !requested && nativePairSelection(env) === 'explicit')
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
// same CJCJ_SOURCE_SELECTION) exports the selected compiler URL and SHA, which the
// consumers' buildConfig then compares the AST facts with.
export function compilerSource(env = process.env) {
  const selected = workflowSourceSelection(env);
  const source = {repository: selected.COMPILER_SRC_URL, commit: selected.CANGJIE_COMPILER_SHA};
  if (!SHA40.test(source.commit || '') || !source.repository) throw new Error('PREPARE_COMPILER_SOURCE');
  return source;
}

// HLE dependency package read by ci/bootstrap/hle-input.mjs configureHleInput and
// build/srcbuild/hle-dependencies.mjs: this runner's own Node executable, the npm
// tree of the pinned tools dtsparser package.json (--ignore-scripts: its
// postinstall download is replaced by the pinned cjbind below) and the public
// cjbind-cangjie release that consumer accepts. That release has no darwin-x64
// asset (the tag commit's build matrix has no darwin-x64 cell), so darwin_x86_64
// carries the controller-approved source identity below instead of any foreign
// binary: the release's tag commit, built on that prepare host (macos-15-intel)
// with the installed official darwin-x64 host SDK, and recorded by commit.
export const HLE_CJBIND = Object.freeze({version: 'v1.1.0-alpha.53.1',
  base: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie/releases/download/v1.1.0-alpha.53.1/',
  assets: Object.freeze({
    linux_x86_64: Object.freeze({name: 'cjbind-linux-x64', size: 90753504, sha256: '71bf15dbd18a343c366a923a5b25766a373af5d1709a59c25ced545ebc88f21e'}),
    linux_aarch64: Object.freeze({name: 'cjbind-linux-arm64', size: 82689672, sha256: '18fee7c8d63722f0eb990a5640d877212b195c5d994d78df29e65434d21bb579'}),
    windows_x86_64: Object.freeze({name: 'cjbind-windows-x64.exe', size: 77087232, sha256: '417c6aac0d2ff448490c2027bbbd619cf09d10b207e1513ebff369d69db9935e'}),
    darwin_aarch64: Object.freeze({name: 'cjbind-darwin-arm64', size: 92136544, sha256: '4da660c010203be14660edb5ee0e76f4a894214ca7a7c383702159d2f9d4005b'}),
  })});
export const HLE_DESCRIPTOR = 'hle/hle-dependencies.json';
export const HLE_CJBIND_SOURCE_BUILD = Object.freeze({
  darwin_x86_64: Object.freeze({repo: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git',
    commit: 'd9ba9709906fda36fdb486fa55ec615cdb1fa2cb', tag: 'v1.1.0-alpha.53.1', version: 'v1.1.0-alpha.53.1-source'}),
});
export function hleCjbindSource(target) {
  const platform = prepareHost(target).llvm_platform, build = HLE_CJBIND_SOURCE_BUILD[platform];
  if (!build) throw new Error(`HLE_CJBIND_SOURCE_UNAPPROVED ${platform}`);
  return build;
}
// A source-built cjbind is accepted only on its approved host, only for the
// fixed commit, and only as a non-empty executable regular file.
function sourceBuiltCjbind(platform, file, commit) {
  const build = HLE_CJBIND_SOURCE_BUILD[platform];
  if (!build) {
    if (commit !== undefined) throw new Error(`HLE_CJBIND_SOURCE_UNAPPROVED ${platform}`);
    return undefined;
  }
  if (!file) throw new Error(`HLE_CJBIND_SOURCE_FILE_REQUIRED ${platform}`);
  if (commit !== build.commit) throw new Error(`HLE_CJBIND_SOURCE_COMMIT ${commit ?? '(none)'} != ${build.commit}`);
  const stat = fs.existsSync(file) ? fs.statSync(file) : undefined;
  if (!stat?.isFile() || stat.size === 0 || (process.platform !== 'win32' && (stat.mode & 0o111) === 0))
    throw new Error(`HLE_CJBIND_SOURCE_FILE ${file}`);
  return build;
}
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
export async function installHle({root, target, parser, node = process.execPath, cjbindFile, cjbindSourceCommit,
  installModules = npmInstall, download = downloadAsset, asset: pinned}) {
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const build = sourceBuiltCjbind(platform, cjbindFile, cjbindSourceCommit);
  const asset = build ? undefined : pinned ?? hleCjbindAsset(platform), specs = hleModuleSpecs(parser);
  const hle = freshComponent(root, 'hle');
  const nodeRel = `node/node${native.exe}`, cjbindRel = `cjbind/cjbind${native.exe}`;
  fs.mkdirSync(path.join(hle, 'node'));
  fs.copyFileSync(node, path.join(hle, nodeRel));
  const nodeVersion = String(spawnSync(node, ['--version'], {encoding: 'utf8'}).stdout || '').trim();
  if (!/^v\d+\.\d+\.\d+$/.test(nodeVersion)) throw new Error('HLE_NODE_VERSION');
  fs.mkdirSync(path.join(hle, 'cjbind'));
  const cjbind = path.join(hle, cjbindRel);
  if (cjbindFile) fs.copyFileSync(cjbindFile, cjbind); else await download(asset.url, cjbind);
  if (!build && (fs.statSync(cjbind).size !== asset.size || sha256(cjbind) !== asset.sha256)) throw new Error('HLE_CJBIND_IDENTITY');
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
    cjbind: build
      ? {path: cjbindRel, version: build.version, source: `${build.repo}@${build.commit}`, commit: build.commit,
        sha256: sha256(cjbind), size: fs.statSync(cjbind).size}
      : {path: cjbindRel, version: asset.version, source: asset.url, sha256: asset.sha256, size: asset.size}};
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
  const facts = JSON.parse(fs.readFileSync(path.join(root, llvm.buildResult), 'utf8'));
  if (facts.astInstallation && (facts.platform !== host.llvm_platform || facts.commits?.shim !== provenance.producer_sha
    || facts.commits.llvm !== provenance.native_llvm_ref || facts.commits.runtime !== provenance.native_runtime_ref
    || facts.commits.compiler !== provenance.compiler_ref)) throw Error('PREPARE_NATIVE_SOURCE_PAIR');
  if (!facts.nativeShim)
    throw new Error('NATIVE_INPUTS_COMPONENT_MISSING shim');
  const locations = {
    platform: host.llvm_platform,
    host: selectedHost,
    hleDependencies: HLE_DESCRIPTOR,
    installations: {
      llvm,
      runtime: installation(root, 'runtime', 'NATIVE-INPUTS.json'),
      ast: facts.astInstallation ? llvm : installation(root, 'ast', 'BUILD-INPUTS.json'),
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

// Static wiring contract of prepare.yml: its prepare-native job builds the five
// hosts directly (no nested workflow call), uploads both artifact families, and
// feeds only the same-run linux-x64 source build; release.yml, sdk-build.yml and
// sdk-build-target.yml carry no prepare path. Returns a list of problems; empty means wired.
export function prepareWorkflowProblems({release, prepare, sdkBuild, target}) {
  const problems = [...g4SourcePhases(release, prepare).problems];
  const prep = loadYaml(prepare)?.jobs || {}, sdk = loadYaml(sdkBuild)?.jobs || {}, tgt = loadYaml(target)?.jobs || {};
  const targetInputs = loadYaml(target)?.on?.workflow_call?.inputs || {};
  if (sdk.prepare || sdk.package) problems.push('sdk-build.yml still carries a prepare or package job');
  if (tgt['prepare-native'] || targetInputs.prepare_native) problems.push('sdk-build-target.yml still carries prepare-native');
  if (/prepare_native/.test(String(tgt.plan?.if ?? ''))) problems.push('sdk-build-target.yml plan still reads prepare_native');
  const job = prep['prepare-native'];
  if (!job || job.uses || job.if !== undefined) { problems.push('prepare.yml lacks an unconditional prepare-native job'); return problems; }
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
  // darwin-x64: the approved source cjbind is built, checked by commit and
  // probed on that host, then handed to install-hle with that commit.
  const source = (job.steps || []).find(step => String(step.run || '').includes('prepare_native_inputs.mjs cjbind-source'));
  if (!source || source.if !== "matrix.target == 'darwin-x64'" || !/rev-parse HEAD/.test(source.run)
    || !/target\/release\/bin\/main --version/.test(source.run) || !/uv run/.test(source.run))
    problems.push('prepare-native does not build the darwin-x64 source cjbind');
  const hle = (job.steps || []).find(step => String(step.run || '').includes('prepare_native_inputs.mjs install-hle'));
  if (!/matrix\.target == 'darwin-x64' && '--cjbind-file "\$CJBIND_FILE" --cjbind-source-commit "\$CJBIND_COMMIT"'/.test(String(hle?.run || ''))
    || (source?.id && !String(hle?.env?.CJBIND_FILE || '').includes(`steps.${source.id}.outputs.file`)))
    problems.push('prepare-native does not hand the darwin-x64 source cjbind to install-hle');
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
  native: Object.fromEntries(['Linux','macOS','Windows'].map(os => [os,
    ['prepare_native_superbuild.mjs "${{ matrix.target }}"', 'git -C compiler checkout', 'srcbuild_git_checkout_skip_zone_identifier flatbuffers']])),
  hle: Object.freeze({
    Linux: ['prepare_native_inputs.mjs install-hle'],
    macOS: ['prepare_native_inputs.mjs install-hle'],
    Windows: ['prepare_native_inputs.mjs install-hle'],
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
    else if (command === 'host-version') console.log(prepareHostVersion(option('target')));
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
      target: option('target'), parser: path.resolve(option('parser') || ''), cjbindFile: option('cjbind-file'),
      cjbindSourceCommit: option('cjbind-source-commit')})));
    else if (command === 'cjbind-source') {
      const build = hleCjbindSource(option('target'));
      process.stdout.write(`CJBIND_SRC_URL=${build.repo}\nCJBIND_TAG=${build.tag}\nCJBIND_REF=${build.commit}\n`);
    }
    else if (command === 'install-ast') console.log(JSON.stringify(installAst({root: path.resolve(option('root') || ''),
      target: option('target'), from: path.resolve(option('from') || ''), commits: componentCommits()})));
    else throw new Error('usage: prepare_native_inputs.mjs provenance | host-version --target T | install-host --root DIR --target T'
      + ' | assemble --root DIR --target T [--host-version V] | install-llvm|install-ast --root DIR --target T --from DIR'
      + ' | compiler-source | cjbind-source --target T | pack --root DIR --out FILE');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
