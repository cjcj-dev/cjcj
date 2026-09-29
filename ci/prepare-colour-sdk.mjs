#!/usr/bin/env node
// Build inputs and process loader inputs are deliberately separate.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const stateFile = path.join(repo, '.platform-ci', 'colour-sdk.json');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function run(command, args, env = process.env) {
  const result = spawnSync(command, args, {stdio: 'inherit', env});
  if (result.status !== 0) throw new Error(`${command} failed rc=${result.status} signal=${result.signal}`);
}
export async function prepareColourSdk(runtimeRoot, env = process.env) {
  if (process.platform !== 'linux' || process.arch !== 'x64') {
    throw new Error('COLOUR_STD_NOT_RUN: platform input pending #695/#473/#501');
  }
  const tuple = 'linux_x86_64_cjnative';
  const host = await fs.realpath(env.CANGJIE_HOME);
  const root = path.dirname(stateFile);
  await fs.mkdir(root, {recursive: true});
  const pin = JSON.parse(await fs.readFile(path.join(repo, 'ci/colour-std-pin.json'), 'utf8'));
  if (pin.runtime_sha !== env.RUNTIME_REF) {
    throw new Error(`COLOUR_STD_NOT_RUN: manifest runtime=${pin.runtime_sha} required=${env.RUNTIME_REF}; waiting #501/#135`);
  }
  const archive = path.join(root, pin.asset);
  try {
    if (digest(await fs.readFile(archive)) !== pin.sha256) throw new Error('archive hash mismatch');
  } catch {
    const response = await fetch(`https://github.com/${pin.repository}/releases/download/${pin.tag}/${pin.asset}`);
    if (!response.ok) throw new Error(`colour std download: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (digest(bytes) !== pin.sha256) throw new Error('colour std archive hash mismatch');
    await fs.writeFile(archive, bytes);
  }
  const std = path.join(root, 'colour-std');
  await fs.rm(std, {recursive: true, force: true});
  run('python3', ['-m', 'zipfile', '-e', archive, std]);
  const manifestBytes = await fs.readFile(path.join(std, 'manifest.json'));
  if (digest(manifestBytes) !== pin.manifest_sha256) throw new Error('colour std manifest hash mismatch');
  const manifest = JSON.parse(manifestBytes);
  if (manifest.runtime_sha !== env.RUNTIME_REF || manifest.platform !== pin.platform) {
    throw new Error('COLOUR_RT_MANIFEST_MISMATCH');
  }
  for (const [rel, sha] of Object.entries(manifest.files)) {
    if (digest(await fs.readFile(path.join(std, rel))) !== sha) throw new Error(`colour std file hash mismatch: ${rel}`);
  }
  const sdk = path.join(root, 'colour-sdk');
  const runtime = path.resolve(runtimeRoot);
  let runtimeDir = path.join(runtime, 'runtime', 'lib', tuple);
  try { await fs.access(path.join(runtimeDir, 'libcangjie-runtime.so')); }
  catch { runtimeDir = runtime; }
  const hostRuntime = path.join(host, 'runtime', 'lib', tuple);
  run('bash', [path.join(repo, 'ci/bootstrap/sdk_build.sh'), '--from', host, '--to', sdk,
    '--target', tuple, '--std', std, '--runtime', runtime,
    '--runtime-commit', env.RUNTIME_REF, '--colour-runtime', path.join(runtimeDir, 'libcangjie-runtime.so'),
    '--host-runtime', path.join(hostRuntime, 'libcangjie-runtime.so'), '--verify-host-rt', hostRuntime, '--force'], env);
  // Same convention as #710. Only rebuilt consumers receive this loader path.
  const published = path.resolve(env.CJCJ_PATCHED_RUNTIME_LIB_DIR || path.join(repo, 'patched-runtime', 'lib', tuple));
  const resolvedParent = await fs.realpath(path.dirname(published)).catch(() => path.dirname(published));
  if (resolvedParent === host || resolvedParent.startsWith(`${host}${path.sep}`)) throw new Error('runtime destination is inside official SDK');
  await fs.mkdir(published, {recursive: true});
  const realPublished = await fs.realpath(published);
  if (realPublished === host || realPublished.startsWith(`${host}${path.sep}`)) throw new Error('runtime destination is inside official SDK');
  for (const entry of await fs.readdir(path.join(sdk, 'runtime', 'lib', tuple), {withFileTypes: true})) {
    if (!entry.isFile()) continue;
    // Rename a fresh file so an inherited destination symlink cannot write
    // through into a host SDK (the #710 installer uses the same boundary).
    const temporary = path.join(realPublished, `.${entry.name}.${crypto.randomUUID()}`);
    await fs.copyFile(path.join(sdk, 'runtime', 'lib', tuple, entry.name), temporary, fs.constants.COPYFILE_EXCL);
    await fs.rename(temporary, path.join(realPublished, entry.name));
  }
  const state = {host, sdk, runtime: realPublished, tuple, runtime_sha: env.RUNTIME_REF, std_manifest_sha256: pin.manifest_sha256};
  await fs.writeFile(stateFile, JSON.stringify(state, null, 2) + '\n');
  if (env.GITHUB_ENV) await fs.appendFile(env.GITHUB_ENV, `CJCJ_PATCHED_RUNTIME_LIB_DIR=${realPublished}\n`);
  console.log(`COLOUR_SDK ${JSON.stringify(state)}`);
  return state;
}
export async function colourEnvironment(mode, env = process.env) {
  const state = JSON.parse(await fs.readFile(stateFile, 'utf8'));
  if (!/^[a-f0-9]{40}$/.test(state.runtime_sha || '') || state.runtime_sha !== env.RUNTIME_REF) {
    throw new Error('COLOUR_RT_STATE_MISMATCH: prepare the SDK for the current runtime pin');
  }
  const libraries = mode === 'build'
    ? [path.join(state.host, 'runtime', 'lib', state.tuple), path.join(state.host, 'tools/lib'), path.join(state.host, 'third_party/llvm/lib')]
    : [state.runtime, path.join(state.sdk, 'lib'), path.join(state.sdk, 'tools/lib'), path.join(state.sdk, 'third_party/llvm/lib')];
  return {...env, CANGJIE_HOME: state.sdk, CJCJ_PATCHED_RUNTIME_LIB_DIR: state.runtime,
    LD_LIBRARY_PATH: libraries.join(':'),
    PATH: [path.join(state.host, 'bin'), path.join(state.host, 'tools/bin'), env.PATH].join(':')};
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await prepareColourSdk(process.argv[2] || 'dist-runtime');
}
