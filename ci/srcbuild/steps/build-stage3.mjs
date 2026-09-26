#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {countSdkLoadBadMask, readRuntimeSymbols} from '../../../build/lib/runtime-split.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';
import {resolveProductBinary} from '../lib/product-binary.mjs';
import {prepareBootstrapHandoff} from '../lib/bootstrap-handoff.mjs';
import {stdIdentity, payloadIdentity} from '../lib/final-compiler.mjs';
import {installStage3Compiler} from '../lib/compose-install.mjs';
import {captureBuildInputs, finishBuildReceipt, sourceIdentity} from '../lib/source-build-receipt.mjs';
import {assertWriteBarriers} from '../lib/write-barrier.mjs';

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

async function assertBuildCompiler(stageEnv, expectedSha, nativeName = 'cjcj-stage2', entrySha = compilerEntrySha) {
  const installed = path.join(sdk, 'bin', nativeName);
  const linked = path.join(sdk, 'bin', 'cjc');
  const resolvedLink = await fs.realpath(linked);
  const resolvedInstalled = await fs.realpath(installed);
  const command = await $({cwd: githubWorkspace, env: stageEnv, stdio: 'pipe'})`command -v cjc`;
  const resolvedCommand = await fs.realpath(command.stdout.trim());
  const installedSha = await sha256(installed);
  if (resolvedCommand !== resolvedLink || installedSha !== expectedSha || await sha256(linked) !== entrySha) {
    throw new Error(`build compiler assertion failed: link=${resolvedLink}, command=${resolvedCommand}, expected=${resolvedInstalled}, sha=${installedSha}`);
  }
  console.log(`STAGE3_COMPILER_ASSERT_PASS path=${resolvedInstalled} sha256=${installedSha}`);
}

// The SDK ships llvm-objdump; failing when it is absent keeps this from quietly
// becoming a no-op on a host that happens not to have one.
async function assertWriteBarriersWith(sdkRoot, coreLib, targetSpec) {
  const tool = path.join(sdkRoot, 'third_party', 'llvm', 'bin', 'llvm-objdump');
  if (!await exists(tool)) throw new Error(`write-barrier check needs llvm-objdump: ${tool}`);
  const dump = await $({stdio: 'pipe'})`${tool} -d -r -C ${coreLib}`;
  return assertWriteBarriers(dump.stdout, `target=${targetSpec.spec.key} core=${path.basename(coreLib)}`);
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
    // Deliberate, and on stderr so it does not sit in the stream of green lines.
    // The disassembler is no longer the reason: llvm-objdump reads aarch64 and
    // Mach-O, and the write-side analyser now runs off it. What is still missing
    // is a real aarch64 std archive to check the phase-check shape against --
    // `lsr x9, x28, #56` is readable in AArch64AsmPrinter but has never been put
    // through a two-armed check, and a fixture I write myself would only prove my
    // own regex reads my own text. No verdict here until that exists.
    console.error(`STAGE3_WRITE_BARRIER_SKIP target=${target.spec.key} reason=aarch64-shape-never-validated-against-a-real-archive`);
    console.error('STAGE3_WRITE_BARRIER_SKIP no write-side conclusion on this target — not a pass');
    return;
  }
  const output = await $({stdio: 'pipe'})`objdump -drwC ${coreLib}`;
  // Everything below proves the read side: the tag test and a CJ_MCC_Read* call.
  // A std built with colouring but without the generational post barrier passes
  // all of it, which is exactly the shape the pinned llc produces by default, so
  // the write side is checked too -- but off llvm-objdump, not this output.
  //
  // Why a second disassembly rather than reusing this one: llvm-objdump is the
  // only one of the two that reads aarch64 and Mach-O, and running the write-side
  // patterns against one dialect everywhere is worth a few seconds. The two tools
  // were measured to agree exactly on the four write-side columns for both a stock
  // and a source-built core (426/14/7/405 and 19/19/0/0), with a control arm that
  // does diverge when one side is given wrong flags.
  //
  // The read side below stays on GNU objdump on purpose: its `shr $0x30` probe is
  // written in GNU's radix and llvm-objdump spells the same instruction `shrq $48`.
  // The equivalence measured above covers the write-side analyser only, so moving
  // the read side too would be changing a validated check on unvalidated grounds.
  await assertWriteBarriersWith(sdk, coreLib, target);
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

const {compiler: stage2Product, targetLd} = await prepareBootstrapHandoff({
  work: bootstrapWork, sdk, source: githubWorkspace, tuple,
});
const stage2Sha = await sha256(stage2Product);
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

