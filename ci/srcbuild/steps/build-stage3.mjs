#!/usr/bin/env zx

import {checkCodegenRuntimeLayout} from '../../check-codegen-runtime-layout.mjs';
import {verifyBootstrapRuntimeSdk} from '../../bootstrap/runtime_sdk.mjs';
import {prepareTrimpath} from '../../release/trimpath.mjs';

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';
import {resolveProductBinary} from '../lib/product-binary.mjs';
import {prepareBootstrapHandoff, assertBootstrapCompiler, bootstrapBackendIdentity, assertBootstrapBackends} from '../lib/bootstrap-handoff.mjs';
import {assertColouredRuntime} from '../lib/runtime-colour.mjs';
import {stdIdentity} from '../lib/final-compiler.mjs';

$.stdio = 'inherit';

const requiredEnv = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

const workspace = path.resolve(requiredEnv('CANGJIE_WORKSPACE'));
const githubWorkspace = path.resolve(requiredEnv('GITHUB_WORKSPACE'));
const target = getTarget(requiredEnv('CJCJ_SRCBUILD_TARGET'));
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${target.spec.key} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}
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
const bootstrapWork = path.resolve(requiredEnv('CJCJ_BOOTSTRAP_WORK'));
const runtimeTarget = path.join(sdk, 'runtime', 'lib', target.spec.runtimeTuple);
const {runtimeTuple: tuple} = target.spec;
const finalStd = dryRun
  ? path.resolve(requiredEnv('CJCJ_STAGE3_DRY_RUN_FINAL_STD'))
  : path.join(workspace, 'software', 'final-std-stage2');

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
  return resolveProductBinary(path.join(githubWorkspace, 'target', 'release', 'bin'), phase);
}

async function assertStage2Compiler(stageEnv, stage2Sha) {
  const command = await $({cwd: githubWorkspace, env: stageEnv, stdio: 'pipe'})`command -v cjc`;
  await assertBootstrapCompiler({sdk, command: command.stdout.trim(),
    producer: stage2Product, producerSha256: stage2Sha, targetLd});
  console.log(`STAGE3_COMPILER_ASSERT_PASS path=${path.join(sdk, 'bin', 'cjcj-stage2')} sha256=${stage2Sha}`);
}

async function assertConsumerInputs(stageEnv) {
  await verifyBootstrapRuntimeSdk(sdk, tuple, process.env, path.dirname(stdlibRoot), assemblyLockSha);
  await assertBootstrapBackends({sdk, targetLd, identity: backendIdentity});
  await assertStage2Compiler(stageEnv, stage2Sha);
}

