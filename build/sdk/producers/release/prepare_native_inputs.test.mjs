// phase=prepare: five native hosts, both artifact families, no route to publish,
// and native-inputs roots that bind their real installations and provenance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import crypto from 'node:crypto';
import {PREPARE_HOSTS, PROVENANCE_KEYS, assembleNativeInputs, prepareProvenance, prepareWorkflowProblems,
  installLlvm, installAst, componentCommits, prepareComponentProblems, installHost, prepareHostVersion,
  packNativeInputs, compilerSource, PREPARE_LLVM_TOOLS} from './prepare_native_inputs.mjs';
import {unpackNativeArtifact} from '../../../../ci/bootstrap/native-artifact-archive.mjs';
import {buildPrepareLlvm, llvmConfigureArgs} from './build_prepare_llvm.mjs';
import {nativeInstallationLocations} from '../../../../ci/bootstrap/native-installation-locations.mjs';
import {readInstalledNativeAst} from '../../../../ci/bootstrap/installed-native-ast.mjs';
import {sdkPlatform, stdxChirMembers} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {rejectPrivateTools} from '../../../../ci/bootstrap/deploy-native-tools.mjs';
import {load as loadYaml} from '../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {sourceBuildCells} from '../../../lib/targets.mjs';

const root = path.resolve(import.meta.dirname, '../../../..');
const read = name => fs.readFileSync(path.join(root, '.github/workflows', name + '.yml'), 'utf8');
const real = () => ({release: read('release'), sdkBuild: read('sdk-build'), target: read('sdk-build-target')});
const once = (text, from, to) => { assert.equal(text.split(from).length, 2, from); return text.replace(from, to); };

test('the real workflows wire the five-host prepare path without a route to publish', () => {
  assert.deepEqual(prepareWorkflowProblems(real()), []);
  assert.deepEqual(PREPARE_HOSTS.map(row => row.target), ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64']);
  for (const cell of sourceBuildCells()) {
    const host = PREPARE_HOSTS.find(row => row.target === cell.target);
    assert.ok(host, cell.target);
    assert.equal(host.runner, cell.runner, `${cell.target} runner differs from the repository source matrix`);
    assert.equal(host.llvm_platform, cell.llvm_platform);
  }
});

test('red cut: dropping one native host from prepare-native is rejected', () => {
  const w = real();
  w.target = once(w.target, '          - target: darwin-x64\n            llvm_platform: darwin_x86_64\n            runner: macos-15-intel\n', '');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native lacks host darwin-x64|darwin_x86_64|macos-15-intel'));
});

test('red cut: a prepare host on a foreign runner is rejected', () => {
  const w = real();
  w.target = once(w.target, '            llvm_platform: windows_x86_64\n            runner: windows-2025\n',
    '            llvm_platform: windows_x86_64\n            runner: ubuntu-24.04\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native lacks host windows-x64|windows_x86_64|windows-2025'));
});

test('red cut: prepare that can reach publish is rejected', () => {
  const w = real();
  w.release = once(w.release, "    if: inputs.phase == 'publish' && !inputs.dry_run\n", "    if: '!inputs.dry_run'\n");
  assert.ok(prepareWorkflowProblems(w).includes('publish is not gated on phase=publish'));
  const v = real();
  v.release = once(v.release, '    needs: [source-p1-linux-x64, source-p2-linux-aarch64,', '    needs: [prepare-native, source-p1-linux-x64, source-p2-linux-aarch64,');
  assert.ok(prepareWorkflowProblems(v).some(p => p === 'publish depends on prepare job prepare-native'), JSON.stringify(prepareWorkflowProblems(v)));
});

test('red cut: the same-run linux-x64 source build must consume this run\'s native inputs', () => {
  const w = real();
  w.release = once(w.release, '      native_inputs_artifact: native-inputs\n      native_inputs_run_id: ${{ github.run_id }}\n',
    '      native_inputs_artifact: native-inputs\n      native_inputs_run_id: ${{ inputs.native_inputs_run_id }}\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-srcbuild-linux-x64 native_inputs_run_id must be ${{ github.run_id }}'));
});

