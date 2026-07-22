#!/usr/bin/env zx

import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';

const root = path.resolve(import.meta.dirname, '../../..');
const sdk = argv._[0];
if (!sdk) throw new Error('usage: verify.mjs <sdk-dir>');
const self = `${sdk}/bin/cjcj`;
const oracle = `${sdk}/bin/cjc`;
let jobs = process.env.CJCJ_VERIFY_JOBS || (await $({stdio: 'pipe'})`nproc`).stdout.trim();
if ((await $({nothrow: true})`test ${jobs} -gt 16`).exitCode === 0) jobs = '16';

await $`test -x ${self}`;
await $`test -x ${oracle}`;
process.env.CANGJIE_HOME = sdk;
process.env.PATH = `${sdk}/bin:${sdk}/tools/bin:${process.env.PATH}`;
process.env.LD_LIBRARY_PATH = `${sdk}/third_party/llvm/lib:${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/tools/lib:${process.env.LD_LIBRARY_PATH || ''}`;
process.env.cjHeapSize ||= '12GB';

const work = `${process.env.RUNNER_TEMP || '/tmp'}/cjcj-srcbuild-verify`;
await fs.rm(work, {recursive: true, force: true});
await fs.mkdir(work, {recursive: true});

console.log('[1/4] difftest: cjcj vs source-built C++ cjc');
const difftestEnv = {
  ...process.env,
  DIFFTEST_TC: sdk,
  DIFFTEST_SELF: self,
  DIFFTEST_REF: oracle,
};
await $({env: difftestEnv})`set -o pipefail; bash ${root}/scripts/difftest.sh -j ${jobs} | tee ${work}/difftest.log`;
await $`grep -Eq 'TOTAL=[0-9]+[[:space:]]+PASS=[0-9]+[[:space:]]+MISMATCH=0[[:space:]]+FAIL=0' ${work}/difftest.log`;

console.log('[2/4] deployed SDK smoke');
await $`bash ${root}/ci/smoke/run_smoke.sh ${self} ${work}/smoke`;

console.log('[3/4] compiler-package smoke (includes incremental_compilation)');
const packages = [
  'option', 'conditional_compilation', 'mangle', 'frontend_tool', 'incremental_compilation',
  'modules', 'driver', 'meta_transformation', 'lex', 'ast', 'frontend', 'cjc', 'basic', 'codegen', 'macro',
];
for (const pkg of packages) {
  console.log(`  package: ${pkg}`);
  await $`timeout 900 ${self} --package ${root}/packages/${pkg}/src --module-name cjcj --import-path ${root}/target/release --output-type=staticlib -o ${work}/${pkg}.a`;
}

console.log('[4/4] bitcode parity gate');
await $`set -o pipefail; python3 ${root}/scripts/bcgate.py --self ${self} --base ${oracle} --corpus ${root}/scripts/difftest_corpus -j ${jobs} | tee ${work}/bcgate.log`;
await $`grep -Eq 'byte-identical: [0-9]+ \\(100\\.0%\\)[[:space:]]+\\|[[:space:]]+differing: 0' ${work}/bcgate.log`;
await $`grep -Eq 'compile-errors: 0' ${work}/bcgate.log`;
const onlyOneSide = await $({nothrow: true})`grep -q 'functions present on only one side' ${work}/bcgate.log`;
if (onlyOneSide.exitCode === 0) throw new Error('bcgate failed: functions are present on only one side');
console.log('srcbuild verification: PASS');
