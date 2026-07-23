#!/usr/bin/env zx
// Verify and install a source-built runtime into this job's SDK tree.

import fs from 'node:fs/promises';
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

const so = `${dist}/libcangjie-runtime.so`;
await $`test -f ${so}`;
const sourceSha = (await fs.readFile(`${dist}/SOURCE_SHA`, 'utf8')).trim();
if (sourceSha !== runtimeRef) throw new Error(`runtime source mismatch: ${sourceSha} != ${runtimeRef}`);
await $({cwd: dist})`sha256sum -c libcangjie-runtime.so.sha256`;

const hostOs = (await $({stdio: 'pipe'})`uname -s`).stdout.trim();
const hostArch = (await $({stdio: 'pipe'})`uname -m`).stdout.trim();
const runtimeDirs = {
  'Linux/x86_64': 'linux_x86_64_cjnative',
  'Linux/aarch64': 'linux_aarch64_cjnative',
};
const runtimeDir = runtimeDirs[`${hostOs}/${hostArch}`];
if (!runtimeDir) {
  console.error(`[runtime] unsupported host ${hostOs}/${hostArch}`);
  process.exit(2);
}

const destination = `${cangjieHome}/runtime/lib/${runtimeDir}/libcangjie-runtime.so`;
await $`test -f ${destination}`;
await $`install -m0755 ${so} ${destination}.new`;
await $`mv -f ${destination}.new ${destination}`;
const destinationSha = (await $({stdio: 'pipe'})`sha256sum ${destination}`).stdout.trim().split(/\s+/)[0];
const sourceFileSha = (await $({stdio: 'pipe'})`sha256sum ${so}`).stdout.trim().split(/\s+/)[0];
if (destinationSha !== sourceFileSha) throw new Error('installed runtime sha mismatch');
console.log(`[runtime] installed ${runtimeRef} -> ${destination}`);