test('red cut: prepare-native without one artifact family is rejected', () => {
  const w = real();
  w.target = once(w.target, '          name: native-runtime-install-${{ matrix.llvm_platform }}\n', '          name: native-runtime-install\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native does not upload native-runtime-install-${{ matrix.llvm_platform }}'));
});

const commit = c => c.repeat(40);
// A host root as install-host leaves it: the SDK tree, its original archive
// file and the HOST-INPUT.json record that binds archive name, size and digest.
function putHost(dir, platform, version = '1.1.0') {
  const native = sdkPlatform(platform), archive = `cangjie-sdk-fixture-${version}.tar.gz`;
  fs.mkdirSync(path.join(dir, 'host/bin'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'host/bin/cjc' + native.exe), 'host');
  fs.mkdirSync(path.join(dir, 'host-archive'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'host-archive', archive), 'original archive bytes');
  const bytes = fs.readFileSync(path.join(dir, 'host-archive', archive));
  fs.writeFileSync(path.join(dir, 'HOST-INPUT.json'), JSON.stringify({schema: 'cjcj-prepare-host-v1', platform, version, install: 'host',
    archive: {file: `host-archive/${archive}`, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), size: bytes.length}}));
}
const env = {GITHUB_SHA: commit('a'), GITHUB_RUN_ID: '4242', GITHUB_RUN_ATTEMPT: '1',
  CJCJ_NATIVE_LLVM_REF: commit('b'), CJCJ_NATIVE_RUNTIME_REF: commit('c')};
const pins = {COMPILER_REF: commit('d'), TOOLS_REF: commit('e'), STDX_REF: commit('f')};
function inputs(t, {darwin = false, skip, hostTarget} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-inputs-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), body); };
  putHost(dir, PREPARE_HOSTS.find(h => h.target === (hostTarget || 'linux-aarch64')).llvm_platform);
  for (const [name, file] of [['llvm', 'BUILD-INPUTS.json'], ['runtime', 'NATIVE-INPUTS.json'], ['ast', 'BUILD-INPUTS.json']])
    if (name !== skip) put(`${name}/${file}`, JSON.stringify({configuration: {name}}));
  if (darwin) for (const rel of ['ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']) put('adapter/' + rel, '//');
  return dir;
}

test('assemble binds the real installations and every provenance identity', t => {
  const dir = inputs(t);
  const {locations, record} = assembleNativeInputs({root: dir, target: 'linux-aarch64', hostVersion: '1.1.0', env, pins});
  assert.equal(locations.platform, 'linux_aarch64');
  assert.deepEqual(locations.host, {install: 'host', archive: 'host-archive/cangjie-sdk-fixture-1.1.0.tar.gz', version: '1.1.0'});
  assert.deepEqual(Object.keys(locations.installations), ['llvm', 'runtime', 'ast']);
  assert.deepEqual(locations.tools, {});
  for (const key of PROVENANCE_KEYS) assert.ok(record[key], key);
  assert.equal(record.tools_ref, pins.TOOLS_REF);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'locations.json'))), locations);
});

test('assemble fails closed on a missing installation, adapter or identity', t => {
  assert.throws(() => assembleNativeInputs({root: inputs(t, {skip: 'ast', hostTarget: 'linux-x64'}), target: 'linux-x64', env, pins}),
    /NATIVE_INPUTS_COMPONENT_MISSING ast/);
  for (const target of ['windows-x64', 'darwin-arm64', 'linux-x64'])
    assert.throws(() => assembleNativeInputs({root: inputs(t, {darwin: true, hostTarget: target}), target, env, pins}),
      /NATIVE_TOOLS_ADAPTER_UNEXPECTED/);
  assert.throws(() => prepareProvenance({...env, CJCJ_NATIVE_RUNTIME_REF: 'main'}, pins), /PREPARE_PROVENANCE native_runtime_ref/);
  assert.throws(() => assembleNativeInputs({root: inputs(t), target: 'freebsd-x64', env, pins}), /PREPARE_HOST_UNKNOWN/);
  const darwin = assembleNativeInputs({root: inputs(t, {hostTarget: 'darwin-x64'}), target: 'darwin-x64', env, pins});
  assert.deepEqual(darwin.locations.tools, {});
});

