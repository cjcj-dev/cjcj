#!/usr/bin/env node
// Verify existing srcbuild handoffs before the archive producer copies bytes.
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseLlvmToolsManifest} from '../llvm-tools-manifest.mjs';
import {consumeFinalCompiler, fileSha256, stdIdentity} from '../srcbuild/lib/final-compiler.mjs';

const [sdk, compilerDirectory, std, runtimeDirectory, cjcjSha, runtimeSha, llvmSha, runId, runAttempt, llvmManifest] = process.argv.slice(2);
const tuple = 'linux_x86_64_cjnative';
for (const sha of [cjcjSha, runtimeSha, llvmSha]) {
  if (!/^[0-9a-f]{40}$/.test(sha || '')) throw new Error('source tuple requires immutable source SHAs');
}
const read = async file => JSON.parse(await fs.readFile(file, 'utf8'));
const compiler = await read(path.join(compilerDirectory, 'FINAL-COMPILER-PROVENANCE.json'));
const stdReceipt = await read(path.join(std, 'SOURCE-BUILD.json'));
const runtime = await read(path.join(runtimeDirectory, 'manifest.json'));
if (runtime.build?.sourceCommit !== runtimeSha || !runtime.build?.buildInputs?.commands?.length
    || !runtime.build?.buildInputs?.compiler_state) throw new Error('source tuple runtime build inputs missing');
const llvm = Object.fromEntries(parseLlvmToolsManifest(await fs.readFile(llvmManifest, 'utf8')).values);
if (llvm.LLVM_SHA !== llvmSha || stdReceipt.inputs.llvmManifest !== await fileSha256(llvmManifest)) {
  throw new Error('source tuple LLVM source/input mismatch');
}
await consumeFinalCompiler({directory: compilerDirectory, platform: 'linux-x64',
  repository: 'https://github.com/cjcj-dev/cjcj.git', commit: cjcjSha,
  runId, runAttempt, std, llvmManifest});
if (compiler.production.stage !== 'stage3' || stdReceipt.source.commit !== runtimeSha
    || stdReceipt.compilerSource?.commit !== cjcjSha
    || compiler.production.source?.commit !== cjcjSha
    || JSON.stringify(stdReceipt.compilerSource) !== JSON.stringify(compiler.production.source)
    || compiler.production.stdCompilerSha256 !== compiler.artifact.sha256
    || runtime.runtime_sha !== runtimeSha
    || compiler.artifact.sha256 !== stdReceipt.inputs.compiler) {
  throw new Error('source tuple stage/source/parent mismatch');
}
if (await fileSha256(path.join(sdk, 'bin/cjc')) !== compiler.artifact.sha256
    || await stdIdentity(sdk, std) !== compiler.production.stdSha256) {
  throw new Error('source tuple installed compiler/std mismatch');
}
for (const file of ['libcangjie-runtime.so', 'libboundscheck.so']) {
  const rel = `runtime/lib/${tuple}/${file}`;
  if (await fileSha256(path.join(sdk, rel)) !== runtime.files[rel]
      || await fileSha256(path.join(runtimeDirectory, rel)) !== runtime.files[rel]) {
    throw new Error(`source tuple compiler runtime mismatch: ${file}`);
  }
}
if (runtime.files[`runtime/lib/${tuple}/libcangjie-runtime.so`] !== compiler.production.runtimeSha256) {
  throw new Error('source tuple compiler runtime lineage mismatch');
}
if (await fileSha256(path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so')) !== stdReceipt.inputs.llvmLibrary
    || compiler.production.llvmLibrarySha256 !== stdReceipt.inputs.llvmLibrary) {
  throw new Error('source tuple compiler LLVM library mismatch');
}
for (const name of ['llc', 'opt']) {
  if (await fileSha256(path.join(sdk, 'third_party/llvm/bin', `${name}-stage1`)) !== stdReceipt.inputs[name]
      || llvm[`${name.toUpperCase()}_SHA256`] !== stdReceipt.inputs[name]) {
    throw new Error(`source tuple std backend mismatch: ${name}`);
  }
}
process.stdout.write(JSON.stringify({compiler, stdlib: stdReceipt, runtime, llvm}));
