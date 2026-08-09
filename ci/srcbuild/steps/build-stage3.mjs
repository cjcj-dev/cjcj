#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';

$.stdio = 'inherit';

const requiredEnv = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

const workspace = path.resolve(requiredEnv('CANGJIE_WORKSPACE'));
const githubWorkspace = path.resolve(requiredEnv('GITHUB_WORKSPACE'));
const target = getTarget(requiredEnv('CJCJ_SRCBUILD_TARGET'));
if (workspace === path.parse(workspace).root || githubWorkspace === path.parse(githubWorkspace).root) {
  throw new Error('CANGJIE_WORKSPACE and GITHUB_WORKSPACE must not be filesystem roots');
}
const stdlibBuildType = requiredEnv('CJCJ_STAGE3_STDLIB_BUILD_TYPE');
const dryRunValue = process.env.CJCJ_STAGE3_DRY_RUN;
if (dryRunValue && dryRunValue !== '1') {
  throw new Error('CJCJ_STAGE3_DRY_RUN, when set, must be exactly 1');
}
const dryRun = dryRunValue === '1';
const allowIdenticalStdValue = process.env.CJCJ_STAGE3_ALLOW_IDENTICAL_STD;
if (allowIdenticalStdValue && allowIdenticalStdValue !== '1') {
  throw new Error('CJCJ_STAGE3_ALLOW_IDENTICAL_STD, when set, must be exactly 1');
}

const sdk = path.join(workspace, 'software', 'cangjie');
const stdlibRoot = path.join(workspace, 'cangjie_runtime', 'stdlib');
const runtimeTarget = path.join(workspace, 'cangjie_runtime', 'runtime', 'target');
const {runtimeTuple: tuple} = target.spec;
const finalStd = dryRun
  ? path.resolve(requiredEnv('CJCJ_STAGE3_DRY_RUN_FINAL_STD'))
  : path.join(workspace, 'software', 'final-std-stage2');
const productCandidates = ['cjc@cjcj', 'cjcj::cjc'];

const exists = async (file, kind = 'file') => {
  try {
    const stat = await fs.stat(file);
    return kind === 'dir' ? stat.isDirectory() : stat.isFile();
  } catch {
    return false;
  }
};

const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

async function findProductBinary(phase) {
  const binDir = path.join(githubWorkspace, 'target', 'release', 'bin');
  const found = [];
  for (const name of productCandidates) {
    const candidate = path.join(binDir, name);
    if (await exists(candidate)) found.push(candidate);
  }
  if (found.length !== 1) {
    throw new Error(`${phase}: expected exactly one cjcj product (${productCandidates.join(', ')}), found ${found.length}`);
  }
  return found[0];
}

async function assertStage2Compiler(stageEnv, stage2Sha) {
  const installed = path.join(sdk, 'bin', 'cjcj-stage2');
  const linked = path.join(sdk, 'bin', 'cjc');
  const resolvedLink = await fs.realpath(linked);
  const resolvedInstalled = await fs.realpath(installed);
  const command = await $({cwd: githubWorkspace, env: stageEnv, stdio: 'pipe'})`command -v cjc`;
  const resolvedCommand = await fs.realpath(command.stdout.trim());
  const installedSha = await sha256(installed);
  if (resolvedLink !== resolvedInstalled || resolvedCommand !== resolvedInstalled || installedSha !== stage2Sha) {
    throw new Error(`stage2 compiler assertion failed: link=${resolvedLink}, command=${resolvedCommand}, expected=${resolvedInstalled}, sha=${installedSha}`);
  }
  console.log(`STAGE3_COMPILER_ASSERT_PASS path=${resolvedInstalled} sha256=${installedSha}`);
}