// ---- N/LLVM + AST producers on all five hosts (ruling 1) ----
const job = text => loadYaml(text).jobs['prepare-native'];
test('every prepare host runs its N/LLVM and AST producer and installs both', () => {
  assert.deepEqual(prepareComponentProblems(job(read('sdk-build-target')).steps), []);
});
test('red cut: dropping one host family\'s N/LLVM or AST step names exactly that host and component', () => {
  const cuts = [
    ['  - name: Build the pinned in-process LLVM and its tools on this Windows host\n        if: runner.os == \'Windows\'',
      '  - name: Build the pinned in-process LLVM and its tools on this Windows host\n        if: runner.os == \'Linux\'',
      ['windows-x64 lacks llvm producer build/sdk/producers/release/build_prepare_llvm.mjs']],
    ['  - name: Build AST support on this Unix host\n        if: runner.os != \'Windows\'', '  - name: Build AST support on this Unix host\n        if: runner.os == \'Linux\'',
      ['darwin-arm64 lacks ast producer ci/build_ast_support.sh', 'darwin-x64 lacks ast producer ci/build_ast_support.sh']],
    ['  - name: Build the pinned in-process LLVM and its tools on this Unix host\n        if: runner.os != \'Windows\'',
      '  - name: Build the pinned in-process LLVM and its tools on this Unix host\n        if: runner.os == \'macOS\'',
      ['linux-x64 lacks llvm producer build/sdk/producers/release/build_prepare_llvm.mjs',
        'linux-aarch64 lacks llvm producer build/sdk/producers/release/build_prepare_llvm.mjs']],
    ['install-ast \\\n', 'echo-ast \\\n', PREPARE_HOSTS.map(h => `${h.target} lacks ast producer prepare_native_inputs.mjs install-ast`)],
  ];
  for (const [from, to, want] of cuts) {
    const problems = prepareComponentProblems(job(once(read('sdk-build-target'), from, to)).steps)
      .map(p => p.replace(/^prepare-native host /, ''));
    assert.deepEqual(problems, want, from);
    assert.ok(prepareWorkflowProblems({...real(), target: once(read('sdk-build-target'), from, to)}).length >= want.length);
  }
});
test('red cut: re-adding the private adapter deployment to prepare-native is refused', () => {
  const text = once(read('sdk-build-target'), '      - name: Install N/LLVM and AST into the native input root\n',
    '      - name: Deploy adapter\n        run: node ci/bootstrap/deploy-native-tools.mjs src ref out\n      - name: Install N/LLVM and AST into the native input root\n');
  assert.ok(prepareWorkflowProblems({...real(), target: text}).includes('prepare-native consumes the retired private tools adapter'));
});

