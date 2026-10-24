#!/usr/bin/env zx
// CI consumes the same native target/install graph as srcbuild. The state file
// only locates an installation; installed bytes and stage facts are re-read.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {configureGhaInputs} from './bootstrap/configure-gha-inputs.mjs';
import {prepareBootstrapEnvironment} from './bootstrap/prepare-bootstrap-plans.mjs';
import {atomicJson, privateRoot, readJson} from './bootstrap/sdk-flow.mjs';
import {cleanSdkEnvironment, sdkPlatform} from './bootstrap/sdk-platform.mjs';
import {installedStageOutput} from './srcbuild/lib/installed-stage-output.mjs';
import {hostPlatform} from './host-toolchain-pin.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const stateFile = path.join(repo, '.platform-ci', 'colour-sdk.json');
const finalStages = new Set(['stage2-target-sdk', 'stage3']);
function paired(platform, runtime, env) {
  if (platform !== hostPlatform()) throw new Error('COLOUR_SDK_PLATFORM_MISMATCH');
  if (!/^[a-f0-9]{40}$/.test(runtime || '') || runtime !== env.RUNTIME_REF)
    throw new Error(`COLOUR_RT_STATE_MISMATCH: installed/configured runtime=${runtime} required=${env.RUNTIME_REF}`);
}
async function installed(sdk, stage, env) {
  if (!finalStages.has(stage)) throw new Error('COLOUR_SDK_FINAL_STAGE_REQUIRED');
  const output = await installedStageOutput(sdk, stage);
  paired(output.lineage.platform, output.lineage.runtimeCommit, env);
  return output;
}
export async function prepareColourSdk(nativeInputs, env = process.env) {
  const selected = {...env};
  if (!selected.CJCJ_SDK_TARGETS && !selected.CJCJ_SDK_INPUTS && !selected.CJCJ_NATIVE_INPUTS) {
    selected.CJCJ_NATIVE_INPUT_ROOT = nativeInputs || selected.CJCJ_NATIVE_INPUT_ROOT;
    selected.CJCJ_BOOTSTRAP_BASE ||= selected.CANGJIE_HOME;
    selected.CJCJ_SDK_INPUTS = await configureGhaInputs(selected);
  }
  const {config} = await prepareBootstrapEnvironment(selected);
  const targets = await readJson(config);
  const {platform, runtime} = targets.bootstrapInputs;
  paired(platform, runtime.commit, selected);
  if (!finalStages.has(targets.finalStage)) throw new Error('COLOUR_SDK_FINAL_STAGE_REQUIRED');
  const sdk = await privateRoot(targets.install);
  const result = spawnSync(process.execPath, [path.join(repo, 'ci/bootstrap/sdk-build.mjs'),
    '--config', config, '--no-package'], {stdio: 'inherit', env: selected});
  if (result.status !== 0) throw Object.assign(new Error(`COLOUR_SDK_BUILD rc=${result.status} signal=${result.signal}`), {rc: result.status ?? 1});
  return selectInstalledColourSdk(sdk, selected);
}
export async function selectInstalledColourSdk(sdk, env = process.env) {
  sdk = await privateRoot(sdk);
  const metadata = await readJson(path.join(sdk, 'STAGE-INPUTS.json'));
  const output = await installed(sdk, metadata.phase, env);
  const {verifyInstall} = await import('./bootstrap/sdk-verify-install.mjs');
  await verifyInstall({sdk, platform: metadata.platform, finalStd: true,
    work: path.join(path.dirname(stateFile), 'installed-sdk-check')});
  const platform = metadata.platform, tuple = output.platform.tuple;
  const state = {sdk, host: path.join(sdk, '.host'), platform, tuple,
    runtime: path.join(sdk, 'runtime/lib', tuple), runtime_sha: metadata.runtimeCommit,
    stage: metadata.phase, compiler_sha256: output.lineage.compilerSha256};
  await atomicJson(stateFile, state);
  if (env.GITHUB_ENV) await fs.appendFile(env.GITHUB_ENV,
    `CJCJ_TARGET_SDK=${sdk}\nCJCJ_HOST_SDK=${state.host}\nCJCJ_PATCHED_RUNTIME_LIB_DIR=${state.runtime}\n`);
  console.log(`COLOUR_SDK ${JSON.stringify(state)}`);
  return state;
}
export async function colourEnvironment(mode, env = process.env) {
  if (!['build', 'run'].includes(mode)) throw new Error('COLOUR_SDK_MODE');
  const state = await readJson(stateFile);
  paired(state.platform, state.runtime_sha, env);
  const output = await installed(state.sdk, state.stage, env);
  if (state.compiler_sha256 !== output.lineage.compilerSha256) throw new Error('COLOUR_SDK_COMPILER_CHANGED');
  const runtime = path.join(state.sdk, 'runtime/lib', output.platform.tuple);
  // Native compiler entries select their own .host/.compiler-exec domain. Both
  // workspace builds and target runs use the installed target std and libraries.
  return {...cleanSdkEnvironment(state.sdk, state.platform, env),
    CJCJ_PATCHED_LLVM_BIN: path.join(state.sdk, 'third_party/llvm/bin'),
    CJCJ_LLVM_SHIM_O: path.join(state.sdk, 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o'),
    CJCJ_LLVM_LINK_RSP: '',
    CJCJ_TARGET_SDK: state.sdk, CJCJ_HOST_SDK: path.join(state.sdk, '.host'),
    CJCJ_PATCHED_RUNTIME_LIB_DIR: runtime};
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { await prepareColourSdk(process.argv[2]); }
  catch (error) { console.error(error.stack); process.exitCode = error.rc || 1; }
}
