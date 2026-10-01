#!/usr/bin/env node
// Source jobs retain absolute SDK bindings and verify the producer before use.
// Like bootstrap_store.acquire, nothing is consumable until its manifest checks.
import fs from 'node:fs/promises';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {createReadStream} from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const [mode, phase, directory] = process.argv.slice(2);
if (!['pack', 'restore'].includes(mode) || !/^[a-z0-9-]+$/.test(phase || '') || !directory) {
  throw new Error('usage: job-handoff.mjs pack|restore PHASE DIRECTORY');
}
const required = name => {
  if (!process.env[name]) throw new Error(`missing ${name}`);
  return process.env[name];
};
const root = path.resolve(required('GITHUB_WORKSPACE'));
const identity = {
  version: 1, phase, target: required('CJCJ_SRCBUILD_TARGET'),
  commit: required('GITHUB_SHA'), run: required('GITHUB_RUN_ID'),
  workspace: root,
};
const dir = path.resolve(directory);
const archive = path.join(dir, 'payload.tar');
const manifest = path.join(dir, 'manifest.json');
const hash = async file => {
  const h = crypto.createHash('sha256');
  for await (const chunk of createReadStream(file)) h.update(chunk);
  return h.digest('hex');
};
const tar = args => {
  const result = spawnSync('tar', args, {stdio: 'inherit'});
  if (result.error || result.status !== 0) throw new Error(`handoff tar failed: ${result.error || result.status}`);
};
// Deliberately exclude PATH, cache launchers, tokens and runner command files.
// Every consuming job installs its own dependencies and starts its own cache.
const allowed = name => /^(CJCJ_BOOTSTRAP_[A-Z0-9_]+|CJCJ_SRCBUILD_(HOST_SDK|BOOTSTRAP_SDK)|CJCJ_TOOLCHAIN|CJCJ_ACTUAL_HOST_TOOLCHAIN|CANGJIE_HOME|CANGJIE_STDX_PATH|LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|G2_IDENTITY|G2_CAMPAIGN_DIR|SOURCE_SDK_VERSION|CJCJ_RUNTIME_REF_OVERRIDE|CJCJ_ALLOW_RUNTIME_OVERRIDE|RUNTIME_REF|RUNTIME_SRC_URL|TOOLS_REF|TOOLS_SRC_URL|STDX_REF|STDX_SRC_URL|CANGJIE_COMPILER_SHA|CANGJIE_COMPILER_URL|LLVM_SHA|LLVM_TUPLE_SUMS_SHA)$/.test(name);
// MinGW is an independent producer. Its overlay must not replace the native
// SDK, injected source version or environment when Windows std joins both arms.
const roots = phase === 'mingw' ? ['.srcbuild/buildtools/llvm-mingw-w64']
  : ['.srcbuild', 'packages', 'runtime_shim', 'cjpm.toml'];
const optional = phase === 'mingw' ? [] : ['cjpm.lock', 'target'];
async function verifyRuntimeHandoff(environment) {
  const selected = await resolveRuntimeSource(environment);
  const pin = environment.CJCJ_BOOTSTRAP_RUNTIME_PIN;
  if (selected.overrideRef && !pin) throw new Error('handoff candidate runtime pin missing');
  if (pin) {
    const archived = path.join(root, '.srcbuild') + path.sep;
    if (!path.resolve(pin).startsWith(archived) || !String(await fs.realpath(pin)).startsWith(archived)) {
      throw new Error('handoff runtime pin outside archived inputs');
    }
  }
}
if (mode === 'pack') {
  await fs.mkdir(dir, {recursive: true});
  if (dir === root || roots.some(entry => dir.startsWith(path.join(root, entry) + path.sep))) {
    throw new Error('handoff output must be outside archived trees');
  }
  const environment = phase === 'mingw' ? {}
    : Object.fromEntries(Object.entries(process.env).filter(([key]) => allowed(key)));
  if (phase !== 'mingw') await verifyRuntimeHandoff(environment);
  for (const [key, value] of Object.entries(environment)) {
    if (/[\r\n]/.test(value)) throw new Error(`multiline handoff environment: ${key}`);
  }
  const entries = [...roots];
  for (const entry of optional) {
    try { await fs.lstat(path.join(root, entry)); entries.push(entry); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  // tar preserves modes and links that upload-artifact's zip cannot preserve.
  // A checkout copied by bootstrap may contain Git's credential-bearing config;
  // retain its object identity, never that config or Actions command files.
  tar(['-cf', archive, '--exclude=.git/config', '--exclude=*/.git/config',
    '--exclude=*/cjcj-src-stage0/target', '--exclude=*/cjcj-src-stage1/target',
    '--exclude=*/stage0depot', '-C', root, ...entries]);
  const record = {...identity, environment, entries, sha256: await hash(archive)};
  await fs.writeFile(manifest, `${JSON.stringify(record, null, 2)}\n`);
  console.log(`BOOTSTRAP_HANDOFF phase=${phase} sha256=${record.sha256}`);
} else {
  const record = JSON.parse(await fs.readFile(manifest, 'utf8'));
  for (const [key, value] of Object.entries(identity)) {
    if (record[key] !== value) throw new Error(`handoff identity mismatch: ${key}`);
  }
  if (!/^[a-f0-9]{64}$/.test(record.sha256 || '') || await hash(archive) !== record.sha256) {
    throw new Error('handoff payload SHA256 mismatch');
  }
  if (!record.environment || Object.entries(record.environment).some(([key, value]) =>
    !allowed(key) || typeof value !== 'string' || /[\r\n]/.test(value))) {
    throw new Error('invalid handoff environment');
  }
  // The artifact is selected by same-run target/phase name; the identity above
  // also rejects accidental cross-target or stale-run selection before unpack.
  if (phase !== 'mingw') await resolveRuntimeSource(record.environment, null);
  tar(['-xf', archive, '-C', root]);
  if (phase !== 'mingw') await verifyRuntimeHandoff(record.environment);
  await fs.appendFile(required('GITHUB_ENV'), Object.entries(record.environment)
    .map(([key, value]) => `${key}=${value}\n`).join(''));
  const sdk = record.environment.CANGJIE_HOME;
  if (sdk) await fs.appendFile(required('GITHUB_PATH'), `${sdk}/bin\n${sdk}/tools/bin\n`);
  console.log(`BOOTSTRAP_VERIFIED handoff/${phase} ${record.sha256}`);
}
