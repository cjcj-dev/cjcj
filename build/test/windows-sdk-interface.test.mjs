import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {getBuildTarget} from '../lib/build-target.mjs';
import {packageConsumption} from '../../ci/srcbuild/lib/package-install.mjs';
import {createBootstrapTargets, validateBootstrapTargets, FIXED_INPUTS} from '../../ci/bootstrap/sdk-targets.mjs';
import {targetOrder} from '../../ci/bootstrap/sdk-flow.mjs';

test('package consumes native Windows but retains cross NOT_RUN independently', () => {
  assert.deepEqual(packageConsumption(getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64'})),
    {status: 'EXECUTED', platform: 'windows_x86_64'});
  assert.deepEqual(packageConsumption(getBuildTarget('windows-x64', {platform: 'linux', arch: 'x64'})),
    {status: 'NOT_RUN', reason: 'HOST_CROSS_EXEC', platform: 'windows_x86_64'});
});
test('existing SDK graph carries explicit Ndb51/R79b native Windows sources to C3 installation', () => {
  // Configuration fixture, never handed to an actual native build.
  const row = (commit, name) => ({commit, tree: 'a'.repeat(40), repository: '/fixture/' + name + '.git',
    install: '/fixture/' + name, configuration: {fixture: true}, buildResult: '/fixture/' + name + '/result.json'});
  const llvmCommit = 'db51a4c7ebb6903e9f997d3b35d52f3577810385';
  const runtimeCommit = '79b34798d0f4696f9fe5a3708981539466ecd35b';
  const astCommit = 'f07c55738c12c154160c313c630a42a73a51025d';
  const runtime = row(runtimeCommit, 'R');
  const inputs = {platform: 'windows_x86_64', work: '/fixture/work', install: '/fixture/install',
    llvmCommit, runtimeCommit, astCommit, host: {version: '1.3.0-alpha.20260925001050', install: '/fixture/H'},
    llvm: row(llvmCommit, 'N'), runtime, stdlib: {...runtime}, ast: row(astCommit, 'AST'),
    h1: row(FIXED_INPUTS.h1, 'H1'), compiler: row('b'.repeat(40), 'C'), tools: {privateRoot: '/fixture/tools', launcher: 'sccache'}};
  const graph = createBootstrapTargets(inputs);
  validateBootstrapTargets(graph);
  const order = targetOrder(graph.stages, graph.finalStage);
  assert.equal(graph.finalStage, 'stage3');
  assert.ok(order.length > 8);
  assert.equal(graph.repos.std1.commit, runtimeCommit);
  assert.equal(graph.stages.find(s => s.id === 'nativeAST').reuse.commit, astCommit);
  assert.throws(() => createBootstrapTargets({...inputs, ast: row(FIXED_INPUTS.compiler, 'AST')}), /TARGET_SOURCE ast/);
  assert.throws(() => createBootstrapTargets({...inputs, astCommit: 'HEAD'}), /TARGET_SOURCE ast/);
  validateBootstrapTargets(createBootstrapTargets({...inputs, astCommit: undefined, ast: row(FIXED_INPUTS.compiler, 'AST')}));
  const final = graph.stages.find(s => s.id === 'stage3');
  assert.equal(final.output, '${install}');
  assert.ok(final.copies.some(c => c.from === '/fixture/N/third_party/llvm'));
  assert.ok(final.entries.some(g => g.names?.includes('cjcj-stage1.exe')));
});
test('public bootstrap preparation rejects a foreign Windows descriptor before native work', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'windows-sdk-interface-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const descriptor = path.join(root, 'input.json');
  fs.writeFileSync(descriptor, JSON.stringify({platform: 'windows_x86_64'}));
  const r = spawnSync(process.execPath, ['ci/bootstrap/prepare-bootstrap-plans.mjs'], {
    cwd: path.resolve(import.meta.dirname, '../..'), encoding: 'utf8', timeout: 30000,
    env: {...process.env, CJCJ_SDK_TARGETS: '', CJCJ_SDK_INPUTS: '', CJCJ_NATIVE_INPUTS: descriptor, CANGJIE_WORKSPACE: root}});
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /NATIVE_RUNNER_REQUIRED windows_x86_64/);
  assert.equal(fs.existsSync(path.join(root, 'build-targets.json')), false);
});
