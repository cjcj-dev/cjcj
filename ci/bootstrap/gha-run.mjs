#!/usr/bin/env zx
import path from 'node:path';
import {spawn} from 'node:child_process';
import {prepareBootstrapEnvironment} from './prepare-bootstrap-plans.mjs';
import {fileURLToPath} from 'node:url';

export async function runBootstrapJob(stage, env = process.env) {
  const required = name => { if (!env[name]) throw new Error(`${name} is required`); return env[name]; };
  const root = required('GITHUB_WORKSPACE'), workspace = required('CANGJIE_WORKSPACE');
  if (!['stage0', 'stage1-initial-std', 'stage1-std', 'stage1-compiler'].includes(stage)) throw new Error(`unknown bootstrap job ${stage}`);
  const argumentsByInput = {
    '--runtime-pin': 'CJCJ_BOOTSTRAP_RUNTIME_PIN', '--cjcj-sha': 'CJCJ_BOOTSTRAP_CJCJ_SHA',
    '--cpp-src': 'CJCJ_BOOTSTRAP_CPP_SRC', '--base': 'CJCJ_BOOTSTRAP_BASE',
    '--host-llvm-so': 'CJCJ_BOOTSTRAP_HOST_LLVM_SO', '--host-llvm-sha256': 'CJCJ_BOOTSTRAP_HOST_LLVM_SHA256',
    '--colour-llvm-so': 'CJCJ_BOOTSTRAP_COLOUR_LLVM_SO', '--colour-llvm-sha256': 'CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256',
    '--ast-support': 'CJCJ_BOOTSTRAP_AST_SUPPORT', '--ast-support-sha256': 'CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256',
    '--colour-tuple': 'CJCJ_BOOTSTRAP_COLOUR_TUPLE', '--colour-llvm-sha': 'CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA',
    '--colour-rt': 'CJCJ_BOOTSTRAP_COLOUR_RT', '--host-rt': 'CJCJ_BOOTSTRAP_HOST_RT',
  };
  const inputs = Object.entries(argumentsByInput).flatMap(([flag, name]) => [flag, required(name)]);
  const {plans} = await prepareBootstrapEnvironment(env);
  const childEnv = {...env, CJCJ_BOOTSTRAP_SDK_PLANS: plans,
    SDK_BUILD: path.join(root, 'ci/bootstrap/sdk_build.sh'),
    STAGE0_CACHE_ROOT: env.STAGE0_CACHE_ROOT || path.join(workspace, 'stage0depot')};
  delete childEnv.CJCJ_BOOTSTRAP_SDK_INTENTS;
  // Generation/validation has finished before the dispatcher can build.
  return new Promise((resolve, reject) => {
    const child = spawn('bash', [path.join(root, 'ci/bootstrap/bootstrap.sh'),
      '--work', path.join(workspace, 'bootstrap-work'), '--src', root,
      '--stdsrc', path.join(workspace, 'cangjie_runtime/stdlib'), '--sdk-plans', plans,
      ...inputs, '--stage', stage], {env: childEnv, stdio: 'inherit'});
    child.once('error', reject);
    child.once('exit', (rc, signal) => resolve({rc, signal}));
  });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await runBootstrapJob(process.argv[2]);
    if (result.signal) throw new Error(`bootstrap job signal=${result.signal}`);
    process.exitCode = result.rc;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