const runtime = path.join(sdk, 'runtime', 'lib', tuple, target.spec.runtimeLibrary);
if (!await exists(runtime)) throw new Error(`fork runtime missing: ${runtime}`);
const runtimeKind = (await $({stdio: 'pipe'})`file -b ${runtime}`).stdout.trim();
if (!runtimeKind.includes(target.spec.fileFormat) || !runtimeKind.includes(target.spec.fileArch)) {
  throw new Error(`fork runtime has wrong native format for ${target.spec.key}: ${runtimeKind}`);
}
// Check the loader input before starting the managed compiler. Diagnostic text
// markers were removed from runtime main; use the same exported ABI reader as
// compose-sdk and bind its bytes to the separately pinned runtime manifest.
const maskCount = countSdkLoadBadMask(readRuntimeSymbols(runtime, target), target);
if (maskCount !== 1) throw new Error(`STAGE3_RUNTIME_COLOUR_ABI_MISMATCH symbol=g_cjLoadBadMask count=${maskCount}`);
const runtimeManifest = path.join(requiredEnv('CJCJ_BOOTSTRAP_COLOUR_RT'), 'manifest.json');
const runtimeManifestPin = requiredEnv('COLOUR_RT_MANIFEST_SHA256');
const runtimeManifestSha = await sha256(runtimeManifest);
if (!/^[0-9a-f]{64}$/.test(runtimeManifestPin) || runtimeManifestSha !== runtimeManifestPin) {
  throw new Error(`STAGE3_RUNTIME_MANIFEST_MISMATCH expected=${runtimeManifestPin} actual=${runtimeManifestSha}`);
}
const runtimeIdentity = JSON.parse(await fs.readFile(runtimeManifest, 'utf8'));
const runtimeSha = await sha256(runtime);
if (runtimeIdentity.runtime_sha !== requiredEnv('RUNTIME_REF')
    || runtimeIdentity.files?.[`runtime/lib/${tuple}/${target.spec.runtimeLibrary}`] !== runtimeSha) {
  throw new Error('STAGE3_RUNTIME_SOURCE_OR_PAYLOAD_MISMATCH');
}
console.log(`STAGE3_RUNTIME_ASSERT_PASS symbol=g_cjLoadBadMask count=${maskCount} source=${runtimeIdentity.runtime_sha} runtime_sha256=${runtimeSha} manifest_sha256=${runtimeManifestSha}`);
await assertBuildCompiler(stageEnv, stage2Sha);
await $({cwd: githubWorkspace, env: stageEnv})`set -o pipefail; cjc --version | head -2`;

const bootstrapCore = path.join(sdk, 'lib', tuple, 'libcangjie-std-core.a');
if (!await exists(bootstrapCore)) throw new Error(`bootstrap std core missing: ${bootstrapCore}`);
const bootstrapCoreSha = await sha256(bootstrapCore);

