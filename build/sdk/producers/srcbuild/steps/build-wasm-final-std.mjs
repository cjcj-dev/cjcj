#!/usr/bin/env node
// Formal producer for final-std-wasm32-wasi (WASI Preview 1), mirroring
// build-android-final-std.mjs / build-ohos-final-std.mjs.
//
// Inputs: a wasm SDK (the stage2 SDK overlaid by ci/wasm-sdk-overlay.mjs with the paired LLVM,
// the wasm32 runtime archive and the pinned wasi-sysroot), the cangjie_runtime stdlib source,
// the boundscheck source, PCRE2 and a wasm32-capable clang/llvm-ar.
// Output: <finalStd>/{lib,modules}/wasi_wasm32_cjnative (every std .a/.cjo the package graph
// produces), third_party/wasi-sysroot, tools/wasm/run_wasi.mjs, the toolchain id, a
// cross-runtime/ tree consumed by build/sdk/producers/release/cross-runtime.mjs, and WASM-FINAL-STD.json
// (per-package status + sha256 of every shipped file).
//
// CI:   node build/sdk/producers/srcbuild/steps/build-wasm-final-std.mjs            (environment below)
// Host: node build/sdk/producers/srcbuild/steps/build-wasm-final-std.mjs --sdk S --stdlib-source D ...
import {execFileSync} from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildWasmStdFull, WASM_TARGET_DIR} from '../../../../../ci/wasm-std-full.mjs';
import {SYSROOT_DIR} from '../../../../../ci/wasi-toolchain.mjs';
import {TOOLCHAIN_ID, RUNNER} from '../../../../../ci/wasm-sdk-overlay.mjs';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

export const TUPLE = WASM_TARGET_DIR;
export const ARTIFACT = 'final-std-wasm32-wasi';
export const PROVENANCE = 'WASM-FINAL-STD.json';
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function walk(root, relative = '') {
  const out = [];
  for (const entry of fs.readdirSync(path.join(root, relative), {withFileTypes: true}).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const rel = path.posix.join(relative, entry.name);
    if (entry.isDirectory()) out.push(...walk(root, rel));
    else if (entry.isFile()) out.push(rel);
    else throw new Error(`final std must contain regular files only: ${rel}`);
  }
  return out;
}

export function indexArchives(llvmAr, dirs) {
  if (!llvmAr) throw new Error('wasm final std requires llvm-ar to index the archives it ships');
  for (const dir of dirs) {
    for (const name of fs.readdirSync(dir).filter(n => n.endsWith('.a')).sort()) execFileSync(llvmAr, ['s', path.join(dir, name)], {stdio: 'inherit'});
  }
}

export async function produceWasmFinalStd({sdk, stdlibSource, boundscheckSource, pcre2Source, clang, llvmAr, finalStd, work,
  runtimeRef, fallbackOpt = false}) {
  if (!/^[0-9a-f]{40}$/.test(runtimeRef ?? '')) throw new Error('wasm final std requires the exact cangjie_runtime source SHA');
  for (const required of [path.join(sdk, 'runtime', 'lib', TUPLE, 'libcangjie-runtime.a'), path.join(sdk, SYSROOT_DIR, 'lib', 'wasm32-wasi', 'libc.a'),
    path.join(sdk, TOOLCHAIN_ID), path.join(sdk, RUNNER)]) {
    if (!fs.statSync(required, {throwIfNoEntry: false})?.isFile()) throw new Error(`wasm SDK input missing: ${required}`);
  }
  // wasm-ld only resolves archive members through the archive symbol table. An archive written by an
  // llvm-ar that did not index it (a CMake build with the SDK's llvm-ar) links nothing, so the producer
  // indexes the runtime archive before the std build and every shipped archive after it.
  indexArchives(llvmAr, [path.join(sdk, 'runtime', 'lib', TUPLE)]);
  const inventory = buildWasmStdFull({sdk, stdlibSource, boundscheckSource, pcre2Source, clang, llvmAr, work, fallbackOpt});
  indexArchives(llvmAr, [path.join(sdk, 'lib', TUPLE)]);
  fs.rmSync(finalStd, {recursive: true, force: true});
  const copy = rel => fs.cpSync(path.join(sdk, rel), path.join(finalStd, rel), {recursive: true});
  for (const rel of [`lib/${TUPLE}`, `modules/${TUPLE}`, SYSROOT_DIR, path.dirname(RUNNER)]) copy(rel);
  // Runtime stays separate from std so consumers cannot confuse their provenance (cf. Android).
  const crossRuntime = path.join(finalStd, 'cross-runtime');
  fs.cpSync(path.join(sdk, 'runtime', 'lib', TUPLE), path.join(crossRuntime, 'runtime', 'lib', TUPLE), {recursive: true});
  fs.cpSync(path.join(sdk, 'lib', TUPLE), path.join(crossRuntime, 'lib', TUPLE), {recursive: true});
  await writeCrossRuntimeManifest({root: crossRuntime, tuple: TUPLE, runtimeRef});
  const files = walk(finalStd).map(rel => ({path: rel, bytes: fs.statSync(path.join(finalStd, rel)).size, sha256: sha256(path.join(finalStd, rel))}));
  const record = {schema: 1, tuple: TUPLE, artifact: ARTIFACT, runtimeRef, packages: inventory.results.map(r => ({name: r.name,
    status: r.status, opt: r.opt ?? null, archive: r.archive, archiveBytes: r.archiveBytes ?? null, cjo: r.cjo, cjoBytes: r.cjoBytes ?? null,
    reason: r.reason ?? null, o2Error: r.o2Error ?? null, native: r.native})), files};
  fs.writeFileSync(path.join(finalStd, PROVENANCE), `${JSON.stringify(record, null, 2)}\n`);
  return record;
}

