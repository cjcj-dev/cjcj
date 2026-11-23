// phase=prepare: five native hosts, both artifact families, no route to publish,
// and native-inputs roots that bind their real installations and provenance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {PREPARE_HOSTS, PROVENANCE_KEYS, assembleNativeInputs, prepareProvenance, prepareWorkflowProblems}
  from './prepare_native_inputs.mjs';
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
  assert.throws(() => assembleNativeInputs({root: inputs(t), target: 'darwin-arm64', hostVersion: '1', env, pins}),
    /NATIVE_TOOLS_ADAPTER_MISSING ts\/src\/sharedbuild\/cjcj-stage1\.mjs/);
  assert.throws(() => assembleNativeInputs({root: inputs(t, {darwin: true}), target: 'windows-x64', hostVersion: '1', env, pins}),
    /NATIVE_TOOLS_ADAPTER_UNEXPECTED/);
  assert.throws(() => prepareProvenance({...env, CJCJ_NATIVE_RUNTIME_REF: 'main'}, pins), /PREPARE_PROVENANCE native_runtime_ref/);
  assert.throws(() => assembleNativeInputs({root: inputs(t), target: 'freebsd-x64', hostVersion: '1', env, pins}), /PREPARE_HOST_UNKNOWN/);
  const darwin = assembleNativeInputs({root: inputs(t, {darwin: true}), target: 'darwin-x64', hostVersion: '1', env, pins});
  assert.deepEqual(darwin.locations.tools, {privateRoot: 'adapter'});
});
