#!/usr/bin/env node
// phase=prepare producer contract. Five native hosts each build, from fixed Git
// sources, the two input sets a later phase=publish consumes:
//   native-runtime-install-<llvm_platform>  paired runtime + boundscheck install
//   native-inputs-<target>                  host SDK + N/R/AST installs + locations.json
// This module is the single source of the host set and assembles the
// native-inputs root on the producing runner. It never invents a component:
// a missing installation or a missing public Unix adapter fails closed.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {NATIVE_TOOLS_ADAPTER_FILES} from '../../../../ci/bootstrap/deploy-native-tools.mjs';
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

// The Darwin H1 producer consumes the two adapter modules. They must already be
// deployed into <root>/adapter by deploy-native-tools.mjs from a public pinned
// commit; Linux and Windows inputs must not carry them.
export function assembleNativeInputs({root, target, hostVersion, env = process.env, pins}) {
  const host = prepareHost(target);
  const provenance = prepareProvenance(env, pins);
  if (!fs.existsSync(path.join(root, 'host'))) throw new Error('NATIVE_INPUTS_COMPONENT_MISSING host');
  if (!/^[0-9A-Za-z.+-]+$/.test(hostVersion || '')) throw new Error('PREPARE_HOST_VERSION');
  const darwin = target.startsWith('darwin-');
  const adapter = path.join(root, 'adapter');
  if (darwin) {
    for (const rel of NATIVE_TOOLS_ADAPTER_FILES)
      if (!fs.existsSync(path.join(adapter, rel))) throw new Error(`NATIVE_TOOLS_ADAPTER_MISSING ${rel}`);
  } else if (fs.existsSync(adapter)) throw new Error('NATIVE_TOOLS_ADAPTER_UNEXPECTED');
  const locations = {
    platform: host.llvm_platform,
    host: {install: 'host', archive: 'host-archive', version: hostVersion},
    installations: {
      llvm: installation(root, 'llvm', 'BUILD-INPUTS.json'),
      runtime: installation(root, 'runtime', 'NATIVE-INPUTS.json'),
      ast: installation(root, 'ast', 'BUILD-INPUTS.json'),
    },
    tools: darwin ? {privateRoot: 'adapter'} : {},
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
    'build/sdk/producers/release/prepare_native_inputs.mjs assemble', 'ci/bootstrap/deploy-native-tools.mjs'])
    if (!text.includes(program)) problems.push(`prepare-native does not run ${program}`);
  if (/gh release|softprops\/action-gh-release|ci\/release-publish\.mjs/.test(text)) problems.push('prepare-native publishes');
  return problems;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, ...rest] = process.argv.slice(2);
    const option = name => { const i = rest.indexOf(`--${name}`); return i >= 0 ? rest[i + 1] : undefined; };
    if (command === 'provenance') console.log(JSON.stringify(prepareProvenance()));
    else if (command === 'assemble') console.log(JSON.stringify(assembleNativeInputs({root: path.resolve(option('root') || ''),
      target: option('target'), hostVersion: option('host-version')}).record));
    else throw new Error('usage: prepare_native_inputs.mjs provenance | assemble --root DIR --target T --host-version V');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