// Stage2 is a pinned bootstrap input, not the compiler shipped with the std.
// Keep a validated compiler checkpoint so a continuation can resume std alone.
const phase = process.env.CJCJ_STAGE3_PHASE || 'all';
if (!['all', 'compiler', 'std'].includes(phase) || (dryRun && phase !== 'all')) {
  throw new Error('CJCJ_STAGE3_PHASE must be all, compiler or std; dry-run supports all');
}
const checkpoint = path.join(workspace, 'software', 'stage3-bootstrap.json');
const retainedProduct = path.join(workspace, 'software', 'stage3-compiler');
const parentStd = path.join(bootstrapWork, 'stdlib-stage2');
const linkStdSha256 = await payloadIdentity(parentStd);
if (await payloadIdentity(sdk, parentStd) !== linkStdSha256) throw new Error('stage3 bootstrap std installation mismatch');
let stage3Lineage;
if (dryRun) {
  console.log('[stage3][dry-run] build stage3 with stage2, then rebuild shipped std with stage3');
} else if (phase === 'std') {
  stage3Lineage = JSON.parse(await fs.readFile(checkpoint, 'utf8'));
  if (await sha256(retainedProduct) !== stage3Lineage.compilerSha256
      || stage3Lineage.parentSha256 !== stage2Sha || stage3Lineage.linkStdSha256 !== linkStdSha256
      || stage3Lineage.runtimeSha256 !== runtimeSha
      || stage3Lineage.runtimeManifestSha256 !== runtimeManifestSha
      || stage3Lineage.llvmManifestSha256 !== await sha256(path.join(requiredEnv('CJCJ_FIXED_LLVM_DIR'), 'llvm-tools.manifest'))
      || stage3Lineage.llvmLibrarySha256 !== await sha256(path.join(sdk, 'third_party', 'llvm', 'lib', target.spec.os === 'darwin' ? 'libLLVM.dylib' : 'libLLVM-15.so'))
      || JSON.stringify(stage3Lineage.source) !== JSON.stringify(sourceIdentity(path.join(githubWorkspace, 'packages')))) {
    throw new Error('stage3 std resume checkpoint identity mismatch');
  }
} else {
  const source = sourceIdentity(path.join(githubWorkspace, 'packages'));
  // The C provenance object must be rebuilt for this compiler source, rather
  // than retaining the older bootstrap compiler's embedded commit stamp.
  await $({cwd: githubWorkspace, env: {...stageEnv,
    CANGJIE_CPP_SRC: path.join(workspace, 'cangjie_compiler'), CJCJ_COMMIT: source.commit,
    CANGJIE_HOME: '', // Compile the objects without creating a shared runtime symlink.
    CJCJ_LLVM_SHIM_O: path.join(requiredEnv('CJCJ_FIXED_LLVM_DIR'), 'cjselfhost_llvmshim.o')}})
    `npx --yes zx@8 ${path.join(githubWorkspace, 'runtime_shim', 'build_shim.mjs')}`;
  await $({cwd: githubWorkspace, env: stageEnv})`cjpm clean`;
  const buildRuntime = path.join(githubWorkspace, 'target', 'release', 'runtime');
  await fs.rm(buildRuntime, {recursive: true, force: true});
  await fs.cp(path.join(sdk, 'runtime'), buildRuntime, {recursive: true, dereference: true});
  await $({cwd: githubWorkspace, env: {...stageEnv, cjHeapSize: '20GB'}})`cjpm build -j 1`;
  if (JSON.stringify(sourceIdentity(path.join(githubWorkspace, 'packages'))) !== JSON.stringify(source)) {
    throw new Error('stage3 compiler source changed during build');
  }
  const product = await findProductBinary('stage3');
  await fs.copyFile(product, retainedProduct);
  await fs.chmod(retainedProduct, 0o755);
  stage3Lineage = {
    compilerSha256: await sha256(retainedProduct), parentSha256: stage2Sha,
    bootstrap: {parentSource: sourceIdentity(path.join(bootstrapWork, 'cjcj-src-stage1', 'packages'))},
    linkStdSha256, stage: 'stage3', source, tuple, parentEntrySha256: compilerEntrySha,
    projectSha256: await sha256(path.join(githubWorkspace, 'cjpm.toml')),
    llvmLibrarySha256: await sha256(path.join(sdk, 'third_party', 'llvm', 'lib', target.spec.os === 'darwin' ? 'libLLVM.dylib' : 'libLLVM-15.so')),
    shimSha256: {llvm: await sha256(path.join(githubWorkspace, 'runtime_shim', 'cjselfhost_llvmshim.o')),
      runtimeConfig: await sha256(path.join(githubWorkspace, 'runtime_shim', 'cjc_runtime_config.o'))},
    runtimeSha256: runtimeSha, runtimeManifestSha256: runtimeManifestSha,
    llvmManifestSha256: await sha256(path.join(requiredEnv('CJCJ_FIXED_LLVM_DIR'), 'llvm-tools.manifest')),
  };
  await fs.writeFile(checkpoint, `${JSON.stringify(stage3Lineage, null, 2)}\n`);
  console.log(`STAGE3_COMPILER_RETAINED path=${retainedProduct} sha256=${stage3Lineage.compilerSha256} source=${source.commit}`);
}
if (phase === 'compiler') process.exit(0);
if (!dryRun) await installStage3Compiler({sdk, product: retainedProduct, lineage: stage3Lineage});
const stdCompilerName = dryRun ? 'cjcj-stage2' : 'cjcj-stage1';
const stdCompilerSha = dryRun ? stage2Sha : stage3Lineage.compilerSha256;
const stdEntrySha = dryRun ? compilerEntrySha : stdCompilerSha;