// ---- end-to-end mock layout: producer output -> native-inputs -> downstream readers ----
const LLVM = commit('1'), RUNTIME = commit('2'), COMPILER = commit('3');
function produced(t, target) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-e2e-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const native = sdkPlatform(PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), body); };
  put('llvm-out/' + native.llvmLibrary, 'llvm bytes ' + target);
  for (const tool of PREPARE_LLVM_TOOLS) put(`llvm-out/bin/${tool}${native.exe}`, `${tool} ${target}`);
  for (const rel of ['libcangjie-ast-support.a', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h',
    ...stdxChirMembers, 'third_party/flatbuffers/bin/flatc' + native.exe]) put('ast-out/' + rel, 'ast ' + rel);
  putHost(path.join(dir, 'root'), PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  put('root/runtime/NATIVE-INPUTS.json', JSON.stringify({configuration: {runtime: RUNTIME}}));
  const root = path.join(dir, 'root'), commits = {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER};
  installLlvm({root, target, from: path.join(dir, 'llvm-out'), commits, producer: 'test'});
  installAst({root, target, from: path.join(dir, 'ast-out'), commits});
  return {dir, root, native};
}
for (const host of PREPARE_HOSTS) test(`${host.target}: prepare output is read by the downstream native consumers`, async t => {
  const {root, native} = produced(t, host.target);
  const {locations} = assembleNativeInputs({root, target: host.target, hostVersion: '1.1.0', env, pins});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'locations.json'))), locations);
  // configure-gha-inputs / select-native-host: the same resolver and readers.
  const resolved = await nativeInstallationLocations(root, locations, {});
  for (const name of ['llvm', 'runtime', 'ast']) {
    assert.ok(fs.existsSync(resolved[name].buildResult), name);
    assert.ok(resolved[name].install.startsWith(root + path.sep), name);
  }
  const llvmFacts = JSON.parse(fs.readFileSync(resolved.llvm.buildResult));
  assert.equal(llvmFacts.commits.compiler, COMPILER);
  assert.equal(llvmFacts.commits.llvm, LLVM);
  assert.ok(fs.existsSync(path.join(resolved.llvm.install, 'third_party/llvm', native.llvmDirectory, native.llvmLibrary)));
  const ast = await readInstalledNativeAst({install: resolved.ast.install, buildResult: resolved.ast.buildResult,
    platform: locations.platform, commit: COMPILER, llvmCommit: LLVM});
  assert.equal(ast.library, `lib/${native.tuple}/libcangjie-ast-support.a`);
  assert.deepEqual(rejectPrivateTools(locations.tools), {});
  const provenance = JSON.parse(fs.readFileSync(path.join(root, 'PREPARE-PROVENANCE.json')));
  assert.equal(provenance.target, host.target);
});
test('red cut: downstream consumers refuse a damaged, mispaired or escaping prepare layout', async t => {
  const target = 'darwin-arm64';
  const tampered = produced(t, target);
  const {locations} = assembleNativeInputs({root: tampered.root, target, hostVersion: '1.1.0', env, pins});
  const resolved = await nativeInstallationLocations(tampered.root, locations, {});
  const read = () => readInstalledNativeAst({install: resolved.ast.install, buildResult: resolved.ast.buildResult,
    platform: locations.platform, commit: COMPILER, llvmCommit: LLVM});
  await read();
  fs.appendFileSync(path.join(resolved.ast.install, 'schema/StdAstFormat.fbs'), 'changed');
  await assert.rejects(read(), /NATIVE_AST_INSTALL_BYTES schema\/StdAstFormat\.fbs/);
  const other = produced(t, target);
  const located = assembleNativeInputs({root: other.root, target, hostVersion: '1.1.0', env, pins}).locations;
  const rows = await nativeInstallationLocations(other.root, located, {});
  await assert.rejects(readInstalledNativeAst({install: rows.ast.install, buildResult: rows.ast.buildResult,
    platform: located.platform, commit: commit('9'), llvmCommit: LLVM}), /NATIVE_AST_SOURCE_PAIR/);
  await assert.rejects(nativeInstallationLocations(other.root,
    {...located, installations: {...located.installations, ast: {...located.installations.ast, install: '../ast'}}}, {}), /INSTALL_PATH \.\.\/ast/);
  assert.throws(() => rejectPrivateTools({privateRoot: 'adapter'}), /NATIVE_TOOLS_PRIVATE_ROOT_RETIRED/);
  // A producer output that lacks a member or a commit is never installed.
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-empty-'));
  t.after(() => fs.rmSync(empty, {recursive: true, force: true}));
  assert.throws(() => installAst({root: empty, target, from: path.join(other.dir, 'llvm-out'), commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}}),
    /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING libcangjie-ast-support\.a/);
  assert.throws(() => componentCommits({PREPARE_LLVM_COMMIT: LLVM, PREPARE_RUNTIME_COMMIT: RUNTIME}), /PREPARE_COMPONENT_COMMIT compiler/);
});