async function assertStdBarriers(coreLib) {
  const symbolTable = await $({stdio: 'pipe'})`nm -A ${coreLib}`;
  const colourCheck = fileURLToPath(new URL('../../bootstrap/std_runtime_colour.py', import.meta.url));
  const hostRuntime = path.join(path.resolve(requiredEnv('CJCJ_BOOTSTRAP_HOST_RT')),
    'runtime', 'lib', tuple, target.spec.runtimeLibrary);
  const colour = await $({stdio: 'pipe'})`python3 ${colourCheck} --colour-runtime ${runtime} --host-runtime ${hostRuntime} --std-colour ${coreLib}`;
  process.stderr.write(colour.stderr);
  const hasColour = colour.stdout.trim() === '1';
  const hasReadBarrier = /CJ_MCC_Read(?:StaticRef|RefField)/.test(symbolTable.stdout);
  if (!hasColour || !hasReadBarrier) {
    throw new Error(`final std barrier symbol assertion failed: colour=${hasColour} read_barrier=${hasReadBarrier}`);
  }
  if (target.spec.os !== 'linux' || target.spec.arch !== 'x86_64') {
    // The existing instruction-shape probe is x86-specific. On native AArch64
    // and Mach-O, require both exact runtime references instead of pretending
    // the x86 shr/relocation syntax applies.
    console.log(`STAGE3_BARRIER_SYMBOL_ASSERT_PASS target=${target.spec.key} colour=1 read_barrier=1`);
    return;
  }
  const output = await $({stdio: 'pipe'})`objdump -drwC ${coreLib}`;
  // LLVM #96 removed GCPhase guards. The retired phase-shape write checker
  // cannot observe the new store-mask protocol. This checks only the read side;
  // source layout compatibility is checked by check-llvm-runtime-abi.sh.
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

if (!await exists(stdlibRoot, 'dir')) throw new Error(`runtime stdlib source missing: ${stdlibRoot}`);

const stage2Producer = path.join(bootstrapWork, 'cjcj-stage2');
const stage2Sha = await sha256(stage2Producer);
const assemblyLockSha = await sha256(path.join(bootstrapWork, 'sdk-stage1', 'SDK.lock.json'));
const backendIdentity = await bootstrapBackendIdentity();
const {compiler: stage2Product, targetLd} = await prepareBootstrapHandoff({
  work: bootstrapWork, sdk, source: githubWorkspace, tuple,
});
// Handoff replaces the SDK and overlays stage2 std: verify the final consumer
// before its compiler or any host tool executes.

const compilerEntrySha = await sha256(path.join(sdk, 'bin', 'cjc'));

const resourceOutput = await $({stdio: 'pipe'})`bash ${path.join(githubWorkspace, 'ci/build_resources.sh')} ${process.env.CJ_HEAP || '96GB'}`;
process.stderr.write(resourceOutput.stderr);
const resources = Object.fromEntries(resourceOutput.stdout.trim().split('\n').map(line => line.split('=')));
const stageEnv = {
  ...process.env,
  CANGJIE_HOME: sdk,
  cjHeapSize: resources.STD_BUILD_HEAP,
  [target.spec.loaderEnv]: targetLd,
  PATH: `${path.join(sdk, 'bin')}:${path.join(sdk, 'tools', 'bin')}:${process.env.PATH ?? ''}`,
};
await assertConsumerInputs(stageEnv);
await $({cwd: githubWorkspace, env: stageEnv})`set -o pipefail; cjc --version | head -2`;

const runtime = path.join(sdk, 'runtime', 'lib', tuple, target.spec.runtimeLibrary);
if (!await exists(runtime)) throw new Error(`fork runtime missing: ${runtime}`);
const runtimeKind = (await $({stdio: 'pipe'})`file -b ${runtime}`).stdout.trim();
if (!runtimeKind.includes(target.spec.fileFormat) || !runtimeKind.includes(target.spec.fileArch)) {
  throw new Error(`fork runtime has wrong native format for ${target.spec.key}: ${runtimeKind}`);
}
await assertColouredRuntime(runtime, path.join(path.resolve(requiredEnv('CJCJ_BOOTSTRAP_HOST_RT')),
  'runtime', 'lib', tuple, target.spec.runtimeLibrary));
console.log('STAGE3_RUNTIME_ASSERT_PASS colour=1');

const bootstrapCore = path.join(sdk, 'lib', tuple, 'libcangjie-std-core.a');
if (!await exists(bootstrapCore)) throw new Error(`bootstrap std core missing: ${bootstrapCore}`);
const bootstrapCoreSha = await sha256(bootstrapCore);

console.log('[stage3] rebuild final std with stage2');
if (dryRun) {
  console.log(`STAGE3_DRY_RUN_FAKE_ARTIFACTS=1 final_std=${finalStd}`);
  console.log(`[stage3][dry-run] python3 build.py clean; build -t ${stdlibBuildType} -j ${resources.STD_BUILD_JOBS} --target native --target-lib=${runtimeTarget} --target-lib=${target.spec.opensslLibDir}; install --prefix ${finalStd}`);
} else {
  await $`python3 ${path.join(githubWorkspace, 'ci/install_std_sdk_inputs.py')} ${path.dirname(process.env.CJCJ_BOOTSTRAP_AST_SUPPORT)} ${sdk} ${tuple}`;
  await fs.rm(finalStd, {recursive: true, force: true});
  await assertConsumerInputs(stageEnv);
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py clean`;
  await fs.rm(path.join(stdlibRoot, 'build', 'build'), {recursive: true, force: true});
  await assertConsumerInputs(stageEnv);
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py build -t ${stdlibBuildType} -j ${resources.STD_BUILD_JOBS} --target native --target-lib=${runtimeTarget} --target-lib=${target.spec.opensslLibDir}`;
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
  await writeStdProvenance({
    sourceDir: stdlibRoot,
    installPrefix: finalStd,
    buildSdk: sdk,
    compiler: path.join(sdk, 'bin', 'cjcj-stage2'),
  });
}

await assertFinalStd(finalStd, target, {dryRun});
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
await assertConsumerInputs(stageEnv);
if (dryRun) {
  console.log('[stage3][dry-run] cjpm clean; cjpm build -j 1');
  console.log('STAGE3_DRY_RUN_REACHED_BUILD=1');
} else {
  await checkCodegenRuntimeLayout();
  await $({cwd: githubWorkspace, env: stageEnv})`cjpm clean`;
  await prepareTrimpath(githubWorkspace);
  await $({cwd: githubWorkspace, env: stageEnv})`cjpm build -j 1`;
  const stage3Product = await findProductBinary('stage3');
  const stage3Sha = await sha256(stage3Product);
  await fs.writeFile(path.join(workspace, 'software', 'stage3-compiler.json'), `${JSON.stringify({
    compilerSha256: stage3Sha,
    parentSha256: stage2Sha,
    stdSha256: await stdIdentity(finalStd),
    stage: 'stage3',
    tuple,
    parentEntrySha256: compilerEntrySha,
    shimSha256: {
      llvm: await sha256(path.join(githubWorkspace, 'runtime_shim', 'cjselfhost_llvmshim.o')),
      runtimeConfig: await sha256(path.join(githubWorkspace, 'runtime_shim', 'cjc_runtime_config.o')),
    },
    runtimeSha256: await sha256(runtime),
    llvmManifestSha256: await sha256(path.join(requiredEnv('CJCJ_FIXED_LLVM_DIR'), 'llvm-tools.manifest')),
  }, null, 2)}\n`);
  console.log(`STAGE3_BUILD_PASS compiler=${stage3Product} sha256=${stage3Sha} input_compiler_sha256=${stage2Sha} input_std_sha256=${finalCoreSha}`);
}
