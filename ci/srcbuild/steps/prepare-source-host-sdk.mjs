#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {getTarget} from '../../../build/lib/targets.mjs';
import {assertPlainHostRuntime} from '../../../build/lib/runtime-split.mjs';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubEnv = process.env.GITHUB_ENV;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
const bootstrapSdk = process.env.CJCJ_SRCBUILD_BOOTSTRAP_SDK;
if (!workspace || !githubEnv || !targetKey || !bootstrapSdk) {
  throw new Error(
    'CANGJIE_WORKSPACE, GITHUB_ENV, CJCJ_SRCBUILD_TARGET and CJCJ_SRCBUILD_BOOTSTRAP_SDK are required',
  );
}

const target = getTarget(targetKey);
const sourceSdk = await fs.realpath(bootstrapSdk);
const hostSdk = path.join(workspace, 'source-host-sdk');
const compiler = path.join(workspace, 'cangjie_compiler', 'output', 'bin', 'cjc');
if (!(await fs.stat(compiler)).isFile()) throw new Error(`source-built compiler is missing: ${compiler}`);
if (path.resolve(hostSdk) === sourceSdk || path.resolve(hostSdk).startsWith(`${sourceSdk}${path.sep}`)) {
  throw new Error(`private host SDK must not alias or live inside the bootstrap SDK: ${sourceSdk}`);
}

// The compiler resolves built-in macro libraries relative to its own executable,
// so a loader-only override cannot split host from target when those libraries
// carry $ORIGIN. Preserve the complete stock SDK and replace only its compiler.
await fs.rm(hostSdk, {recursive: true, force: true});
await fs.cp(sourceSdk, hostSdk, {recursive: true, preserveTimestamps: true});
if ((await fs.lstat(hostSdk)).isSymbolicLink()) {
  throw new Error(`private host SDK is a symbolic link: ${hostSdk}`);
}
const hostCompiler = path.join(hostSdk, 'bin', 'cjc');
await fs.copyFile(compiler, hostCompiler);
await fs.chmod(hostCompiler, (await fs.stat(compiler)).mode);

const digest = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
const compilerSha = await digest(compiler);
const hostCompilerSha = await digest(hostCompiler);
if (hostCompilerSha !== compilerSha) {
  throw new Error(`private host cjc copy mismatch: ${hostCompilerSha} != ${compilerSha}`);
}
assertPlainHostRuntime({hostSdk, target});
await fs.appendFile(githubEnv, `CJCJ_SRCBUILD_HOST_SDK=${hostSdk}\n`);
console.log(
  `SOURCE_HOST_SDK_PREPARED path=${hostSdk} source=${sourceSdk} ` +
  `cjc_sha256=${hostCompilerSha}`,
);
