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
import {sdkPlatform, stdxChirMembers} from '../../../../ci/bootstrap/sdk-platform.mjs';
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

// Install the in-process LLVM library built on this host (Unix: the
// LLVM_BUILD_LLVM_DYLIB CMake build of the pinned fork; Windows: the
// platform_tuples build) at the location every native reader resolves:
// llvm/third_party/llvm/<llvmDirectory>/<llvmLibrary> + llvm/BUILD-INPUTS.json.
export function installLlvm({root, target, from, commits, producer}) {
  const platform = prepareHost(target).llvm_platform, native = sdkPlatform(platform);
  const install = freshComponent(root, 'llvm');
  const file = `third_party/llvm/${native.llvmDirectory}/${native.llvmLibrary}`;
  const row = copyMember(from, native.llvmLibrary, install, file);
  const facts = {schema: 'cjcj-prepare-llvm-v1', platform, commits,
    configuration: {producer, library: file, targets: 'X86;ARM;AArch64'},
    llvmLibrary: {file, sha256: row.sha256}};
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

// No native input carries a tools adapter: the retired private
// ts/src/sharedbuild modules are not an input of any host, and a stray
// adapter directory fails closed instead of being forwarded.
export function assembleNativeInputs({root, target, hostVersion, env = process.env, pins}) {
  const host = prepareHost(target);
  const provenance = prepareProvenance(env, pins);
  if (!fs.existsSync(path.join(root, 'host'))) throw new Error('NATIVE_INPUTS_COMPONENT_MISSING host');
  if (!/^[0-9A-Za-z.+-]+$/.test(hostVersion || '')) throw new Error('PREPARE_HOST_VERSION');
  if (fs.existsSync(path.join(root, 'adapter'))) throw new Error('NATIVE_TOOLS_ADAPTER_UNEXPECTED');
  const locations = {
    platform: host.llvm_platform,
    host: {install: 'host', archive: 'host-archive', version: hostVersion},
    installations: {
      llvm: installation(root, 'llvm', 'BUILD-INPUTS.json'),
      runtime: installation(root, 'runtime', 'NATIVE-INPUTS.json'),
      ast: installation(root, 'ast', 'BUILD-INPUTS.json'),
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
  const uploads = (job.steps || []).filter(step => String(step.uses || '').startsWith('actions/upload-artifact@')).map(step => step.with?.name);
  for (const name of ['native-runtime-install-${{ matrix.llvm_platform }}', 'native-inputs-${{ matrix.target }}'])
    if (!uploads.includes(name)) problems.push(`prepare-native does not upload ${name}`);
  const text = JSON.stringify(job.steps || []);
  for (const program of ['build/sdk/producers/platform_matrix/build_runtime.mjs', 'build/sdk/producers/platform_matrix/native_runtime_package.mjs',
    'build/sdk/producers/release/prepare_native_inputs.mjs assemble'])
    if (!text.includes(program)) problems.push(`prepare-native does not run ${program}`);
  problems.push(...prepareComponentProblems(job.steps || []));
  if (/deploy-native-tools|sharedbuild|privateRoot/.test(text)) problems.push('prepare-native consumes the retired private tools adapter');
  if (/gh release|softprops\/action-gh-release|ci\/release-publish\.mjs/.test(text)) problems.push('prepare-native publishes');
  return problems;
}

// Per-host N/LLVM and AST producers. A step applies to a host when its `if`
// is empty or a plain runner.os (in)equality that admits the host's OS; every
// host needs its producer markers and the install step in its applicable steps.
export const PREPARE_COMPONENT_STEPS = Object.freeze({
  llvm: Object.freeze({
    Linux: ['ci/fetch-llvm-runtime.mjs', '-DLLVM_BUILD_LLVM_DYLIB=ON', 'prepare_native_inputs.mjs install-llvm'],
    macOS: ['ci/fetch-llvm-runtime.mjs', '-DLLVM_BUILD_LLVM_DYLIB=ON', 'prepare_native_inputs.mjs install-llvm'],
    Windows: ['build/sdk/producers/platform_tuples/fetch_sources.mjs', 'build/sdk/producers/platform_tuples/build_tuple.mjs',
      'prepare_native_inputs.mjs install-llvm'],
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
      target: option('target'), hostVersion: option('host-version')}).record));
    else if (command === 'install-llvm') console.log(JSON.stringify(installLlvm({root: path.resolve(option('root') || ''),
      target: option('target'), from: path.resolve(option('from') || ''), commits: componentCommits(), producer: option('producer')})));
    else if (command === 'install-ast') console.log(JSON.stringify(installAst({root: path.resolve(option('root') || ''),
      target: option('target'), from: path.resolve(option('from') || ''), commits: componentCommits()})));
    else throw new Error('usage: prepare_native_inputs.mjs provenance | assemble --root DIR --target T --host-version V'
      + ' | install-llvm|install-ast --root DIR --target T --from DIR');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