// ---- host SDK: the original official archive, the consumer's pair rule ----
test('prepare host version follows the consumer pair rule and the checked-in pin', () => {
  const pinned = prepareHostVersion('linux-x64', {});
  assert.match(pinned, /^\d+\.\d+\.\d+-alpha\.\d+$/);
  assert.equal(prepareHostVersion('windows-x64', {CJCJ_NATIVE_LLVM_REF: LLVM, CJCJ_NATIVE_RUNTIME_REF: RUNTIME, CJCJ_NATIVE_HOST_VERSION: pinned}), pinned);
  assert.throws(() => prepareHostVersion('linux-x64', {CJCJ_NATIVE_LLVM_REF: LLVM, CJCJ_NATIVE_RUNTIME_REF: RUNTIME}),
    /NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED/);
  assert.throws(() => prepareHostVersion('linux-x64', {CJCJ_NATIVE_HOST_VERSION: '1.0.0-alpha.1'}), /PREPARE_HOST_VERSION_UNPINNED/);
});
test('install-host keeps only an archive with the pinned name, size and digest', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-host-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const fake = name => async (platform, work) => {
    const sdk = path.join(work, 'host-sdk-x/cangjie');
    fs.mkdirSync(path.join(sdk, 'bin'), {recursive: true}); fs.writeFileSync(path.join(sdk, 'bin/cjc'), 'h');
    fs.writeFileSync(path.join(work, name), 'not the release');
    return {path: sdk, archive: path.join(work, name), sha256: crypto.createHash('sha256').update('not the release').digest('hex')};
  };
  const root = path.join(dir, 'root'); fs.mkdirSync(root);
  await assert.rejects(installHost({root, target: 'linux-x64', env: {}, prepare: fake('host-sdk.tar')}), /PREPARE_HOST_ARCHIVE_IDENTITY/);
  assert.ok(!fs.existsSync(path.join(root, 'HOST-INPUT.json')) && !fs.existsSync(path.join(root, '.host-download')));
  fs.mkdirSync(path.join(root, 'host'));
  await assert.rejects(installHost({root, target: 'linux-x64', env: {}, prepare: fake('x')}), /NATIVE_INPUTS_COMPONENT_EXISTS host/);
});
test('assemble names the recorded original archive and refuses a changed one', t => {
  const dir = inputs(t, {hostTarget: 'linux-x64'});
  const {locations} = assembleNativeInputs({root: dir, target: 'linux-x64', env, pins});
  assert.equal(locations.host.archive, 'host-archive/cangjie-sdk-fixture-1.1.0.tar.gz');
  assert.throws(() => assembleNativeInputs({root: dir, target: 'linux-x64', hostVersion: '9.9.9', env, pins}), /PREPARE_HOST_VERSION/);
  fs.appendFileSync(path.join(dir, locations.host.archive), 'x');
  assert.throws(() => assembleNativeInputs({root: dir, target: 'linux-x64', env, pins}), /PREPARE_HOST_ARCHIVE_IDENTITY/);
  const bare = inputs(t, {hostTarget: 'linux-x64'}); fs.rmSync(path.join(bare, 'HOST-INPUT.json'));
  assert.throws(() => assembleNativeInputs({root: bare, target: 'linux-x64', env, pins}), /NATIVE_INPUTS_COMPONENT_MISSING host/);
  assert.throws(() => assembleNativeInputs({root: inputs(t, {hostTarget: 'linux-x64'}), target: 'linux-aarch64', env, pins}), /PREPARE_HOST_RECORD/);
});