async function countFinalStd(root) {
  const modulesTop = path.join(root, 'modules', tuple);
  const modulesStd = path.join(root, 'modules', tuple, 'std');
  const staticDir = path.join(root, 'lib', tuple);
  const sharedDir = path.join(root, 'runtime', 'lib', tuple);
  for (const directory of [modulesTop, modulesStd, staticDir, sharedDir]) {
    if (!await exists(directory, 'dir')) throw new Error(`final std directory missing: ${directory}`);
  }
  const [topModules, modules, staticLibs, sharedLibs] = await Promise.all([
    fs.readdir(modulesTop),
    fs.readdir(modulesStd),
    fs.readdir(staticDir),
    fs.readdir(sharedDir),
  ]);
  return {
    cjos: modules.filter((name) => /^std\..+\.cjo$/.test(name)).length
      + Number(topModules.includes('std.cjo')),
    bitcode: modules.filter((name) => /^libstd\..+\.bc$/.test(name)).length
      + Number(topModules.includes('libstd.bc')),
    staticLibs: staticLibs.filter((name) => /^libcangjie-std(?:-|\.)?.*\.a$/.test(name) && !name.endsWith('FFI.a')).length,
    ffiStaticLibs: staticLibs.filter((name) => /^libcangjie-std.*FFI\.a$/.test(name)).length,
    sharedLibs: sharedLibs.filter((name) => /^libcangjie-std(?:-|\.)?.*\.so$/.test(name)).length,
  };
}

async function assertFinalStd(root) {
  const counts = await countFinalStd(root);
  const expected = dryRun
    ? {cjos: 1, bitcode: 1, staticLibs: 1, ffiStaticLibs: 1, sharedLibs: 1}
    : {cjos: 47, bitcode: 47, staticLibs: 47, ffiStaticLibs: 16, sharedLibs: 47};
  for (const [kind, count] of Object.entries(counts)) {
    if (count !== expected[kind]) throw new Error(`final std ${kind}: expected ${expected[kind]}, found ${count}`);
  }
  console.log(`STAGE3_FINAL_STD_ASSERT_PASS cjos=${counts.cjos} bitcode=${counts.bitcode} static=${counts.staticLibs} ffi_static=${counts.ffiStaticLibs} shared=${counts.sharedLibs}${dryRun ? ' FAKE=1' : ''}`);
  return counts;
}

async function countRuntimeMarkers(runtime) {
  const contents = (await fs.readFile(runtime)).toString('latin1');
  return contents.match(/MRT_GCV2_/g)?.length ?? 0;
}

async function assertStdBarriers(coreLib) {
  const output = await $({stdio: 'pipe'})`objdump -drwC ${coreLib}`;
  const lines = output.stdout.split('\n');
  const symbols = [
    '_CNat6String7indexOfHRNatY0_E',
    '_CNat6String7toArrayHv',
  ];
  let checked = 0;
  for (const symbol of symbols) {
    let inBody = false;
    let found = false;
    let shrTests = 0;
    let maskTests = 0;
    let barrierCalls = 0;
    for (const line of lines) {
      if (line.includes(`<${symbol}>:`)) {
        inBody = true;
        found = true;
        continue;
      }
      if (inBody && (line.trim() === '' || (/^[0-9a-f]+ </.test(line) && !line.includes(symbol)))) inBody = false;
      if (!inBody) continue;
      // The tag test has two shapes. Older toolchains shift the top bits down and
      // compare against zero; since CJBarrierLowering.cpp:653-665 the compiler loads
      // g_cjLoadBadMask and ands against it, so a std built by the current LLVM main
      // carries no shr at all. Counting only the shr form would reject a correctly
      // built final std, which is the one thing this assertion exists to accept.
      if (/shr *\$0x30/.test(line)) shrTests += 1;
      if (/g_cjLoadBadMask/.test(line)) maskTests += 1;
      if (/CJ_MCC_ReadStaticRef|CJ_MCC_ReadRefField/.test(line)) barrierCalls += 1;
    }
    const tagTests = shrTests + maskTests;
    if (!found || tagTests === 0 || barrierCalls === 0) {
      throw new Error(`final std barrier assertion failed for ${symbol}: found=${found}, shr=${shrTests}, mask=${maskTests}, barrier_call=${barrierCalls}`);
    }
    checked += 1;
    console.log(`STAGE3_BARRIER_FUNCTION_PASS symbol=${symbol} shr=${shrTests} mask=${maskTests} barrier_call=${barrierCalls}`);
  }
  if (checked === 0) throw new Error('final std barrier assertion checked zero functions');
  console.log(`STAGE3_BARRIER_ASSERT_PASS checked=${checked}`);
}

if (!await exists(sdk, 'dir')) throw new Error(`source SDK missing: ${sdk}`);
if (!await exists(stdlibRoot, 'dir')) throw new Error(`runtime stdlib source missing: ${stdlibRoot}`);

