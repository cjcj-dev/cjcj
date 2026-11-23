import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {STAGES, layout} from '../bootstrap.mjs';
import {createRunner} from '../run.mjs';
import {installSdk, installDescriptor} from '../install.mjs';
import {parseArgs, readConfig} from '../cli.mjs';
import {checkTools, TOOL_NAMES} from '../tools.mjs';
import {readNativeBinding} from '../native.mjs';
import {makeSdk} from './fixture.mjs';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-pipeline-'));

test('pipeline: the self-hosting chain is Stage0 -> Stage2 -> final std -> Stage3 -> install', () => {
  assert.deepEqual(STAGES, ['runtime-input', 'ast-input', 'stage2-bootstrap', 'stage2', 'std-generator', 'stdlib', 'stage3-generator', 'stage3', 'install']);
  const l = layout('/w');
  assert.equal(l.sdk, '/w/cangjie');
  assert.equal(new Set(Object.values(l)).size, Object.keys(l).length);
});

test('pipeline: the runner records the process own rc and fails the step on non-zero', () => {
  const evidence = tmp(), runner = createRunner({evidence});
  assert.equal(runner.run('ok', [process.execPath, '-e', 'process.exit(0)']).rc, 0);
  assert.throws(() => runner.run('bad', [process.execPath, '-e', 'process.exit(7)']), /^Error: STEP_FAILED bad rc=7/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(evidence, 'bad.result.json'), 'utf8')).rc, 7);
  assert.throws(() => runner.run('a b', ['true']), /^Error: RUN_LABEL/);
});

test('install: a failed installer leaves no half product behind', async () => {
  const work = tmp(), evidence = tmp(), install = path.join(work, 'cangjie');
  const runner = {run() { fs.mkdirSync(install, {recursive: true}); fs.writeFileSync(path.join(install, 'partial'), 'x'); throw new Error('STEP_FAILED 09-install rc=1'); }};
  const descriptor = installDescriptor({label: '09-install', work, install, selection: {}, tools: {}, production: {}});
  await assert.rejects(installSdk({runner, label: '09-install', descriptor, evidence, cli: '/cli.mjs'}), /STEP_FAILED 09-install/);
  assert.equal(fs.existsSync(install), false);
  assert.ok(fs.existsSync(path.join(evidence, '09-install.descriptor.json')));
});

test('install: the final install must pass the role-layout check; an existing destination is refused', async () => {
  const {root, sdk} = makeSdk({host: null}), evidence = tmp();
  fs.renameSync(sdk, path.join(root, 'staged'));
  const runner = {run() { fs.renameSync(path.join(root, 'staged'), sdk); }};
  const descriptor = installDescriptor({label: '09-install', work: root, install: sdk, selection: {}, tools: {}, production: {}});
  await assert.rejects(installSdk({runner, label: '09-install', descriptor, evidence, cli: '/cli.mjs', finalAsset: 'linux-x64'}), /^Error: SDK_MISSING_HOST_RUNTIME$/);
  assert.equal(fs.existsSync(sdk), false);
  fs.mkdirSync(sdk);
  await assert.rejects(installSdk({runner, label: '09-install', descriptor, evidence, cli: '/cli.mjs'}), /^Error: INSTALL_DESTINATION_EXISTS/);
});

test('native: a mixed-generation LLVM/runtime pair is refused', () => {
  const dir = tmp(), native = path.join(dir, 'n'), runtime = path.join(dir, 'r');
  fs.mkdirSync(native); fs.mkdirSync(runtime);
  const commits = {llvm: 'l'.repeat(40), runtime: 'r'.repeat(40), cjcj: 'c'.repeat(40), ast: 'a'.repeat(40)};
  fs.writeFileSync(path.join(native, 'BUILD-INPUTS.json'), JSON.stringify({commits: {llvm: commits.llvm, runtime: commits.runtime, shim: commits.cjcj, compiler: commits.ast}}));
  fs.writeFileSync(path.join(runtime, 'NATIVE-INPUTS.json'), JSON.stringify({runtime_sha: commits.runtime, paired_llvm_sha: commits.llvm, configuration: {hostVersion: 'h'}}));
  assert.ok(readNativeBinding({nativeInstall: native, runtimeInstall: runtime, commits, hostVersion: 'h'}));
  fs.writeFileSync(path.join(runtime, 'NATIVE-INPUTS.json'), JSON.stringify({runtime_sha: commits.runtime, paired_llvm_sha: 'x'.repeat(40), configuration: {hostVersion: 'h'}}));
  assert.throws(() => readNativeBinding({nativeInstall: native, runtimeInstall: runtime, commits, hostVersion: 'h'}), /^Error: NATIVE_MIXED_GENERATION 5/);
});

test('tools: exactly the 10 tools from the pinned tools commit', () => {
  const commit = '3460b1e55a16414f52385663ba780fb4ed07ee65';
  const row = {producer: {source: {commit}, build: {rc: 0}, install: {rc: 0}}};
  const files = Object.fromEntries(TOOL_NAMES.map(n => [n, row]));
  assert.equal(checkTools({files}, commit), 10);
  assert.throws(() => checkTools({files: {...files, extra: row}}, commit), /^Error: TOOLS_COUNT 11/);
  assert.throws(() => checkTools({files: {...files, cjpm: {producer: {...row.producer, build: {rc: 1}}}}}, commit), /^Error: TOOLS_PRODUCER/);
});

test('cli: arguments and config are validated against the pins', () => {
  assert.deepEqual(parseArgs(['plan', '--asset', 'linux-x64']), {command: 'plan', options: {asset: 'linux-x64'}});
  assert.throws(() => parseArgs(['deploy']), /^Error: SDK_COMMAND deploy/);
  assert.throws(() => parseArgs(['build', '--config']), /^Error: SDK_ARGS --config/);
  const dir = tmp(), file = path.join(dir, 'c.json');
  const base = {work: dir, evidence: dir, cjcj: dir, platform: 'linux_x86_64', asset: 'linux-x64', nativeInstall: dir, runtimeInstall: dir,
    seedInputs: dir, sources: {}, env: {}, commits: {runtime: 'e5060a7bf96a50c7e7b65eac2a3a029f65db9a07', llvm: 'eb7ad0120f43f802fbc60615e6c6f068183fffe3',
      ast: '41b22350b8eb5b0c8244704f906b7b8d3096eb9c', tools: '3460b1e55a16414f52385663ba780fb4ed07ee65', stdx: '76c9da37332d5ec2f82fedaf6c0a3793d3200e2c'}};
  fs.writeFileSync(file, JSON.stringify(base));
  assert.equal(readConfig(file).asset, 'linux-x64');
  fs.writeFileSync(file, JSON.stringify({...base, commits: {...base.commits, stdx: 'b10784b27a5b3f815c9542d28f3ba02f48db48d5'}}));
  assert.throws(() => readConfig(file), /^Error: SDK_CONFIG_PIN stdx/);
  fs.writeFileSync(file, JSON.stringify({...base, asset: 'linux-mips'}));
  assert.throws(() => readConfig(file), /^Error: UNKNOWN_ASSET linux-mips/);
});
