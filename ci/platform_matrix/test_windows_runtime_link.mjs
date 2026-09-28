#!/usr/bin/env zx
// Integration test: run the production entry, including its real build.py/CMake
// consumer. Negative controls change linker selection, never the result oracle.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

assert.equal(process.platform, 'win32', 'this test needs the native Windows entry');
const arm = process.env.LINK_CONTROL_ARM || 'candidate';
assert.ok(['candidate', 'cut-entry', 'cut-selection', 'restored'].includes(arm));
const evidence = path.resolve('link-evidence');
await fs.mkdir(evidence, {recursive: true});
const entry = 'ci/platform_matrix/build_runtime.mjs';
const selection = 'ci/platform_matrix/windows_runtime_toolchain.cmake';
const originalEntry = await fs.readFile(entry, 'utf8');
const originalSelection = await fs.readFile(selection, 'utf8');
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const entryCall = 'python3 build.py build --target ${runtimeTarget} --build-type ${buildType} --target-toolchain /mingw64';
assert.equal(originalEntry.split(entryCall).length, 2, 'one native product build call');
assert.equal(originalSelection.split('set(CMAKE_LINKER_TYPE LLD)').length, 2);
const cutEntry = originalEntry.replace(entryCall, `CMAKE_TOOLCHAIN_FILE= ${entryCall}`);
const cutSelection = originalSelection.replace('set(CMAKE_LINKER_TYPE LLD)', 'set(CMAKE_LINKER_TYPE SYSTEM)');
const started = Date.now();
let result;
try {
  if (arm === 'cut-entry' || arm === 'restored') await fs.writeFile(entry, cutEntry);
  if (arm === 'cut-selection') await fs.writeFile(selection, cutSelection);
  if (arm === 'restored') await fs.writeFile(entry, originalEntry);
  await fs.writeFile(path.join(evidence, 'cut.diff'), (await $({verbose: false})`git diff -- ${entry} ${selection}`).stdout);
  const identity = {
    entry: sha256(await fs.readFile(entry)),
    selection: sha256(await fs.readFile(selection)),
    test: sha256(await fs.readFile('ci/platform_matrix/test_windows_runtime_link.mjs')),
    runtime: process.env.RUNTIME_REF,
  };
  const run = await $({nothrow: true, verbose: false})`npx --yes zx@8 ci/platform_matrix/build_runtime.mjs`;
  const log = `${run.stdout}\n${run.stderr}`;
  await fs.writeFile(path.join(evidence, 'build.log'), log);
  const linkCommands = log.split(/\r?\n/).filter((line) => line.startsWith('cd ') && line.includes(' && clang++.exe ') && line.includes('-shared '));
  assert.ok(linkCommands.length, 'actual DLL link command was observed');
  const linkCommand = linkCommands.at(-1);
  await fs.writeFile(path.join(evidence, 'link.txt'), linkCommand);
  const negative = arm.startsWith('cut-');
  let productAssertionRc = 0;
  let productAssertion;
  try {
    assert.equal(run.exitCode, 0, 'DLL_BUILD_RESULT: production entry must install the runtime DLL');
  } catch (error) {
    productAssertionRc = 1;
    productAssertion = error.message;
    if (!negative) throw error;
  }
  console.log(`DLL_BUILD_RESULT_EXECUTED arm=${arm} build_rc=${run.exitCode} assertion_rc=${productAssertionRc}`);
  result = {arm, identity, buildRc: run.exitCode, productAssertionRc, productAssertion, wallSeconds: (Date.now() - started) / 1000};
  if (negative) {
    assert.equal(productAssertionRc, 1, 'cut must fail the unchanged DLL build assertion');
    assert.match(log, /\[100%\] Linking CXX shared library[^\n]*libcangjie-runtime\.dll/);
    assert.match(log, /CompilerCalls\.cpp\.obj/);
    assert.match(log, /relocation truncated to fit: IMAGE_REL_AMD64_REL32 against undefined symbol .operator delete\(void\*\)/);
    assert.doesNotMatch(linkCommand, /-fuse-ld=lld/);
    result.signature = 'CompilerCalls.cpp.obj / operator delete(void*) / IMAGE_REL_AMD64_REL32';
  } else {
    assert.match(linkCommand, /-fuse-ld=lld/);
    const install = '.platform-ci/runtime-install/windows_release_x86_64';
    assert.equal((await fs.readFile(path.join(install, 'SOURCE_SHA'), 'utf8')).trim(), process.env.RUNTIME_REF);
    const dll = path.join(install, 'runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll');
    const bytes = await fs.readFile(dll);
    assert.equal(bytes.toString('ascii', 0, 2), 'MZ', 'installed DLL is a PE image');
    const pe = bytes.readUInt32LE(0x3c);
    assert.equal(bytes.readUInt32LE(pe), 0x4550, 'PE signature');
    assert.equal(bytes.readUInt16LE(pe + 4), 0x8664, 'x86_64 machine');
    assert.ok(bytes.readUInt16LE(pe + 22) & 0x2000, 'IMAGE_FILE_DLL');
    result.dll = {path: dll, sha256: sha256(bytes), size: bytes.length};
    await fs.copyFile(dll, path.join(evidence, 'libcangjie-runtime.dll'));
    console.log(`DLL_INSTALLED sha256=${result.dll.sha256} size=${bytes.length}`);
  }
  result.controlPassed = true;
} finally {
  await fs.writeFile(entry, originalEntry);
  await fs.writeFile(selection, originalSelection);
  if (result) await fs.writeFile(path.join(evidence, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
}