// Record inputs before the compiler runs. The receipt travels with final-std,
// and stdIdentity binds it into the final compiler's existing handoff manifest.
const stdBuildInputs = dryRun ? null : await captureBuildInputs({
  source: stdlibRoot,
  files: {
    stage3Recipe: new URL(import.meta.url),
    receiptRecipe: new URL('../lib/source-build-receipt.mjs', import.meta.url),
    stdRecipe: path.join(stdlibRoot, 'build.py'),
    compiler: path.join(sdk, 'bin', stdCompilerName),
    compilerEntry: path.join(sdk, 'bin', 'cjc'),
    compilerProject: path.join(githubWorkspace, 'cjpm.toml'),
    llvmLibrary: path.join(sdk, 'third_party', 'llvm', 'lib', target.spec.os === 'darwin' ? 'libLLVM.dylib' : 'libLLVM-15.so'),
    llc: path.join(sdk, 'third_party', 'llvm', 'bin', 'llc-stage1'),
    opt: path.join(sdk, 'third_party', 'llvm', 'bin', 'opt-stage1'),
    runtime,
    boundscheck: path.join(runtimeTarget, `libboundscheck${target.spec.sharedLibrarySuffix}`),
    llvmManifest: path.join(requiredEnv('CJCJ_FIXED_LLVM_DIR'), 'llvm-tools.manifest'),
  },
  recipe: {buildType: stdlibBuildType, target: target.spec.key,
    commands: ['python3 build.py clean',
      `python3 build.py build -t ${stdlibBuildType} --target native --target-lib=${runtimeTarget} --target-lib=${target.spec.opensslLibDir}`,
      `python3 build.py install --prefix ${finalStd}`]},
});
if (!dryRun) {
  stdBuildInputs.compilerSource = stage3Lineage.source;
  stdBuildInputs.bootstrapStd = JSON.parse(await fs.readFile(path.join(bootstrapWork, 'stdlib-stage1', 'BOOTSTRAP-STD.json'), 'utf8'));
}
console.log('[stage3] rebuild final std with shipped stage3 compiler');
if (dryRun) {
  console.log(`STAGE3_DRY_RUN_FAKE_ARTIFACTS=1 final_std=${finalStd}`);
  console.log(`[stage3][dry-run] python3 build.py clean; build -t ${stdlibBuildType} -j ${resources.STD_BUILD_JOBS} --target native --target-lib=${runtimeTarget} --target-lib=${target.spec.opensslLibDir}; install --prefix ${finalStd}`);
} else {
  await $`python3 ${path.join(githubWorkspace, 'ci/install_std_sdk_inputs.py')} ${path.dirname(process.env.CJCJ_BOOTSTRAP_AST_SUPPORT)} ${sdk} ${tuple}`;
  await fs.rm(finalStd, {recursive: true, force: true});
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py clean`;
  await fs.rm(path.join(stdlibRoot, 'build', 'build'), {recursive: true, force: true});
  await assertBuildCompiler(stageEnv, stdCompilerSha, stdCompilerName, stdEntrySha);
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py build -t ${stdlibBuildType} -j ${resources.STD_BUILD_JOBS} --target native --target-lib=${runtimeTarget} --target-lib=${target.spec.opensslLibDir}`;
  await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
  await writeStdProvenance({
    sourceDir: stdlibRoot,
    installPrefix: finalStd,
    buildSdk: sdk,
    compiler: path.join(sdk, 'bin', stdCompilerName),
  });
}

await assertFinalStd(finalStd, target, {dryRun});
const finalCore = path.join(finalStd, 'lib', tuple, 'libcangjie-std-core.a');
const finalCoreSha = await sha256(finalCore);
if (finalCoreSha === bootstrapCoreSha && allowIdenticalStdValue !== '1') {
  throw new Error('stage3-built std is byte-identical to bootstrap std; provenance is inconclusive (set CJCJ_STAGE3_ALLOW_IDENTICAL_STD=1 only after independent proof)');
}
if (!dryRun) {
  await assertStdBarriers(finalCore);
  await finishBuildReceipt({source: stdlibRoot, captured: stdBuildInputs,
    output: path.join(finalStd, 'SOURCE-BUILD.json'), artifacts: {core: finalCore}});
}

for (const entry of await fs.readdir(finalStd)) {
  await fs.cp(path.join(finalStd, entry), path.join(sdk, entry), {recursive: true, force: true});
}
const consumedCoreSha = await sha256(bootstrapCore);
if (consumedCoreSha !== finalCoreSha) {
  throw new Error(`SDK did not consume final std: sdk=${consumedCoreSha}, final=${finalCoreSha}`);
}
console.log(`STAGE3_STD_INPUT_ASSERT_PASS bootstrap_sha256=${bootstrapCoreSha} final_sha256=${finalCoreSha} sdk_sha256=${consumedCoreSha}`);

if (dryRun) {
  console.log('STAGE3_DRY_RUN_REACHED_BUILD=1');
} else {
  const lineage = {...stage3Lineage, stdSha256: await stdIdentity(finalStd),
    stdCompilerSha256: stdCompilerSha};
  await fs.writeFile(path.join(workspace, 'software', 'stage3-compiler.json'), `${JSON.stringify(lineage, null, 2)}\n`);
  console.log(`STAGE3_BUILD_PASS compiler=${retainedProduct} sha256=${lineage.compilerSha256} std_compiler_sha256=${stdCompilerSha} std_sha256=${lineage.stdSha256}`);
}
