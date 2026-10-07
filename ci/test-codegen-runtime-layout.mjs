#!/usr/bin/env zx
// Real frontend -> bitcode -> independent LLVM DataLayout/IR assertions.
import {fs, path, repo, pin, required, run, capture, hash, equalFiles, cliArgs, isMain} from './script-common.mjs';
import {resolveRuntimeSource} from './runtime-pin.mjs';
import os from 'node:os';
let compiler = required(0, 'candidate compiler');
const sdk = required(1, 'host SDK'), llvmLibrary = required(2, 'paired libLLVM');
const llvmRepo = required(3, 'paired LLVM source'), runtimeRepo = required(4, 'paired runtime source');
const work = path.resolve(required(5, 'evidence directory'));
const {LLVM_SHA} = pin(path.join(repo, 'ci/llvm_pin.env'));
const selection = await resolveRuntimeSource(process.env, cliArgs[6] || process.env.CJCJ_BOOTSTRAP_RUNTIME_PIN || path.join(repo, 'ci/runtime_pin.env'));
const RUNTIME_REF = selection.runtimeRef;
fs.mkdirSync(path.join(work, 'frontend'), {recursive: true});
fs.copyFileSync(compiler, path.join(work, 'frontend/cjcj-stage1'));
equalFiles(compiler, path.join(work, 'frontend/cjcj-stage1'));
const frontend = path.join(work, 'frontend/cjc-frontend');
fs.rmSync(frontend, {force: true});
fs.symlinkSync('cjcj-stage1', frontend);
compiler = frontend;
await run(['npx', '--yes', 'zx@8', path.join(repo, 'ci/check-llvm-runtime-abi.mjs'), '--llvm-repo', llvmRepo, '--llvm-ref', LLVM_SHA,
  '--runtime-repo', runtimeRepo, '--runtime-ref', RUNTIME_REF], {log: path.join(work, 'pairing.log')});
const header = path.join(work, 'CangjieRuntimeLayout.h');
fs.writeFileSync(header, (await capture(['git', '-C', llvmRepo, 'show', `${LLVM_SHA}:llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h`])).stdout);
fs.mkdirSync(path.join(work, 'core'), {recursive: true});
const archive = path.join(work, 'runtime-core.tar');
await run(['git', '-C', runtimeRepo, 'archive', '-o', archive, RUNTIME_REF, 'stdlib/libs/std/core']);
await run(['tar', '-xf', archive, '-C', path.join(work, 'core')]);
const actualRuntimeRef = (await capture(['git', 'get-tar-commit-id'], {input: fs.readFileSync(archive)})).stdout.trim();
fs.writeFileSync(path.join(work, 'runtime-source.sha'), `${actualRuntimeRef}\n`);
if (actualRuntimeRef !== RUNTIME_REF.toLowerCase()) {
  console.error(`LAYOUT_IR_RUNTIME_SOURCE_MISMATCH expected=${RUNTIME_REF} actual=${actualRuntimeRef}`); process.exit(1);
}
await hash([archive], path.join(work, 'runtime-core.sha256'));
fs.unlinkSync(archive);
console.log(`LAYOUT_IR_RUNTIME_SOURCE_VERIFIED expected=${RUNTIME_REF} actual=${actualRuntimeRef}`);
const core = path.join(work, 'core/stdlib/libs/std/core');
fs.copyFileSync(path.join(repo, 'tests/runtime_layout/raw.cj'), path.join(core, 'layout_contract.cj'));
Object.assign(process.env, {CANGJIE_HOME: sdk,
  LD_LIBRARY_PATH: `${path.dirname(llvmLibrary)}:${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/lib/linux_x86_64_cjnative:${sdk}/third_party/llvm/lib:${sdk}/tools/lib`, cjHeapSize: '32GB'});
const jobs = (await capture(['nproc'])).stdout.trim();
await run(['uptime'], {log: path.join(work, 'uptime-before.txt')});
await hash([compiler, llvmLibrary, header, path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'),
  path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libboundscheck.so')], path.join(work, 'inputs.sha256'));
const start = Date.now();
let rc = 0;
for (const surface of ['objects', 'arrays']) {
  const directory = path.join(work, surface);
  fs.mkdirSync(directory, {recursive: true});
  const args = surface === 'arrays' ? ['-p', core, '--no-sub-pkg', '--no-prelude'] : [path.join(repo, 'tests/runtime_layout/layout.cj'), '-g'];
  const compile = await run(['timeout', '900', compiler, ...args, '--output-type=staticlib', surface === 'arrays' ? '-O2' : '-O0', '--apc=1', '--jobs', jobs,
    '-o', path.join(directory, 'layout.bc')], {log: path.join(directory, 'compile.log'), check: false});
  fs.writeFileSync(path.join(directory, 'compile.rc'), `${compile.exitCode}\n`);
  let verifyRc = 'NOT_RUN';
  if (compile.exitCode === 0) {
    await hash([path.join(directory, 'layout.bc')], path.join(directory, 'bitcode.sha256'));
    const verify = await run(['python3', path.join(repo, 'ci/verify-codegen-runtime-layout.py'), '--surface', surface,
      '--llvm-library', llvmLibrary, '--header', header, '--bitcode', path.join(directory, 'layout.bc'), '--result', path.join(directory, 'result.json')], {log: path.join(directory, 'verify.log'), check: false});
    verifyRc = verify.exitCode;
  }
  fs.writeFileSync(path.join(directory, 'verify.rc'), `${verifyRc}\n`);
  console.log(`LAYOUT_IR surface=${surface} compile_rc=${compile.exitCode} verify_rc=${verifyRc}`);
  if (compile.exitCode !== 0 || verifyRc !== 0) rc = 1;
}
await run(['uptime'], {log: path.join(work, 'uptime-after.txt')});
fs.writeFileSync(path.join(work, 'result.txt'), `rc=${rc} wall=${Math.floor((Date.now() - start) / 1000)} jobs=${jobs}\n`);
process.exitCode = rc;
