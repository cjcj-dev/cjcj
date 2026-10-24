import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {createBootstrapTargets, FIXED_INPUTS} from './bootstrap/sdk-targets.mjs';
import {hostPlatform, readHostToolchainPin} from './host-toolchain-pin.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const parent = process.env.RELEASE_EVIDENCE_TEST_ROOT;
if (!parent) throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
async function fixture() {
  await fs.mkdir(parent, {recursive: true});
  const root = await fs.mkdtemp(path.join(parent, 'colour-sdk-'));
  await fs.mkdir(path.join(root, 'ci'));
  await fs.mkdir(path.join(root, '.platform-ci'));
  for (const file of ['prepare-colour-sdk.mjs', 'with-colour-sdk.mjs']) {
    const bytes = await fs.readFile(path.join(repo, 'ci', file));
    await fs.writeFile(path.join(root, 'ci', file), bytes);
    console.log(`PRODUCT ${file} sha256=${digest(bytes)}`);
  }
  // Dependencies are the real production modules, read-only in this apparatus.
  for (const name of ['bootstrap', 'srcbuild', 'host-toolchain-pin.mjs'])
    await fs.symlink(path.join(repo, 'ci', name), path.join(root, 'ci', name));
  const platform = hostPlatform(), tuple = platform + '_cjnative';
  const state = {sdk: path.join(root, 'target'), platform, tuple,
    runtime_sha: FIXED_INPUTS.runtime, stage: 'stage2-target-sdk', compiler_sha256: digest('compiler fixture')};
  state.host = path.join(state.sdk, '.host');
  state.runtime = path.join(state.sdk, 'runtime/lib', tuple);
  await fs.mkdir(path.join(state.sdk, 'libexec/compiler'), {recursive: true});
  await fs.writeFile(path.join(state.sdk, 'libexec/compiler/cjc'), 'compiler fixture');
  await fs.writeFile(path.join(state.sdk, 'STAGE-INPUTS.json'), JSON.stringify({phase: state.stage, platform,
    runtimeCommit: state.runtime_sha, compilerFile: 'libexec/compiler/cjc', compilerSha256: state.compiler_sha256}));
  await fs.writeFile(path.join(root, '.platform-ci/colour-sdk.json'), JSON.stringify(state));
  const env = {...process.env, RUNTIME_REF: state.runtime_sha, LD_LIBRARY_PATH: '/unrelated-inherited-runtime'};
  const run = (entry, args = [], extra = {}) => {
    const result = spawnSync(process.execPath, [path.join(root, 'ci', entry), ...args], {encoding: 'utf8', env: {...env, ...extra}});
    console.log(`ENTRY ${entry} rc=${result.status} signal=${result.signal}`);
    return result;
  };
  return {root, state, run};
}
for (const mode of ['build', 'run']) {
  test(`real ${mode} wrapper selects the installed native target domain`, async () => {
    const {state, run} = await fixture();
    const result = run('with-colour-sdk.mjs', [mode, '--', process.execPath, '-e', 'console.log(JSON.stringify(process.env))']);
    assert.equal(result.status, 0, result.stderr);
    const child = JSON.parse(result.stdout);
    assert.equal(child.CANGJIE_HOME, state.sdk);
    assert.equal(child.CJCJ_HOST_SDK, state.host);
    assert.equal(child.CJCJ_TARGET_SDK, state.sdk);
    assert.equal(child.CJCJ_PATCHED_LLVM_BIN, path.join(state.sdk, 'third_party/llvm/bin'));
    assert.equal(child.CJCJ_LLVM_SHIM_O, path.join(state.sdk, 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o'));
    assert.equal(child.CJCJ_LLVM_LINK_RSP, '');
    console.log(`TARGET_ASSERT mode=${mode} loader=${child.LD_LIBRARY_PATH}`);
    assert.equal(child.LD_LIBRARY_PATH.split(':')[0], state.runtime, 'selected native target loader domain');
    assert.equal(child.LD_LIBRARY_PATH.includes('/unrelated-inherited-runtime'), false);
    assert.equal(child.CJCJ_PATCHED_RUNTIME_LIB_DIR, state.runtime);
    assert.equal(child.PATH.split(':')[0], path.join(state.sdk, 'bin'));
  });
}
test('real wrapper rejects replaced installed compiler bytes and recovers', async () => {
  const {state, run} = await fixture();
  const command = ['run', '--', process.execPath, '-e', 'console.log("CONSUMER_REACHED")'];
  const compiler = path.join(state.sdk, 'libexec/compiler/cjc');
  await fs.writeFile(compiler, 'different compiler fixture');
  const bad = run('with-colour-sdk.mjs', command);
  console.log(`TARGET_ASSERT changed compiler rc=${bad.status}`);
  assert.notEqual(bad.status, 0); assert.match(bad.stderr, /installed compiler differs/);
  assert.doesNotMatch(bad.stdout, /CONSUMER_REACHED/);
  await fs.writeFile(compiler, 'compiler fixture');
  const restored = run('with-colour-sdk.mjs', command);
  assert.equal(restored.status, 0, restored.stderr); assert.match(restored.stdout, /CONSUMER_REACHED/);
});
test('real wrapper retains child exit status and rejects a different runtime pin', async () => {
  const {run} = await fixture();
  const command = ['build', '--', process.execPath, '-e', 'process.exit(7)'];
  assert.equal(run('with-colour-sdk.mjs', command).status, 7);
  const bad = run('with-colour-sdk.mjs', command, {RUNTIME_REF: 'c'.repeat(40)});
  assert.equal(bad.status, 1); assert.match(bad.stderr, /COLOUR_RT_STATE_MISMATCH/);
});
test('real preparation rejects a different configured runtime before invoking native targets', async () => {
  const {root, state, run} = await fixture();
  const row = (commit, name) => ({commit, tree: 'a'.repeat(40), repository: root+'/'+name+'.git',
    install: root+'/'+name, configuration: {fixture: true}, buildResult: root+'/'+name+'/result.json'});
  const runtime = row(FIXED_INPUTS.runtime, 'runtime');
  const config = createBootstrapTargets({platform: state.platform, work: root+'/work', install: state.sdk,
    host: {install: root+'/H', version: readHostToolchainPin(state.platform).replace(/^nightly-/, '')},
    llvm: row(FIXED_INPUTS.llvm, 'llvm'), runtime, ast: row(FIXED_INPUTS.compiler, 'ast'),
    h1: row(FIXED_INPUTS.h1, 'h1'), compiler: row('b'.repeat(40), 'compiler'), stdlib: {...runtime}, tools: {privateRoot: root+'/tools'}});
  const file = root+'/targets.json'; await fs.writeFile(file, JSON.stringify(config));
  const result = run('prepare-colour-sdk.mjs', [], {CJCJ_SDK_TARGETS: file, RUNTIME_REF: 'c'.repeat(40)});
  console.log(`TARGET_ASSERT configured runtime rc=${result.status}`);
  assert.equal(result.status, 1); assert.match(result.stderr, /COLOUR_RT_STATE_MISMATCH/);
  assert.equal(await fs.stat(root+'/work').then(() => true, () => false), false);
});
test('real preparation requires native producer locations when no explicit plan is supplied', async () => {
  const {run} = await fixture();
  const result = run('prepare-colour-sdk.mjs', [], {CJCJ_SDK_TARGETS: '', CJCJ_SDK_INPUTS: '', CJCJ_NATIVE_INPUTS: '', CJCJ_NATIVE_INPUT_ROOT: ''});
  assert.equal(result.status, 1); assert.match(result.stderr, /GHA_NATIVE_LOCATIONS_REQUIRED/);
});
