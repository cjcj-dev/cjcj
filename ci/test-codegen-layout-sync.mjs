#!/usr/bin/env zx
// Exercise the actual ABI entry with a stale generated frontend source.
import {fs, path, assert, repo, pin, required, run, hash, diff, replace, equalFiles, zxCommand} from './script-common.mjs';
const work = path.resolve(required(0, 'evidence directory'));
const runtime = required(1, 'runtime repository'), llvm = required(2, 'LLVM repository');
const {RUNTIME_REF} = pin(path.join(repo, 'ci/runtime_pin.env'));
const {LLVM_SHA} = pin(path.join(repo, 'ci/llvm_pin.env'));
fs.mkdirSync(path.join(work, 'product/ci'), {recursive: true});
fs.mkdirSync(path.join(work, 'product/packages/codegen/src'), {recursive: true});
for (const file of ['check-llvm-runtime-abi.mjs', 'script-common.mjs', 'generate-codegen-runtime-layout.py', 'runtime_pin.env', 'llvm_pin.env'])
  fs.copyFileSync(path.join(repo, 'ci', file), path.join(work, 'product/ci', file));
const output = path.join(work, 'product/packages/codegen/src/RuntimeLayout.cj');
fs.copyFileSync(path.join(repo, 'packages/codegen/src/RuntimeLayout.cj'), output);
fs.copyFileSync(output, path.join(work, 'original.cj'));
const check = arm => run([...zxCommand(path.join(work, 'product/ci/check-llvm-runtime-abi.mjs')),
  '--runtime-repo', runtime, '--runtime-ref', RUNTIME_REF, '--llvm-repo', llvm, '--llvm-ref', LLVM_SHA], {log: path.join(work, `${arm}.log`), check: false});
assert.equal((await check('candidate')).exitCode, 0);
await hash([output], path.join(work, 'candidate.sha256'));
replace(output, 'instanceSizeIndex: Int64 = 4', 'instanceSizeIndex: Int64 = 6');
await diff(path.join(work, 'original.cj'), output, path.join(work, 'cut.diff'));
await hash([output], path.join(work, 'cut.sha256'));
const cut = await check('cut');
console.log(`ASSERT generated_source_stale actual_rc=${cut.exitCode} expected_rc=1`);
assert.equal(cut.exitCode, 1);
assert.match(cut.stdall, /CODEGEN_LAYOUT=STALE generated source differs:/);
process.stdout.write(cut.stdall.split('\n').filter(line => line.includes('CODEGEN_LAYOUT=STALE')).join('\n') + '\n');
fs.copyFileSync(path.join(work, 'original.cj'), output);
assert.equal((await check('restored')).exitCode, 0);
await hash([output], path.join(work, 'restored.sha256'));
equalFiles(path.join(work, 'candidate.sha256'), path.join(work, 'restored.sha256'));
console.log('ASSERT generated_source_sync candidate_rc=0 cut_rc=1 restored_rc=0');
