#!/usr/bin/env zx
// Verify and publish a source-built runtime outside the official host SDK.

import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import {resolveRuntimeSource} from './runtime-pin.mjs';

$.stdio = 'inherit';

const dist = argv._[0];
if (!dist) throw new Error('usage: install_patched_runtime.mjs <runtime-artifact-dir>');
const cangjieHome = process.env.CANGJIE_HOME;
if (!cangjieHome) throw new Error('CANGJIE_HOME is required');

const {runtimeRef, pinRef, overrideRef} = await resolveRuntimeSource();
console.log(`[runtime] source ref=${runtimeRef} pin=${pinRef} override=${overrideRef || '<none>'}`);

const sourceSha = (await fs.readFile(`${dist}/SOURCE_SHA`, 'utf8')).trim();
if (sourceSha !== runtimeRef) throw new Error(`runtime source mismatch: ${sourceSha} != ${runtimeRef}`);

const hostOs = (await $({stdio: 'pipe'})`uname -s`).stdout.trim();
const hostArch = (await $({stdio: 'pipe'})`uname -m`).stdout.trim();
const runtimes = {
  'Linux/x86_64': ['linux_x86_64_cjnative', 'libcangjie-runtime.so'],
  'Linux/aarch64': ['linux_aarch64_cjnative', 'libcangjie-runtime.so'],
  'Darwin/x86_64': ['darwin_x86_64_cjnative', 'libcangjie-runtime.dylib'],
  'Darwin/arm64': ['darwin_aarch64_cjnative', 'libcangjie-runtime.dylib'],
};
const runtime = runtimes[`${hostOs}/${hostArch}`];
if (!runtime) {
  console.error(`patched runtime install unsupported on ${hostOs}/${hostArch}`);
  process.exit(2);
}
const [runtimeDir, runtimeLibrary] = runtime;
const source = path.join(dist, runtimeLibrary);
const sourceFileSha = crypto.createHash('sha256').update(await fs.readFile(source)).digest('hex');
const expectedFileSha = (await fs.readFile(`${source}.sha256`, 'utf8')).trim().split(/\s+/)[0];
if (sourceFileSha !== expectedFileSha) throw new Error('source runtime sha mismatch');

const installRoot = path.resolve(argv._[1] || 'patched-runtime');
await fs.mkdir(installRoot, {recursive: true});
const sdkRoot = await fs.realpath(cangjieHome);
const realInstallRoot = await fs.realpath(installRoot);
if (realInstallRoot === sdkRoot || realInstallRoot.startsWith(`${sdkRoot}${path.sep}`)) {
  throw new Error('patched runtime destination must be outside the official SDK');
}
const destinationDir = path.join(realInstallRoot, 'lib', runtimeDir);
await fs.mkdir(destinationDir, {recursive: true});
const realDestinationDir = await fs.realpath(destinationDir);
if (!realDestinationDir.startsWith(`${realInstallRoot}${path.sep}`)) {
  throw new Error('patched runtime destination escapes its independent directory');
}
const destination = path.join(realDestinationDir, runtimeLibrary);
await fs.copyFile(source, `${destination}.new`);
await fs.chmod(`${destination}.new`, 0o755);
await fs.rename(`${destination}.new`, destination);
const destinationSha = crypto.createHash('sha256').update(await fs.readFile(destination)).digest('hex');
if (destinationSha !== sourceFileSha) throw new Error('installed runtime sha mismatch');
console.log(`[runtime] installed ${runtimeRef} -> ${destination}`);

// Explicit opt-in for rebuilt consumers; never alter the host loader environment.
if (process.env.GITHUB_ENV) {
  await fs.appendFile(process.env.GITHUB_ENV, `CJCJ_PATCHED_RUNTIME_LIB_DIR=${realDestinationDir}\n`);
}
