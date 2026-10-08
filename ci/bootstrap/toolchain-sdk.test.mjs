import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {PLAN_SCHEMA, validatePlan, buildIdentities, objectId, readJson, atomicJson, fileDigest,
  execute, ROLES} from './sdk-manifest.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const product = process.env.SDK_MANIFEST_PRODUCT || path.join(here, 'toolchain-sdk.mjs');
const engine = process.env.SDK_SHAREDBUILD_ENGINE;
const testRoot = process.env.SDK_MANIFEST_TEST_ROOT;
const tuple = 'linux_x86_64_cjnative';
const command = async argv => {
  try { return {rc: 0, ...(await execute(argv[0], argv.slice(1), {maxBuffer: 8 * 1024 * 1024}))}; }
  catch (error) { return {rc: error.code, stdout: error.stdout || '', stderr: error.stderr || '', error: error.message}; }
};
const write = async (file, content) => { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, content); };
const clone = value => structuredClone(value);
const fixtureSources = {
  'runtime.c': '#ifndef CJRT_SHA\n#define CJRT_SHA "official"\n#endif\nconst char provenance[]="CJRT-COMMIT:" CJRT_SHA; int official_symbol=1;\n#ifdef FIXTURE_COLOUR\nint g_cjLoadBadMask=1;\n#endif\n',
  'boundscheck.c': 'int boundscheck_fixture(void){return 0;}\n',
  'std.c': '#ifdef FIXTURE_COLOUR\nextern int g_cjLoadBadMask; int std_fixture(void){return g_cjLoadBadMask;}\n#else\nint std_fixture(void){return 0;}\n#endif\n',
  'tool.c': '#include <stdio.h>\n#ifndef CJLLVM_SHA\n#define CJLLVM_SHA "official"\n#endif\nconst char llvm_origin[]="CJLLVM-COMMIT:" CJLLVM_SHA; int main(void){puts("fixture tool version 1"); return 0;}\n',
  'llvm.c': '#include <stdlib.h>\n#ifndef CJLLVM_SHA\n#define CJLLVM_SHA "official"\n#endif\nconst char llvm_origin[]="CJLLVM-COMMIT:" CJLLVM_SHA;\n' +
    ['X86', 'ARM', 'AArch64'].flatMap(target => ['TargetInfo', 'Target', 'TargetMC', 'AsmPrinter', 'AsmParser'].map(part => `void LLVMInitialize${target}${part}(void){}\n`)).join('') +
    'void *LLVMContextCreate(void){return malloc(1);} void LLVMContextDispose(void *p){free(p);}\n',
};
async function sourceRepository(root, name) {
  const repo = path.join(root, name); await fs.mkdir(repo);
  for (const [rel, content] of Object.entries(fixtureSources)) await write(path.join(repo, rel), content);
  await write(path.join(repo, 'identity.txt'), name);
  for (const args of [['init', '-q', repo], ['-C', repo, 'add', '.'], ['-C', repo, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture input']]) {
    const result = await command(['git', ...args]); assert.equal(result.rc, 0, result.stderr);
  }
  return {kind: 'git', repo, commit: (await execute('git', ['-C', repo, 'rev-parse', 'HEAD'])).stdout.trim(),
    tree: (await execute('git', ['-C', repo, 'rev-parse', 'HEAD^{tree}'])).stdout.trim()};
}
async function fixture() {
  assert.ok(engine && testRoot, 'SDK_SHAREDBUILD_ENGINE and SDK_MANIFEST_TEST_ROOT must name remote isolated inputs');
  const root = await fs.mkdtemp(path.join(testRoot, 'sdk-manifest-'));
  const sources = {};
  for (const name of ['runtime', 'compiler', 'llvm', 'std']) sources[name] = await sourceRepository(root, name);
  const native = path.join(root, 'native'); await fs.mkdir(native);
  const official = path.join(root, 'official');
  for (const rel of ['bin/cjc', 'bin/cjc-frontend', 'tools/bin/cjpm', 'third_party/llvm/bin/llc', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/ld.lld']) {
    const target = path.join(official, rel); await fs.mkdir(path.dirname(target), {recursive: true});
    const result = await command(['cc', path.join(sources.compiler.repo, 'tool.c'), '-o', target]); assert.equal(result.rc, 0, result.stderr);
  }
  for (const [src, rel] of [['runtime.c', `runtime/lib/${tuple}/libcangjie-runtime.so`], ['boundscheck.c', `runtime/lib/${tuple}/libboundscheck.so`],
    ['std.c', `runtime/lib/${tuple}/libcangjie-std-core.so`], ['llvm.c', 'third_party/llvm/lib/libLLVM-15.so']]) {
    const target = path.join(official, rel); await fs.mkdir(path.dirname(target), {recursive: true});
    const result = await command(['cc', '-shared', '-fPIC', path.join(sources.runtime.repo, src), '-o', target]); assert.equal(result.rc, 0, result.stderr);
  }
  assert.equal((await command(['cc', '-c', path.join(sources.std.repo, 'std.c'), '-o', path.join(native, 'std.o')])).rc, 0);
  await fs.mkdir(path.join(official, 'lib', tuple), {recursive: true});
  assert.equal((await command(['ar', 'rcs', path.join(official, 'lib', tuple, 'libcangjie-std-core.a'), path.join(native, 'std.o')])).rc, 0);
  await write(path.join(official, 'lib', tuple, 'libcangjie-ast-support.a'), 'official AST fixture archive');
  await write(path.join(official, 'modules', tuple, 'std/core/core.Int64.ti'), 'official module');
  await write(path.join(official, 'envsetup.sh'), 'export CANGJIE_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nexport PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$CANGJIE_HOME/third_party/llvm/bin:$PATH"\nexport LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/tools/lib"\n');
  const seedResult = await command(['python3', engine, '--remote', '--root', path.join(root, 'seed-cache'), '--lane', 'sdk-fixture', 'sdk-publish', '--source', official, '--version', 'fixture-official']);
  assert.equal(seedResult.rc, 0, seedResult.stderr);
  const seed = seedResult.stdout.trim(), seedLock = path.join(seed, 'SDK.lock.json');
  const colour = path.join(native, 'colour.so');
  assert.equal((await command(['cc', '-shared', '-fPIC', '-DFIXTURE_COLOUR=1', path.join(sources.runtime.repo, 'runtime.c'), '-o', colour])).rc, 0);
  const pin = path.join(root, 'runtime.env'); await write(pin, `RUNTIME_REF=${sources.runtime.commit}\n`);
  const builder = path.join(here, 'fixtures/sdk-fixture-producer.mjs');
  const producerVersion = (await execute('git', ['-C', path.dirname(engine), 'rev-parse', 'HEAD'])).stdout.trim();
  const producerRoot = (await execute('git', ['-C', path.dirname(engine), 'rev-parse', '--show-toplevel'])).stdout.trim();
  const frozenTools = {};
  for (const name of ['python3', 'node', 'git', 'bash', 'tar', 'cmake', 'clang', 'clang++', 'cc', 'ar']) {
    const location = (await execute('sh', ['-c', 'command -v "$1"', 'fixture-tool', name])).stdout.trim();
    frozenTools[name] = {path: path.resolve(location), sha256: await fileDigest(location)};
  }
  const plan = {schema: PLAN_SCHEMA, lane: 'sym_cjcj_918_implement_r6061418558', role: 'target', stage: 'stage1', platform: 'linux_x86_64', buildRoot: path.join(root, 'builds'),
    verification: {runtimePin: {path: pin, sha256: await fileDigest(pin)}, colourRuntime: {path: colour, sha256: await fileDigest(colour)},
      hostRuntime: {path: path.join(seed, `runtime/lib/${tuple}/libcangjie-runtime.so`), sha256: await fileDigest(path.join(seed, `runtime/lib/${tuple}/libcangjie-runtime.so`))},
      hostRuntimeDir: path.join(seed, 'runtime/lib', tuple)}, components: []};
  const retained = {id: 'official', roles: ['ast', 'cjpm', 'official-host'], domain: 'host', source: {kind: 'distribution',
    root: seed, lock: seedLock, version: 'fixture-official', lockSha256: await fileDigest(seedLock), reason: 'explicit native fixture official host retention'},
    config: {host: plan.platform, target: plan.platform, options: {}, tools: {}}, producer: {adapter: 'official', version: producerVersion}, dependencies: [],
    install: [{from: '', to: '', exclude: ['bin', 'lib', 'runtime', 'modules', 'third_party']},
      {from: `lib/${tuple}/libcangjie-ast-support.a`, to: `lib/${tuple}/libcangjie-ast-support.a`}]};
  plan.components.push(retained);
  for (const [id, roles, source, mode, dependencies, install] of [
    ['runtime', ['runtime', 'boundscheck'], sources.runtime, 'runtime', ['official'], [{from: 'install', to: ''}]],
    ['compiler', ['compiler'], sources.compiler, 'compiler', ['official'], [{from: 'bin', to: 'bin'}, {from: 'compiler-lineage.json', to: 'compiler-lineage.json'}]],
    ['llvm-tools', ['llvm-tools'], sources.llvm, 'llvm-tools', ['official', 'runtime'], [{from: '', to: 'third_party/llvm'}]],
    ['llvm-dylib', ['llvm-dylib'], sources.llvm, 'llvm-dylib', ['official', 'runtime'], [{from: '', to: 'third_party/llvm/lib'}]],
    ['std', ['std'], sources.std, 'std', ['official', 'compiler', 'runtime'], [{from: '', to: ''}]],
  ]) {
    const recipe = path.join(root, `${id}.recipe.json`);
    const expectedOutputs = {'runtime': [`install/runtime/lib/${tuple}/libcangjie-runtime.so`], compiler: ['cjcj-stage1'],
      'llvm-tools': ['bin/opt'], 'llvm-dylib': ['libLLVM-15.so'], std: ['std-producer.json']}[id];
    plan.components.push({id, roles, domain: 'target', source, config: {host: plan.platform, target: plan.platform,
      options: {parameters: {mode}, optimization: 'Release', sdkDependency: 'official', jobs: os.availableParallelism(), heap: '32GB',
        inputBindings: id === 'std' ? {compiler: {dependency: 'compiler', artifact: 'bin/cjcj-stage1'}} : {}, outputs: expectedOutputs},
      tools: {...frozenTools, ...(id === 'compiler' ? {compilerIdentity: {path: path.join(here, 'compiler_identity.py'), sha256: await fileDigest(path.join(here, 'compiler_identity.py'))}} : {}), builder: {path: builder, sha256: await fileDigest(builder)}}},
      producer: {adapter: 'sharedbuild-runtime-default', version: producerVersion, repository: producerRoot, engine, engineSha256: await fileDigest(engine), recipe}, dependencies, install});
  }
  const identities = buildIdentities(plan);
  const planFile = path.join(root, 'plan.json'); await atomicJson(planFile, plan);
  return {root, plan, planFile, identities, out: path.join(root, 'sdk'), sources};
}
async function invoke(f, args = []) { await atomicJson(f.planFile, f.plan); return command([process.execPath, product, '--plan', f.planFile, '--out', f.out, ...args]); }
function observed(result, label) { console.log(`TARGET_ASSERTION_EXECUTED ${label} rc=${result.rc}`); }

test('actual CLI dry-run resolves complete full-SHA/config/dependency directories without building', async () => {
  const f = await fixture(); const result = await invoke(f, ['--dry-run']); observed(result, 'dry-run');
  assert.equal(result.rc, 0, result.stderr); const data = JSON.parse(result.stdout.trim());
  assert.ok(data.components.every(value => value.directory.includes(f.plan.components.find(component => component.id === value.component).source.commit || f.plan.components[0].source.lockSha256)));
  await assert.rejects(fs.access(f.plan.buildRoot)); await assert.rejects(fs.access(f.out));
  const changed = clone(f.plan); changed.components[1].config.options.parameters.extra = 'different';
  assert.notEqual(buildIdentities(changed).get('runtime').directory, f.identities.get('runtime').directory);
  const relocated = clone(f.plan); relocated.buildRoot = path.join(f.root, 'other-build-root');
  assert.notEqual(buildIdentities(relocated).get('runtime').recipeId, f.identities.get('runtime').recipeId);
});
test('actual SDK entry builds missing producers, accepts different repository SHAs and reuses successful receipts', async () => {
  const f = await fixture(); const result = await invoke(f); observed(result, 'full-entry');
  assert.equal(result.rc, 0, result.stderr); assert.match(result.stdout, /SDK-BUILD-OK/);
  assert.notEqual(f.sources.runtime.commit, f.sources.compiler.commit);
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  assert.equal(manifest.components.runtime.source.commit, f.sources.runtime.commit);
  assert.equal(manifest.components['llvm-dylib'].source.commit, f.sources.llvm.commit);
  const runtime = await readJson(path.join(f.identities.get('runtime').directory, 'output.json'));
  assert.equal(runtime.execution.rc, 0); assert.match(await fs.readFile(path.join(f.identities.get('runtime').directory, 'sharedbuild-output/build.log'), 'utf8'), /FIXTURE_PRODUCER_EXECUTED mode=runtime/);
  const before = await fs.stat(path.join(f.identities.get('runtime').directory, 'output.json'));
  f.out = path.join(f.root, 'sdk-second'); const repeat = await invoke(f); observed(repeat, 'cache'); assert.equal(repeat.rc, 0, repeat.stderr);
  assert.equal((await fs.stat(path.join(f.identities.get('runtime').directory, 'output.json'))).mtimeMs, before.mtimeMs);
});
test('new opt plus old libLLVM is rejected by the real installed-source assertion', async () => {
  const f = await fixture(); const good = await invoke(f); assert.equal(good.rc, 0, good.stderr);
  const component = f.plan.components.find(value => value.id === 'llvm-dylib');
  const root = f.identities.get(component.id).directory;
  const library = path.join(root, 'artifacts/libLLVM-15.so'); const original = await fs.readFile(library);
  // An internally sealed but semantically wrong output reaches LLVM_TUPLE,
  // independently of the ordinary payload corruption guard.
  const bytes = Buffer.from(original); const token = Buffer.from(f.sources.llvm.commit); const at = bytes.indexOf(token); assert.ok(at >= 0);
  bytes.set(Buffer.from('e'.repeat(40)), at); await fs.writeFile(library, bytes);
  const output = await readJson(path.join(root, 'output.json')); output.files['libLLVM-15.so'].sha256 = await fileDigest(library);
  await atomicJson(path.join(root, 'output.json'), output); await fs.writeFile(path.join(root, 'DONE'), `${await fileDigest(path.join(root, 'output.json'))}\n`);
  f.out = path.join(f.root, 'mixed-sdk'); const mixed = await invoke(f); observed(mixed, 'llvm-mixed-stamp');
  assert.notEqual(mixed.rc, 0); assert.match(mixed.stderr, /rule=LLVM_TUPLE.*libLLVM-15.so/); await assert.rejects(fs.access(f.out));
  await fs.writeFile(library, original); output.files['libLLVM-15.so'].sha256 = await fileDigest(library);
  await atomicJson(path.join(root, 'output.json'), output); await fs.writeFile(path.join(root, 'DONE'), `${await fileDigest(path.join(root, 'output.json'))}\n`);
  const restored = await invoke(f); observed(restored, 'llvm-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('ordinary payload replacement cannot be blessed by rewriting the installation lock', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const root = f.identities.get('std').directory, module = path.join(root, 'artifacts', `modules/${tuple}/std/core/core.Int64.ti`);
  const original = await fs.readFile(module), replacement = Buffer.from(original);
  replacement[0] ^= 1; await fs.writeFile(module, replacement);
  f.out = path.join(f.root, 'changed-sdk'); const changed = await invoke(f); observed(changed, 'ordinary-digest');
  assert.notEqual(changed.rc, 0); assert.match(changed.stderr, /rule=PAYLOAD_(DIGEST|TYPE).*core.Int64.ti/); await assert.rejects(fs.access(f.out));
  await fs.writeFile(module, original); const restored = await invoke(f); observed(restored, 'ordinary-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('mixed frozen LLVM sources, cycles and incomplete plans reject before producing', async () => {
  const f = await fixture();
  for (const [name, mutate, rule] of [
    ['LLVM declaration', plan => { plan.components.find(value => value.id === 'llvm-dylib').source = clone(f.sources.compiler); }, /rule=LLVM_SOURCE/],
    ['cycle', plan => { plan.components.find(value => value.id === 'compiler').dependencies.push('std'); }, /rule=DEPENDENCY_CYCLE/],
    ['missing std', plan => { plan.components = plan.components.filter(value => value.id !== 'std'); }, /rule=MISSING_COMPONENT/],
    ['unknown adapter', plan => { plan.components[1].producer.adapter = 'shell-command'; }, /rule=ADAPTER/],
    ['path escape', plan => { plan.components[1].install[0].to = '../escape'; }, /rule=PATH/],
    ['unpaired boundscheck', plan => {
      const runtime = plan.components.find(value => value.id === 'runtime');
      runtime.roles = ['runtime']; const other = clone(runtime); other.id = 'bounds-only'; other.roles = ['boundscheck']; plan.components.push(other);
    }, /rule=RUNTIME_PAIR/],
  ]) {
    const bad = clone(f.plan); mutate(bad); await atomicJson(f.planFile, bad);
    const result = await command([process.execPath, product, '--plan', f.planFile, '--out', f.out]); observed(result, name);
    assert.notEqual(result.rc, 0); assert.match(result.stderr, rule); await assert.rejects(fs.access(f.plan.buildRoot));
  }
});
test('same-key parallel SDK requests serialize the producer and publish separate complete SDKs', async () => {
  const f = await fixture();
  const run = out => command([process.execPath, product, '--plan', f.planFile, '--out', out]);
  const [first, second] = await Promise.all([run(f.out), run(path.join(f.root, 'sdk-other'))]); observed(first, 'concurrent-first'); observed(second, 'concurrent-second');
  assert.equal(first.rc, 0, first.stderr); assert.equal(second.rc, 0, second.stderr);
  assert.equal(await fileDigest(path.join(f.out, 'SDK.manifest.json')), await fileDigest(path.join(f.root, 'sdk-other/SDK.manifest.json')));
  for (const component of f.plan.components.slice(1)) {
    const log = await fs.readFile(path.join(f.identities.get(component.id).directory, 'sharedbuild-output/build.log'), 'utf8');
    assert.equal((log.match(/FIXTURE_PRODUCER_EXECUTED/g) || []).length, 1, component.id);
  }
});
test('failed producer preserves actual rc and never publishes or starts dependents', async () => {
  const f = await fixture(); const runtime = f.plan.components.find(value => value.id === 'runtime');
  runtime.config.options.parameters.mode = 'fail'; const identities = buildIdentities(f.plan);
  const result = await invoke(f); observed(result, 'producer-failure'); assert.notEqual(result.rc, 0); assert.match(result.stderr, /BUILD_FAILED rc=17/);
  const state = await readJson(path.join(identities.get('runtime').directory, 'state.json')); assert.equal(state.status, 'failed');
  await assert.rejects(fs.access(path.join(identities.get('runtime').directory, 'DONE'))); await assert.rejects(fs.access(path.join(identities.get('std').directory, 'state.json')));
  await assert.rejects(fs.access(f.out));
});

async function resealFixtureRecord(directory, record) {
  await atomicJson(path.join(directory, 'output.json'), record);
  await fs.writeFile(path.join(directory, 'DONE'), `${await fileDigest(path.join(directory, 'output.json'))}\n`);
}
test('wrong compiler std reaches the existing installed compiler lineage guard and recovers', async () => {
  const f = await fixture(); const good = await invoke(f); assert.equal(good.rc, 0, good.stderr);
  const directory = f.identities.get('std').directory;
  const file = path.join(directory, 'artifacts/std-producer.json'), bytes = await fs.readFile(file);
  const record = await readJson(path.join(directory, 'output.json'));
  await atomicJson(file, {compiler_sha256: 'e'.repeat(64)});
  record.files['std-producer.json'].sha256 = await fileDigest(file);
  record.files['std-producer.json'].size = (await fs.stat(file)).size;
  await resealFixtureRecord(directory, record);
  f.out = path.join(f.root, 'wrong-std'); const wrong = await invoke(f); observed(wrong, 'std-wrong-compiler');
  assert.notEqual(wrong.rc, 0); assert.match(wrong.stderr, /rule=STD_CJC.*on-disk cjc/);
  await assert.rejects(fs.access(f.out));
  await fs.writeFile(file, bytes); record.files['std-producer.json'].sha256 = await fileDigest(file);
  record.files['std-producer.json'].size = bytes.length; await resealFixtureRecord(directory, record);
  const restored = await invoke(f); observed(restored, 'std-compiler-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('forged actual source completion rejects before consuming artifacts', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const directory = f.identities.get('runtime').directory, record = await readJson(path.join(directory, 'output.json'));
  const original = clone(record); record.execution.source.commit = f.sources.compiler.commit;
  await resealFixtureRecord(directory, record);
  f.out = path.join(f.root, 'forged-source'); const wrong = await invoke(f); observed(wrong, 'forged-actual-source');
  assert.notEqual(wrong.rc, 0); assert.match(wrong.stderr, /rule=SOURCE_COMPLETION component=runtime/);
  await assert.rejects(fs.access(f.out));
  await resealFixtureRecord(directory, original); const restored = await invoke(f); observed(restored, 'source-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('duplicate destinations and a source directory symlink never publish an SDK', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const original = clone(f.plan); f.out = path.join(f.root, 'duplicate-sdk');
  f.plan.components.find(value => value.id === 'compiler').install.push({from: 'cjcj-stage1', to: 'bin/cjcj-stage1'});
  const duplicate = await invoke(f); observed(duplicate, 'duplicate-install');
  assert.notEqual(duplicate.rc, 0); assert.match(duplicate.stderr, /rule=DUPLICATE_INSTALL component=compiler/);
  await assert.rejects(fs.access(f.out));
  f.plan = original;
  const artifacts = path.join(f.identities.get('runtime').directory, 'artifacts'), saved = `${artifacts}-saved`;
  await fs.rename(artifacts, saved); await fs.symlink(saved, artifacts);
  f.out = path.join(f.root, 'symlink-sdk'); const escaped = await invoke(f); observed(escaped, 'source-root-link');
  assert.notEqual(escaped.rc, 0); assert.match(escaped.stderr, /rule=LINK_ESCAPE component=runtime/);
  await assert.rejects(fs.access(f.out));
  await fs.unlink(artifacts); await fs.rename(saved, artifacts);
  const restored = await invoke(f); observed(restored, 'source-link-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('different frozen configurations sharing a request hint cannot overwrite producer requests', async () => {
  const f = await fixture(), other = clone(f.plan);
  other.components.find(value => value.id === 'runtime').config.options.parameters.mode = 'fail';
  const secondPlan = path.join(f.root, 'other-plan.json'); await atomicJson(secondPlan, other);
  const [normal, failed] = await Promise.all([invoke(f), command([process.execPath, product, '--plan', secondPlan, '--out', path.join(f.root, 'sdk-failed')])]);
  observed(normal, 'different-config-normal'); observed(failed, 'different-config-failure');
  assert.equal(normal.rc, 0, normal.stderr); assert.notEqual(failed.rc, 0); assert.match(failed.stderr, /BUILD_FAILED rc=17/);
  const second = buildIdentities(other).get('runtime').directory;
  assert.notEqual(second, f.identities.get('runtime').directory);
  assert.equal((await readJson(path.join(second, 'sharedbuild-request.json'))).parameters.mode, 'fail');
  assert.equal((await readJson(path.join(f.identities.get('runtime').directory, 'sharedbuild-request.json'))).parameters.mode, 'runtime');
});
test('a collected success cache restores the same completed work without rerunning its producer', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const directory = f.identities.get('runtime').directory, record = await readJson(path.join(directory, 'output.json'));
  const work = record.execution.actualWork, logBefore = await fs.readdir(path.join(work, 'logs'));
  await fs.rename(directory, `${directory}-collected`);
  await fs.rename(path.join(f.plan.buildRoot, 'shared-cache', record.execution.producerBuildId), path.join(f.root, 'collected-shared-cache'));
  f.out = path.join(f.root, 'sdk-restored-cache'); const restored = await invoke(f); observed(restored, 'completed-work-recovery');
  assert.equal(restored.rc, 0, restored.stderr);
  assert.deepEqual(await fs.readdir(path.join(work, 'logs')), logBefore);
  assert.equal((await readJson(path.join(directory, 'output.json'))).execution.actualWork, work);
});

test('transported receipts retain original build origin and frozen digest without source copies or producers', async () => {
  const f = await fixture(); const initial = await invoke(f); assert.equal(initial.rc, 0, initial.stderr);
  const originalRoot = f.plan.buildRoot, records = {};
  for (const component of f.plan.components) {
    const original = f.identities.get(component.id).directory, destination = path.join(f.root, 'received', component.id);
    await fs.mkdir(destination, {recursive: true});
    await fs.cp(path.join(original, 'artifacts'), path.join(destination, 'artifacts'), {recursive: true, dereference: false});
    for (const name of ['output.json', 'DONE']) await fs.copyFile(path.join(original, name), path.join(destination, name));
    records[component.id] = await fs.readFile(path.join(destination, 'output.json'));
    Object.assign(component.producer, {receipt: destination, originBuildRoot: originalRoot,
      receiptSha256: await fileDigest(path.join(destination, 'output.json'))});
  }
  f.plan.buildRoot = path.join(f.root, 'consumer-build-root'); f.out = path.join(f.root, 'sdk-transported');
  const transported = await invoke(f); observed(transported, 'transported-receipts'); assert.equal(transported.rc, 0, transported.stderr);
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  for (const component of f.plan.components) {
    assert.equal(manifest.components[component.id].originDirectory, f.identities.get(component.id).directory);
    assert.equal(manifest.components[component.id].buildId, f.identities.get(component.id).buildId);
    assert.deepEqual(await fs.readFile(path.join(component.producer.receipt, 'output.json')), records[component.id]);
    await assert.rejects(fs.access(buildIdentities(f.plan).get(component.id).directory));
  }
  // Top-level hashes and payload rows can agree while a non-runtime producer
  // receipt differs from the one frozen before assembly. Reuse must compare
  // the actual source closure, not just internally consistent installation.
  const plans = path.join(f.root, 'transported-phases.json');
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases: {'stage1-initial': f.plan}});
  const manifestPath = path.join(f.out, 'SDK.manifest.json'), lockPath = path.join(f.out, 'SDK.lock.json');
  const manifestBytes = await fs.readFile(manifestPath), lockBytes = await fs.readFile(lockPath);
  const changedManifest = JSON.parse(manifestBytes), changedLock = JSON.parse(lockBytes);
  changedManifest.components.compiler.receiptSha256 = 'e'.repeat(64);
  for (const [rel, file] of Object.entries(changedManifest.files)) if (file.component === 'compiler') {
    file.receiptSha256 = 'e'.repeat(64); changedLock.files[rel].producer.receipt_sha256 = file.receiptSha256;
  }
  await atomicJson(manifestPath, changedManifest);
  changedLock.manifest_sha256 = objectId(changedManifest);
  changedLock.files['SDK.manifest.json'].sha256 = await fileDigest(manifestPath);
  await atomicJson(lockPath, changedLock);
  const reuseArgs = [process.execPath, path.join(here, 'bootstrap-sdk.mjs'), '--plans', plans,
    '--phase', 'stage1-initial', '--out', f.out];
  const wrongOrigin = await command(reuseArgs); observed(wrongOrigin, 'phase-frozen-receipt');
  assert.notEqual(wrongOrigin.rc, 0); assert.match(wrongOrigin.stderr, /rule=RESOLVED_IDENTITY component=compiler/);
  await fs.writeFile(manifestPath, manifestBytes); await fs.writeFile(lockPath, lockBytes);
  const recovered = await command(reuseArgs); observed(recovered, 'phase-receipt-restored'); assert.equal(recovered.rc, 0, recovered.stderr);
  const moduleRel = `modules/${tuple}/std/core/core.Int64.ti`, modulePath = path.join(f.out, moduleRel);
  const originalModule = await fs.readFile(modulePath), substitutedModule = Buffer.from(originalModule);
  substitutedModule[0] ^= 1; await fs.writeFile(modulePath, substitutedModule);
  const rewrittenManifest = JSON.parse(manifestBytes), rewrittenLock = JSON.parse(lockBytes);
  rewrittenManifest.files[moduleRel].sha256 = await fileDigest(modulePath);
  rewrittenLock.files[moduleRel].sha256 = rewrittenManifest.files[moduleRel].sha256;
  await atomicJson(manifestPath, rewrittenManifest);
  rewrittenLock.manifest_sha256 = objectId(rewrittenManifest);
  rewrittenLock.files['SDK.manifest.json'].sha256 = await fileDigest(manifestPath);
  await atomicJson(lockPath, rewrittenLock);
  const rewrittenInventory = await command(reuseArgs); observed(rewrittenInventory, 'phase-original-inventory');
  assert.notEqual(rewrittenInventory.rc, 0); assert.match(rewrittenInventory.stderr, /rule=RESOLVED_PAYLOAD component=std.*core.Int64.ti/);
  await fs.writeFile(modulePath, originalModule); await fs.writeFile(manifestPath, manifestBytes); await fs.writeFile(lockPath, lockBytes);
  const inventoryRestored = await command(reuseArgs); observed(inventoryRestored, 'phase-inventory-restored'); assert.equal(inventoryRestored.rc, 0, inventoryRestored.stderr);
  f.plan.components.find(value => value.id === 'runtime').producer.receiptSha256 = 'e'.repeat(64);
  f.out = path.join(f.root, 'wrong-receipt-sdk'); const changed = await invoke(f); observed(changed, 'receipt-digest');
  assert.notEqual(changed.rc, 0); assert.match(changed.stderr, /rule=COMPLETION component=runtime/);
});

test('bootstrap phase reuse binds installed plan and manifest before returning an existing SDK', async () => {
  const f = await fixture(); const initial = await invoke(f); assert.equal(initial.rc, 0, initial.stderr);
  const plans = path.join(f.root, 'phases.json');
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases: {'stage1-initial': f.plan}});
  const argv = [process.execPath, path.join(here, 'bootstrap-sdk.mjs'), '--plans', plans,
    '--phase', 'stage1-initial', '--out', f.out];
  const normal = await command(argv); observed(normal, 'phase-reuse'); assert.equal(normal.rc, 0, normal.stderr);
  assert.equal(JSON.parse(normal.stdout.trim()).reused, true);
  const installedPlan = path.join(f.out, 'SDK.plan.json'), original = await fs.readFile(installedPlan);
  const changed = JSON.parse(original); changed.lane = 'another-owner'; await atomicJson(installedPlan, changed);
  const rejected = await command(argv); observed(rejected, 'phase-plan-binding');
  assert.notEqual(rejected.rc, 0); assert.match(rejected.stderr, /rule=INSTALL_BINDING component=sdk/);
  await fs.writeFile(installedPlan, original);
  const restored = await command(argv); observed(restored, 'phase-plan-restored'); assert.equal(restored.rc, 0, restored.stderr);
  const module = path.join(f.out, `modules/${tuple}/std/core/core.Int64.ti`);
  const moduleBytes = await fs.readFile(module), lockPath = path.join(f.out, 'SDK.lock.json');
  const lockBytes = await fs.readFile(lockPath), lock = JSON.parse(lockBytes);
  const changedModule = Buffer.from(moduleBytes); changedModule[0] ^= 1; await fs.writeFile(module, changedModule);
  lock.files[`modules/${tuple}/std/core/core.Int64.ti`].sha256 = await fileDigest(module);
  await atomicJson(lockPath, lock);
  const rewritten = await command(argv); observed(rewritten, 'phase-lock-rewrite');
  assert.notEqual(rewritten.rc, 0); assert.match(rewritten.stderr, /rule=MANIFEST_BINDING/);
  await fs.writeFile(module, moduleBytes); await fs.writeFile(lockPath, lockBytes);
  const recovered = await command(argv); observed(recovered, 'phase-lock-restored'); assert.equal(recovered.rc, 0, recovered.stderr);
});