function argsToOptions(argv) {
  const opt = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || argv[i + 1] === undefined) throw new Error(`bad argument ${argv[i]}`);
    opt[argv[i].slice(2)] = argv[i + 1];
  }
  return opt;
}

async function main(argv) {
  let options;
  if (argv.length) {
    const o = argsToOptions(argv);
    options = {sdk: o.sdk, stdlibSource: o['stdlib-source'], boundscheckSource: o['boundscheck-source'], pcre2Source: o['pcre2-source'],
      clang: o.clang, llvmAr: o['llvm-ar'], finalStd: o['final-std'], work: o.work, runtimeRef: o['runtime-ref'], fallbackOpt: o['fallback-opt'] === 'default'};
  } else {
    // sdk-build-target.yml source-wasm job.
    const env = name => { if (!process.env[name]) throw new Error(`${name} is required`); return process.env[name]; };
    if (process.platform !== 'linux' || process.arch !== 'x64') throw new Error('wasm producer requires the linux-x64 source cell');
    const workspace = path.resolve(env('CANGJIE_WORKSPACE'));
    const repository = path.join(workspace, 'cangjie_runtime');
    options = {sdk: path.resolve(env('CJCJ_WASM_SDK')), stdlibSource: path.join(repository, 'stdlib'),
      boundscheckSource: env('CJCJ_BOUNDSCHECK_SOURCE'), pcre2Source: path.join(repository, 'stdlib', 'third_party', 'pcre2'),
      clang: env('CJCJ_WASM_CLANG'), llvmAr: env('CJCJ_WASM_LLVM_AR'), finalStd: path.join(workspace, 'software', ARTIFACT),
      work: path.join(workspace, 'wasm-final-std-work'), runtimeRef: env('CJCJ_NATIVE_RUNTIME_REF')};
  }
  for (const [k, v] of Object.entries(options)) if (v === undefined) throw new Error(`missing ${k}`);
  const record = await produceWasmFinalStd(options);
  const bad = record.packages.filter(p => !['BUILT', 'HOST_ONLY'].includes(p.status));
  console.log(`WASM_FINAL_STD_BUILT tuple=${TUPLE} runtime_ref=${record.runtimeRef} packages=${record.packages.length} ` +
    `o2=${record.packages.filter(p => p.status === 'BUILT').length} other=${bad.length} artifact=${options.finalStd}`);
  for (const p of bad) console.log(`WASM_FINAL_STD_PACKAGE ${p.name} ${p.status} ${p.reason ?? p.o2Error ?? ''}`.slice(0, 400));
  return 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main(process.argv.slice(2)).then(code => { process.exitCode = code; }, error => { console.error(error); process.exitCode = 1; });
}