const stage2Product = await findProductBinary('stage2');
const stage2Sha = await sha256(stage2Product);
await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
await $`install -m0755 ${stage2Product} ${path.join(sdk, 'bin', 'cjcj-stage2')}`;
await fs.rm(path.join(sdk, 'bin', 'cjc'), {force: true});
await fs.symlink('cjcj-stage2', path.join(sdk, 'bin', 'cjc'));

const stageEnv = {
  ...process.env,
  CANGJIE_HOME: sdk,
  PATH: `${path.join(sdk, 'bin')}:${path.join(sdk, 'tools', 'bin')}:${process.env.PATH ?? ''}`,
};
await assertStage2Compiler(stageEnv, stage2Sha);
await $({cwd: githubWorkspace, env: stageEnv})`set -o pipefail; cjc --version | head -2`;

const runtime = path.join(sdk, 'runtime', 'lib', tuple, 'libcangjie-runtime.so');
if (!await exists(runtime)) throw new Error(`fork runtime missing: ${runtime}`);
const runtimeMarkers = await countRuntimeMarkers(runtime);
if (runtimeMarkers === 0) throw new Error(`${runtime} carries no MRT_GCV2_ markers; refusing stock runtime`);
console.log(`STAGE3_RUNTIME_ASSERT_PASS MRT_GCV2_markers=${runtimeMarkers}`);

const bootstrapCore = path.join(sdk, 'lib', tuple, 'libcangjie-std-core.a');
if (!await exists(bootstrapCore)) throw new Error(`bootstrap std core missing: ${bootstrapCore}`);
const bootstrapCoreSha = await sha256(bootstrapCore);

console.log('[stage3] rebuild final std with stage2');
if (dryRun) {
  console.log(`STAGE3_DRY_RUN_FAKE_ARTIFACTS=1 final_std=${finalStd}`);
  console.log(`[stage3][dry-run] python3 build.py clean; build -t ${stdlibBuildType} --target-lib=${runtimeTarget}; install --prefix ${finalStd}`);
} else {
  await fs.rm(finalStd, {recursive: true, force: true});
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py clean`;
  await assertStage2Compiler(stageEnv, stage2Sha);
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py build -t ${stdlibBuildType} --target-lib=${runtimeTarget}`;
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
}

await assertFinalStd(finalStd);
const finalCore = path.join(finalStd, 'lib', tuple, 'libcangjie-std-core.a');
const finalCoreSha = await sha256(finalCore);
if (finalCoreSha === bootstrapCoreSha && allowIdenticalStdValue !== '1') {
  throw new Error('stage2-built std is byte-identical to bootstrap std; provenance is inconclusive (set CJCJ_STAGE3_ALLOW_IDENTICAL_STD=1 only after independent proof)');
}
if (!dryRun) await assertStdBarriers(finalCore);

for (const entry of await fs.readdir(finalStd)) {
  await fs.cp(path.join(finalStd, entry), path.join(sdk, entry), {recursive: true, force: true});
}
const consumedCoreSha = await sha256(bootstrapCore);
if (consumedCoreSha !== finalCoreSha) {
  throw new Error(`SDK did not consume final std: sdk=${consumedCoreSha}, final=${finalCoreSha}`);
}
console.log(`STAGE3_STD_INPUT_ASSERT_PASS bootstrap_sha256=${bootstrapCoreSha} final_sha256=${finalCoreSha} sdk_sha256=${consumedCoreSha}`);

console.log('[stage3] clean final compiler with stage2 + final std');
await assertStage2Compiler(stageEnv, stage2Sha);
if (dryRun) {
  console.log('[stage3][dry-run] cjpm clean; cjpm build -j 1');
  console.log('STAGE3_DRY_RUN_REACHED_BUILD=1');
} else {
  await $({cwd: githubWorkspace, env: stageEnv})`cjpm clean`;
  await $({cwd: githubWorkspace, env: {...stageEnv, cjHeapSize: '20GB'}})`cjpm build -j 1`;
  const stage3Product = await findProductBinary('stage3');
  const stage3Sha = await sha256(stage3Product);
  console.log(`STAGE3_BUILD_PASS compiler=${stage3Product} sha256=${stage3Sha} input_compiler_sha256=${stage2Sha} input_std_sha256=${finalCoreSha}`);
}
