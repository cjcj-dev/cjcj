#!/usr/bin/env zx
// Shared small real producer fixture. Receipts and native payloads are emitted
// by the existing sharedbuild engine, never fabricated by the test consumer.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {PLAN_SCHEMA, buildIdentities, execute, fileDigest, atomicJson} from '../sdk-manifest.mjs';
const here = path.dirname(fileURLToPath(new URL('../toolchain-sdk.mjs', import.meta.url)));
const engine = process.env.SDK_SHAREDBUILD_ENGINE;
const testRoot = process.env.SDK_MANIFEST_TEST_ROOT;
const tuple = 'linux_x86_64_cjnative';
export const command = async argv => {
  try { return {rc: 0, ...(await execute(argv[0], argv.slice(1), {maxBuffer: 8 * 1024 * 1024}))}; }
  catch (error) { return {rc: error.code ?? null, signal: error.signal ?? null, killed: error.killed ?? false, stdout: error.stdout || '', stderr: error.stderr || '', error: error.message}; }
};
const write = async (file, content) => { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, content); };
const fixtureSources = {
  'runtime.c': '#ifndef CJRT_SHA\n#define CJRT_SHA "official"\n#endif\nconst char provenance[]="CJRT-COMMIT:" CJRT_SHA; int official_symbol=1;\n#ifdef FIXTURE_COLOUR\nint g_cjLoadBadMask=1;\n#endif\n',
  'alias-tool.c': '#include <stdio.h>\n#include <string.h>\n#include <unistd.h>\nstatic const char *base(const char *p){const char *s=strrchr(p,47);return s?s+1:p;}\nint main(int argc,char **argv){if(argc>1&&!strcmp(argv[1],"--version")){puts("fixture alias tool version 1");return 0;} char physical[4096];ssize_t n=readlink("/proc/self/exe",physical,sizeof(physical)-1);if(n<0)return 2;physical[n]=0;printf("argv0=%s physical=%s\\n",base(argv[0]),base(physical));return 0;}\n',
  'boundscheck.c': 'int boundscheck_fixture(void){return 0;}\n',
  'std.c': '#ifdef FIXTURE_COLOUR\nextern int g_cjLoadBadMask; int std_fixture(void){return g_cjLoadBadMask;}\n#else\nint std_fixture(void){return 0;}\n#endif\n',
  'tool.c': '#include <stdio.h>\n#ifndef CJLLVM_SHA\n#define CJLLVM_SHA "official"\n#endif\nconst char llvm_origin[]="CJLLVM-COMMIT:" CJLLVM_SHA; int main(void){puts("fixture tool version 1"); return 0;}\n',
  'llvm.c': '#include <stdlib.h>\n#ifndef CJLLVM_SHA\n#define CJLLVM_SHA "official"\n#endif\nconst char llvm_origin[]="CJLLVM-COMMIT:" CJLLVM_SHA;\n' +
    '#ifndef FIXTURE_REV\n#define FIXTURE_REV "initial"\n#endif\nconst char fixture_library_revision[]=FIXTURE_REV;\n' +
    ['X86', 'ARM', 'AArch64'].flatMap(target => ['TargetInfo', 'Target', 'TargetMC', 'AsmPrinter', 'AsmParser'].map(part => `void LLVMInitialize${target}${part}(void){}\n`)).join('') +
    'void *LLVMContextCreate(void){return malloc(1);} void LLVMContextDispose(void *p){free(p);}\n',
};
export async function sourceRepository(root, name, overrides = {}) {
  const repo = path.join(root, name); await fs.mkdir(repo);
  for (const [rel, content] of Object.entries({...fixtureSources, ...overrides})) await write(path.join(repo, rel), content);
  await write(path.join(repo, 'identity.txt'), name);
  for (const args of [['init', '-q', repo], ['-C', repo, 'add', '.'], ['-C', repo, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture input']]) {
    const result = await command(['git', ...args]); assert.equal(result.rc, 0, result.stderr);
  }
  return {kind: 'git', repo, commit: (await execute('git', ['-C', repo, 'rev-parse', 'HEAD'])).stdout.trim(),
    tree: (await execute('git', ['-C', repo, 'rev-parse', 'HEAD^{tree}'])).stdout.trim()};
}
export async function fixture({role = 'target', sources: sourceOverrides = {}, sourceNames = {}, parameters = {}, prepareOfficial,
  colourReference = 'runtime.c', runtimeLayout} = {}) {
  assert.ok(engine && testRoot, 'SDK_SHAREDBUILD_ENGINE and SDK_MANIFEST_TEST_ROOT must name remote isolated inputs');
  assert.ok(['host', 'target'].includes(role));
  const root = await fs.mkdtemp(path.join(testRoot, 'sdk-manifest-'));
  const sources = {};
  for (const name of ['runtime', 'compiler', 'llvm', 'std']) sources[name] = await sourceRepository(root, sourceNames[name] || name, sourceOverrides[name]);
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
  // Mutations happen before the real publisher authenticates this source.
  // They cannot amend an output receipt or relabel an old incomplete SDK.
  if (prepareOfficial) await prepareOfficial({root, official, sources});
  const seedResult = await command(['python3', engine, '--remote', '--root', path.join(root, 'seed-cache'), '--lane', 'sdk-fixture', 'sdk-publish', '--source', official, '--version', 'fixture-official']);
  assert.equal(seedResult.rc, 0, seedResult.stderr);
  const seed = seedResult.stdout.trim(), seedLock = path.join(seed, 'SDK.lock.json');
  const colour = path.join(native, 'colour.so');
  assert.equal((await command(['cc', '-shared', '-fPIC', '-DFIXTURE_COLOUR=1', path.join(sources.runtime.repo, colourReference), '-o', colour])).rc, 0);
  const pin = path.join(root, 'runtime.env'); await write(pin, `RUNTIME_REF=${sources.runtime.commit}\n`);
  const builder = path.join(here, 'fixtures/sdk-fixture-producer.mjs');
  const producerVersion = (await execute('git', ['-C', path.dirname(engine), 'rev-parse', 'HEAD'])).stdout.trim();
  const producerRoot = (await execute('git', ['-C', path.dirname(engine), 'rev-parse', '--show-toplevel'])).stdout.trim();
  const frozenTools = {};
  for (const name of ['python3', 'node', 'git', 'bash', 'tar', 'cmake', 'clang', 'clang++', 'cc', 'ar']) {
    const location = (await execute('sh', ['-c', 'command -v "$1"', 'fixture-tool', name])).stdout.trim();
    frozenTools[name] = {path: path.resolve(location), sha256: await fileDigest(location)};
  }
  const plan = {schema: PLAN_SCHEMA, lane: 'sym_cjcj_918_implement_r6061418558', role, stage: 'stage1', platform: 'linux_x86_64', buildRoot: path.join(root, 'builds'),
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
    ['runtime', ['runtime', 'boundscheck'], sources.runtime, 'runtime', ['official'], runtimeLayout === 'flat'
      ? [{from: 'libcangjie-runtime.so', to: `runtime/lib/${tuple}/libcangjie-runtime.so`},
        {from: 'libboundscheck.so', to: `runtime/lib/${tuple}/libboundscheck.so`}, {from: 'lib', to: 'lib'}]
      : [{from: 'install', to: '', ...(runtimeLayout === 'nested-static'
        ? {exclude: [`lib/${tuple}/libcangjie-runtime.so`, `lib/${tuple}/libboundscheck.so`]} : {})}]],
    ['compiler', ['compiler'], sources.compiler, 'compiler', ['official'], [{from: 'bin', to: 'bin'}, {from: 'compiler-lineage.json', to: 'compiler-lineage.json'}]],
    ['llvm-tools', ['llvm-tools'], sources.llvm, 'llvm-tools', ['official', 'runtime'], [{from: '', to: 'third_party/llvm'}]],
    ['llvm-dylib', ['llvm-dylib'], sources.llvm, 'llvm-dylib', ['official', 'runtime'], [{from: '', to: 'third_party/llvm/lib'}]],
    ['std', ['std'], sources.std, 'std', ['official', 'compiler', 'runtime'], [{from: '', to: ''}]],
  ]) {
    const recipe = path.join(root, `${id}.recipe.json`);
    const expectedOutputs = {'runtime': [runtimeLayout === 'flat' ? 'libcangjie-runtime.so' : `install/runtime/lib/${tuple}/libcangjie-runtime.so`], compiler: ['cjcj-stage1'],
      'llvm-tools': ['bin/opt'], 'llvm-dylib': ['libLLVM-15.so'], std: ['std-producer.json']}[id];
    plan.components.push({id, roles, domain: role, source, config: {host: plan.platform, target: plan.platform,
      options: {parameters: {mode, ...(role === 'host' ? {role} : {}), ...(id === 'runtime' && runtimeLayout ? {runtimeLayout} : {}), ...(id === 'llvm-tools' ? {compilerSha: sources.compiler.commit, flatbuffersSha: sources.std.commit} : {}), ...parameters[id]}, optimization: 'Release', sdkDependency: 'official', jobs: os.availableParallelism(), heap: '32GB',
        inputBindings: id === 'std' ? {compiler: {dependency: 'compiler', artifact: 'bin/cjcj-stage1'}} : {}, outputs: expectedOutputs},
      tools: {...frozenTools, ...(id === 'compiler' ? {compilerIdentity: {path: path.join(here, 'compiler_identity.py'), sha256: await fileDigest(path.join(here, 'compiler_identity.py'))}} : {}), builder: {path: builder, sha256: await fileDigest(builder)}}},
      producer: {adapter: 'sharedbuild-runtime-default', version: producerVersion, repository: producerRoot, engine, engineSha256: await fileDigest(engine), recipe}, dependencies, install});
  }
  const identities = buildIdentities(plan);
  const planFile = path.join(root, 'plan.json'); await atomicJson(planFile, plan);
  return {root, plan, planFile, identities, out: path.join(root, 'sdk'), sources};
}
