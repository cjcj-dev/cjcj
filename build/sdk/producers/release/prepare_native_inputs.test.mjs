// phase=prepare: five native hosts, both artifact families, no route to publish,
// and native-inputs roots that bind their real installations and provenance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {PREPARE_HOSTS, PROVENANCE_KEYS, assembleNativeInputs, prepareProvenance, prepareWorkflowProblems,
  installLlvm, installAst, componentCommits, prepareComponentProblems} from './prepare_native_inputs.mjs';
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
const env = {GITHUB_SHA: commit('a'), GITHUB_RUN_ID: '4242', GITHUB_RUN_ATTEMPT: '1',
  CJCJ_NATIVE_LLVM_REF: commit('b'), CJCJ_NATIVE_RUNTIME_REF: commit('c')};
const pins = {COMPILER_REF: commit('d'), TOOLS_REF: commit('e'), STDX_REF: commit('f')};
function inputs(t, {darwin = false, skip} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-inputs-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), body); };
  put('host/bin/cjc', 'host');
  for (const [name, file] of [['llvm', 'BUILD-INPUTS.json'], ['runtime', 'NATIVE-INPUTS.json'], ['ast', 'BUILD-INPUTS.json']])
    if (name !== skip) put(`${name}/${file}`, JSON.stringify({configuration: {name}}));
  if (darwin) for (const rel of ['ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']) put('adapter/' + rel, '//');
  return dir;
}

test('assemble binds the real installations and every provenance identity', t => {
  const dir = inputs(t);
  const {locations, record} = assembleNativeInputs({root: dir, target: 'linux-aarch64', hostVersion: '1.0.0', env, pins});
  assert.equal(locations.platform, 'linux_aarch64');
  assert.deepEqual(Object.keys(locations.installations), ['llvm', 'runtime', 'ast']);
  assert.deepEqual(locations.tools, {});
  for (const key of PROVENANCE_KEYS) assert.ok(record[key], key);
  assert.equal(record.tools_ref, pins.TOOLS_REF);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'locations.json'))), locations);
});

test('assemble fails closed on a missing installation, adapter or identity', t => {
  assert.throws(() => assembleNativeInputs({root: inputs(t, {skip: 'ast'}), target: 'linux-x64', hostVersion: '1', env, pins}),
    /NATIVE_INPUTS_COMPONENT_MISSING ast/);
  for (const target of ['windows-x64', 'darwin-arm64', 'linux-x64'])
    assert.throws(() => assembleNativeInputs({root: inputs(t, {darwin: true}), target, hostVersion: '1', env, pins}),
      /NATIVE_TOOLS_ADAPTER_UNEXPECTED/);
  assert.throws(() => prepareProvenance({...env, CJCJ_NATIVE_RUNTIME_REF: 'main'}, pins), /PREPARE_PROVENANCE native_runtime_ref/);
  assert.throws(() => assembleNativeInputs({root: inputs(t), target: 'freebsd-x64', hostVersion: '1', env, pins}), /PREPARE_HOST_UNKNOWN/);
  const darwin = assembleNativeInputs({root: inputs(t), target: 'darwin-x64', hostVersion: '1', env, pins});
  assert.deepEqual(darwin.locations.tools, {});
});

// ---- N/LLVM + AST producers on all five hosts (ruling 1) ----
const job = text => loadYaml(text).jobs['prepare-native'];
test('every prepare host runs its N/LLVM and AST producer and installs both', () => {
  assert.deepEqual(prepareComponentProblems(job(read('sdk-build-target')).steps), []);
});
test('red cut: dropping one host family\'s N/LLVM or AST step names exactly that host and component', () => {
  const cuts = [
    ['  - name: Build the Windows LLVM tuple on this host\n        if: runner.os == \'Windows\'', '  - name: Build the Windows LLVM tuple on this host\n        if: runner.os == \'Linux\'',
      ['windows-x64 lacks llvm producer build/sdk/producers/platform_tuples/fetch_sources.mjs', 'windows-x64 lacks llvm producer build/sdk/producers/platform_tuples/build_tuple.mjs']],
    ['  - name: Build AST support on this Unix host\n        if: runner.os != \'Windows\'', '  - name: Build AST support on this Unix host\n        if: runner.os == \'Linux\'',
      ['darwin-arm64 lacks ast producer ci/build_ast_support.sh', 'darwin-x64 lacks ast producer ci/build_ast_support.sh']],
    ['  - name: Build the pinned in-process LLVM library on this Unix host\n        if: runner.os != \'Windows\'',
      '  - name: Build the pinned in-process LLVM library on this Unix host\n        if: runner.os == \'macOS\'',
      ['linux-x64 lacks llvm producer ci/fetch-llvm-runtime.mjs', 'linux-x64 lacks llvm producer -DLLVM_BUILD_LLVM_DYLIB=ON',
        'linux-aarch64 lacks llvm producer ci/fetch-llvm-runtime.mjs', 'linux-aarch64 lacks llvm producer -DLLVM_BUILD_LLVM_DYLIB=ON']],
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
  for (const rel of ['libcangjie-ast-support.a', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h',
    ...stdxChirMembers, 'third_party/flatbuffers/bin/flatc' + native.exe]) put('ast-out/' + rel, 'ast ' + rel);
  put('root/host/bin/cjc', 'host'); put('root/host-archive/host-sdk.tar', 'tar');
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