// ---- transport: one tar per family keeps modes; the consumer takes only it ----
test('pack and the consumer unpack keep executable modes and refuse other layouts', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-pack-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const root = path.join(dir, 'native-inputs');
  fs.mkdirSync(path.join(root, 'host/bin'), {recursive: true});
  fs.writeFileSync(path.join(root, 'host/bin/cjc'), '#!/bin/sh\n'); fs.chmodSync(path.join(root, 'host/bin/cjc'), 0o755);
  fs.writeFileSync(path.join(root, 'locations.json'), '{}');
  const packed = packNativeInputs({root, out: path.join(dir, 'native-inputs.tar')});
  assert.throws(() => packNativeInputs({root, out: path.join(root, 'x.tar')}), /NATIVE_INPUTS_ARCHIVE_INSIDE_ROOT/);
  const download = path.join(dir, 'download'); fs.mkdirSync(download);
  fs.copyFileSync(packed.file, path.join(download, 'native-inputs.tar')); // artifact transport: bytes only
  unpackNativeArtifact({directory: download, archive: 'native-inputs.tar'});
  assert.equal(fs.statSync(path.join(download, 'host/bin/cjc')).mode & 0o111, 0o111);
  assert.ok(!fs.existsSync(path.join(download, 'native-inputs.tar')));
  const loose = path.join(dir, 'loose'); fs.mkdirSync(loose);
  fs.copyFileSync(packed.file, path.join(loose, 'native-inputs.tar')); fs.writeFileSync(path.join(loose, 'extra'), '');
  assert.throws(() => unpackNativeArtifact({directory: loose, archive: 'native-inputs.tar'}), /NATIVE_ARTIFACT_SINGLE_ARCHIVE_REQUIRED/);
  const directoryUpload = path.join(dir, 'directory-upload'); fs.cpSync(root, directoryUpload, {recursive: true});
  assert.throws(() => unpackNativeArtifact({directory: directoryUpload, archive: 'native-inputs.tar'}), /NATIVE_ARTIFACT_SINGLE_ARCHIVE_REQUIRED/);
});
test('red cut: uploading a directory instead of the tar, or a cjv host, is refused', () => {
  const dir = once(read('sdk-build-target'), '          path: ${{ runner.temp }}/native-inputs.tar\n', '          path: ${{ runner.temp }}/native-inputs\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), target: dir}), ['prepare-native uploads native-inputs-${{ matrix.target }} without native-inputs.tar']);
  const rt = once(read('sdk-build-target'), '          path: .platform-ci/runtime-install.tar\n', '          path: .platform-ci/runtime-install\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), target: rt}),
    ['prepare-native uploads native-runtime-install-${{ matrix.llvm_platform }} without runtime-install.tar']);
  const cjv = once(read('sdk-build-target'), '          cp -a .platform-ci/runtime-install "$root/runtime"\n',
    '          cp -a .platform-ci/runtime-install "$root/runtime"\n          npx --yes zx@8 ci/setup_sdk.mjs\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), target: cjv}), ['prepare-native provisions the host from an installed toolchain']);
});
test('every native-inputs consumer unpacks the tar before the host or runtime is read', () => {
  const jobs = loadYaml(read('sdk-build-target')).jobs;
  for (const name of ['source-stage0', 'native-windows-sdk']) {
    const steps = jobs[name].steps.map(step => step.name || '');
    const at = label => steps.indexOf(label);
    assert.ok(at('Unpack selected native inputs with their file modes') === at('Receive selected native inputs before choosing the host') + 1, name);
    assert.ok(at('Unpack selected native inputs with their file modes') < at('Select actual native host and freeze the same inputs'), name);
    assert.ok(at('Unpack fixed native runtime installation with its file modes') === at('Receive fixed native runtime installation') + 1, name);
  }
});

// ---- N/LLVM producer: the same dylib build with its tools on all hosts ----
test('the N/LLVM producer configures the dylib build and installs library and tools', t => {
  const args = llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', os: 'win32'});
  for (const flag of ['-DLLVM_BUILD_LLVM_DYLIB=ON', '-DLLVM_LINK_LLVM_DYLIB=OFF', '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64', '-DLLVM_ENABLE_ZLIB=OFF'])
    assert.ok(args.includes(flag), flag);
  assert.ok(!llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', os: 'linux'}).includes('-DLLVM_ENABLE_ZLIB=OFF'));
  for (const platform of ['linux_x86_64', 'windows_x86_64', 'darwin_aarch64']) {
    const native = sdkPlatform(platform), work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-'));
    t.after(() => fs.rmSync(work, {recursive: true, force: true}));
    const seen = [];
    const run = (file, argv) => { // records argv; the build step leaves the real output shape
      const all = [file, ...argv]; seen.push(all.join(' '));
      if (all[0] === 'git' && all.includes('rev-parse')) return {status: 0, stdout: LLVM + '\n'};
      if (all.includes('--jobs-only')) return {status: 0, stdout: '3\n'};
      if (all[0] === 'cmake' && all[1] === '--build') {
        const build = all[2];
        fs.mkdirSync(path.join(build, native.llvmDirectory), {recursive: true}); fs.mkdirSync(path.join(build, 'bin'), {recursive: true});
        fs.writeFileSync(path.join(build, native.llvmDirectory, native.llvmLibrary), 'lib');
        for (const tool of ['llc', 'llvm-as', 'llvm-dis', 'llvm-nm']) fs.writeFileSync(path.join(build, 'bin', tool + native.exe), tool);
      }
      if (all[0].endsWith('llvm-nm' + native.exe)) return {status: 0, stdout: '0000 T LLVMInitializeX86TargetInfo\n'};
      return {status: 0, stdout: ''};
    };
    const out = path.join(work, 'out');
    buildPrepareLlvm({platform, sha: LLVM, out, work, env: {}, run});
    assert.ok(seen.some(line => line.startsWith('cmake --build') && line.includes('LLVM llc llvm-as llvm-dis llvm-nm')), platform);
    assert.ok(fs.existsSync(path.join(out, native.llvmLibrary)));
    for (const tool of PREPARE_LLVM_TOOLS) assert.ok(fs.existsSync(path.join(out, 'bin', tool + native.exe)), tool);
    const root = path.join(work, 'root'); fs.mkdirSync(root);
    const target = PREPARE_HOSTS.find(h => h.llvm_platform === platform).target;
    const facts = installLlvm({root, target, from: out, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'llvm-dylib'});
    assert.deepEqual(Object.keys(facts.tools), PREPARE_LLVM_TOOLS.map(tool => `third_party/llvm/bin/${tool}${native.exe}`));
    // red cut: a missing tool is never installed
    fs.rmSync(path.join(out, 'bin', 'llvm-dis' + native.exe));
    assert.throws(() => installLlvm({root: path.join(work, 'root2'), target, from: out, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x'}),
      new RegExp(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING bin/llvm-dis${native.exe.replace('.', '\\.')}`));
  }
  assert.throws(() => buildPrepareLlvm({platform: 'linux_x86_64', sha: 'main', out: os.tmpdir(), env: {}, run: () => ({status: 0})}), /PREPARE_LLVM_SHA/);
});

// ---- AST compiler: the source the consumer job selects ----
test('the AST compiler source is the consumer job\'s source selection', () => {
  const pinned = fs.readFileSync(path.join(root, 'ci/source_pin.env'), 'utf8').match(/^COMPILER_REF=([0-9a-f]{40})$/m)[1];
  assert.equal(compilerSource({}).commit, pinned);
  const explicit = {CJCJ_SOURCE_SELECTION: JSON.stringify({compiler: {url: 'https://example.invalid/compiler.git', tag: commit('9')}})};
  assert.deepEqual(compilerSource(explicit), {repository: 'https://example.invalid/compiler.git', commit: commit('9')});
  assert.throws(() => compilerSource({CJCJ_SOURCE_SELECTION: JSON.stringify({compiler: {url: 'https://example.invalid/c.git', tag: 'main'}})}),
    /WORKFLOW_FIXED_SOURCE_REQUIRED compiler/);
});
