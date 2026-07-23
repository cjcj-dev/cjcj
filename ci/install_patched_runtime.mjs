#!/usr/bin/env zx
// Verify and install a source-built runtime into this job's SDK tree.

import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';

$.stdio = 'inherit';

const dist = argv._[0];
if (!dist) throw new Error('usage: install_patched_runtime.mjs <runtime-artifact-dir>');
const cangjieHome = process.env.CANGJIE_HOME;
if (!cangjieHome) throw new Error('CANGJIE_HOME is required');

const pinText = await fs.readFile(path.join(import.meta.dirname, 'runtime_pin.env'), 'utf8');
const pins = Object.fromEntries(pinText.split(/\r?\n/).filter(Boolean).map((line) => {
  const separator = line.indexOf('=');
  if (separator < 1) throw new Error(`invalid runtime pin line: ${line}`);
  return [line.slice(0, separator), line.slice(separator + 1)];
}));
const runtimeRef = pins.RUNTIME_REF;
const requestedRuntimeRef = process.env.RUNTIME_REF || '';
if (requestedRuntimeRef && requestedRuntimeRef !== runtimeRef) {
  console.error(`[runtime] pin mismatch: ${requestedRuntimeRef} != ${runtimeRef}`);
  process.exit(2);
}

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

const destination = path.join(cangjieHome, 'runtime', 'lib', runtimeDir, runtimeLibrary);
await fs.access(destination);
await fs.copyFile(source, `${destination}.new`);
await fs.chmod(`${destination}.new`, 0o755);
await fs.rename(`${destination}.new`, destination);
const destinationSha = crypto.createHash('sha256').update(await fs.readFile(destination)).digest('hex');
if (destinationSha !== sourceFileSha) throw new Error('installed runtime sha mismatch');
console.log(`[runtime] installed ${runtimeRef} -> ${destination}`);
