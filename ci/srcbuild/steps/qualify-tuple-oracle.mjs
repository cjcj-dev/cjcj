#!/usr/bin/env zx
// Explicit source-tuple oracle qualification; the default SDK verifier owns
// lineage/smoke/selfcheck/selfdet and has no oracle prerequisite (#357).
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {getTarget} from '../../../build/lib/targets.mjs';
import {runGrepProbe} from '../../../build/lib/fail-closed-probes.mjs';
import {selectOfficialOracle} from '../lib/official-oracle.mjs';
$.stdio = 'inherit';
const [sdkArg, outputArg] = argv._.map(String);
if (!sdkArg || !outputArg) throw new Error('usage: qualify-tuple-oracle.mjs SDK OUTPUT');
const sdk = path.resolve(sdkArg);
const work = path.resolve(outputArg);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const target = getTarget(process.env.CJCJ_SRCBUILD_TARGET);
const self = path.join(sdk, 'bin/cjc');
await fs.mkdir(work, {recursive: false});
async function phase(name, run) {
  console.log(`[tuple-oracle] phase=${name}`);
  await run();
}
const official = await selectOfficialOracle({
  sdk: process.env.CJCJ_SRCBUILD_BOOTSTRAP_SDK,
  target, toolchain: process.env.CJCJ_TOOLCHAIN,
  compilerSha256: process.env.CJCJ_HOST_CJC_SHA256,
  runtimeSha256: process.env.CJCJ_HOST_RUNTIME_SHA256,
  boundscheckSha256: process.env.CJCJ_HOST_BOUNDSCHECK_SHA256,
  hostLlvm: process.env.CJCJ_BOOTSTRAP_HOST_LLVM_SO,
  hostLlvmSha256: process.env.CJCJ_BOOTSTRAP_HOST_LLVM_SHA256,
});
const oracle = official.compiler;
let jobs = Number(process.env.CJCJ_VERIFY_JOBS || os.cpus().length || 1);
if (!Number.isSafeInteger(jobs) || jobs < 1) throw new Error(`invalid CJCJ_VERIFY_JOBS: ${process.env.CJCJ_VERIFY_JOBS}`);
jobs = String(Math.min(jobs, 16));
await phase('difftest', async () => {
  console.log('[difftest] compare selfhost SDK and pinned official bootstrap oracle');
  const difftestEnv = {
    ...process.env,
    DIFFTEST_TC: official.sdk,
    DIFFTEST_SELF_TC: sdk,
    DIFFTEST_REF_LD: official.env[target.spec.loaderEnv],
    CJ_HOST_RTLIB: '',
    DIFFTEST_SELF: self,
    DIFFTEST_REF: oracle,
  };
  await $({env: difftestEnv})`set -o pipefail; npx --yes zx@8 ${root}/scripts/difftest.mjs -j ${jobs} | tee ${work}/difftest.log`;
  await $`grep -Eq 'TOTAL=[0-9]+[[:space:]]+PASS=[0-9]+[[:space:]]+MISMATCH=0[[:space:]]+FAIL=0' ${work}/difftest.log`;
});

await phase('bcgate', async () => {
  console.log('[bcgate] verify bitcode parity');
  await $({env: {...process.env, CJ_HOST_RTLIB: '', BCGATE_BASE_HOME: official.sdk, BCGATE_BASE_LD_LIBRARY_PATH: official.env[target.spec.loaderEnv]}})`set -o pipefail; python3 ${root}/scripts/bcgate.py --self ${self} --base ${oracle} --corpus ${root}/scripts/difftest_corpus -j ${jobs} | tee ${work}/bcgate.log`;
  await $`grep -Eq 'byte-identical: [0-9]+ \\(100\\.0%\\)[[:space:]]+\\|[[:space:]]+differing: 0' ${work}/bcgate.log`;
  await $`grep -Eq 'compile-errors: 0' ${work}/bcgate.log`;
  const onlyOneSide = await runGrepProbe({
    label: 'bcgate one-side divergence grep',
    run: () => $({nothrow: true})`grep -q 'functions present on only one side' ${work}/bcgate.log`,
  });
  if (onlyOneSide.matched) throw new Error('bcgate failed: functions are present on only one side');
});

console.log('TUPLE_ORACLE_QUALIFIED');
