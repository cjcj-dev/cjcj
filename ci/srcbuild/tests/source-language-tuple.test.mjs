import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {produceFinalCompiler, fileSha256, stdIdentity} from '../lib/final-compiler.mjs';

const cli = fileURLToPath(new URL('../../release/source_language_tuple.py', import.meta.url));
const tuple = 'linux_x86_64_cjnative';
const invoke = (...args) => execFileSync('python3', [cli, ...args], {encoding: 'utf8', stdio: 'pipe'});
const write = async (file, value) => {
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, value);
};
const json = async (file, value) => write(file, JSON.stringify(value));

async function fixture(body) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'source-tuple-'));
  try {
    const sdk = path.join(root, 'sdk');
    const std = path.join(root, 'std');
    const runtime = path.join(root, 'runtime');
    const host = path.join(root, 'host');
    const compiler = path.join(root, 'compiler');
    const output = path.join(root, 'package');
    for (const dir of ['include', 'lib', 'modules', 'runtime', 'third_party', 'tools']) await fs.mkdir(path.join(sdk, dir), {recursive: true});
    await write(path.join(std, 'PROVENANCE.txt'), 'synthetic packaging fixture; not a qualified SDK');
    await write(path.join(std, `lib/${tuple}/libcangjie-std-core.a`), 'std fixture');
    await write(path.join(std, `modules/${tuple}/core.cjo`), 'module fixture');
    await write(path.join(sdk, 'bin/cjc'), 'stage3 fixture');
    await fs.chmod(path.join(sdk, 'bin/cjc'), 0o755);
    const runtimeFiles = {};
    const hostPins = [];
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      const rel = `runtime/lib/${tuple}/${name}`;
      await write(path.join(runtime, rel), `coloured fixture ${name}`);
      await write(path.join(sdk, rel), `coloured fixture ${name}`);
      runtimeFiles[rel] = await fileSha256(path.join(runtime, rel));
      await write(path.join(host, name), `official host fixture ${name}`);
      hostPins.push(`${name} ${await fileSha256(path.join(host, name))}`);
    }
    const hostPin = path.join(root, 'host-pins');
    await write(hostPin, hostPins.join('\n'));
    const inputs = {compiler: 'd'.repeat(64), runtime: runtimeFiles[`runtime/lib/${tuple}/libcangjie-runtime.so`]};
    for (const name of ['llc', 'opt']) {
      await write(path.join(sdk, `third_party/llvm/bin/${name}-stage1`), `native backend fixture ${name}`);
      await write(path.join(sdk, `third_party/llvm/bin/${name}`), 'workspace wrapper fixture');
      inputs[name] = await fileSha256(path.join(sdk, `third_party/llvm/bin/${name}-stage1`));
    }
    await write(path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so'), 'coloured LLVM library fixture');
    inputs.llvmLibrary = await fileSha256(path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so'));
    const llvmManifest = path.join(root, 'llvm-tools.manifest');
    await write(llvmManifest, `LLVM_SHA=${'c'.repeat(40)}\nLLC_SHA256=${inputs.llc}\nOPT_SHA256=${inputs.opt}\n`);
    inputs.llvmManifest = await fileSha256(llvmManifest);
    await json(path.join(std, 'SOURCE-BUILD.json'), {schema: 1, source: {commit: 'b'.repeat(40)}, compilerSource: {commit: 'a'.repeat(40)}, inputs,
      products: {core: await fileSha256(path.join(std, `lib/${tuple}/libcangjie-std-core.a`))}});
    await fs.cp(std, sdk, {recursive: true});
    const compilerSha = await fileSha256(path.join(sdk, 'bin/cjc'));
    await produceFinalCompiler({binary: path.join(sdk, 'bin/cjc'), outdir: compiler, platform: 'linux-x64',
      repository: 'https://github.com/cjcj-dev/cjcj.git', commit: 'a'.repeat(40), runId: '42', runAttempt: '1', std,
      lineage: {stage: 'stage3', source: {commit: 'a'.repeat(40)}, llvmLibrarySha256: inputs.llvmLibrary, parentSha256: inputs.compiler, compilerSha256: compilerSha,
        llvmManifestSha256: inputs.llvmManifest, stdSha256: await stdIdentity(std), runtimeSha256: inputs.runtime}});
    await json(path.join(runtime, 'manifest.json'), {runtime_sha: 'b'.repeat(40), files: runtimeFiles, build: {sourceCommit: 'b'.repeat(40), installed: runtimeFiles, buildInputs: {commands: ['synthetic build'], compiler_state: {fixture: true}}}});
    const pack = () => invoke('pack', '--sdk', sdk, '--std', std, '--compiler', compiler,
      '--runtime', runtime, '--host', host, '--host-pins', hostPin, '--host-identity', 'test fixture',
      '--llvm-manifest', llvmManifest, '--output', output, '--cjcj-sha', 'a'.repeat(40), '--runtime-sha', 'b'.repeat(40),
      '--llvm-sha', 'c'.repeat(40), '--run-id', '42', '--run-attempt', '1', '--node', process.execPath);
    const pins = async () => ['--manifest-sha256', await fileSha256(path.join(output, 'language-tuple.json')),
      '--compiler-sha256', compilerSha];
    await body({root, sdk, std, runtime, host, output, pack, pins});
  } finally { await fs.rm(root, {recursive: true, force: true}); }
}

// These execute the shipped packaging CLI against synthetic inputs. They prove
// the device's identity checks, not compiler behaviour or a language gate.
test('source tuple roundtrip and activation keep compiler/official/target roles distinct', () => fixture(async ({root, output, pack, pins}) => {
  assert.match(pack(), /SOURCE_TUPLE_PACKED/);
  const pin = await pins();
  const archive = (await fs.readdir(output)).find(name => name.endsWith('.tar.gz'));
  const downloaded = path.join(root, 'downloaded');
  assert.match(invoke('unpack', '--archive', path.join(output, archive), '--archive-sha256',
    await fileSha256(path.join(output, archive)), '--output', downloaded, ...pin), /UNPACKED_VERIFIED/);
  const target = path.join(root, 'target');
  const options = [];
  for (const [name, flag] of [['libcangjie-runtime.so', 'target-runtime'], ['libboundscheck.so', 'target-boundscheck']]) {
    await write(path.join(target, name), `independent target fixture ${name}`);
    options.push(`--${flag}-sha256`, await fileSha256(path.join(target, name)));
  }
  const env = invoke('activate', '--root', path.join(downloaded, 'tuple'), '--target', target,
    '--output', path.join(root, 'active'), ...options, ...pin);
  assert.match(env, /GC_UNIT_CJC_RUNTIME_LIB_DIR=.*compiler-runtime/);
  assert.match(env, /CJCJ_OFFICIAL_HOST_RUNTIME_LIB_DIR=.*official-host/);
  assert.match(env, /GCV2_RUNTIME_LIB_DIR=.*target/);
}));

test('source producer refuses a different compiler/std producer attempt', () => fixture(async ({output, pack, root}) => {
  const file = path.join(root, 'compiler/FINAL-COMPILER-PROVENANCE.json');
  const value = JSON.parse(await fs.readFile(file));
  value.production.runAttempt = '2';
  await json(file, value);
  assert.throws(pack, /final compiler run\/std mismatch/);
  await assert.rejects(fs.stat(output), {code: 'ENOENT'});
}));

test('source producer refuses installed std substitution', () => fixture(async ({sdk, pack}) => {
  await write(path.join(sdk, `modules/${tuple}/core.cjo`), 'replacement module');
  assert.throws(pack, /installed compiler\/std mismatch/);
}));

test('source consumer refuses compiler substitution', () => fixture(async ({output, pack, pins}) => {
  pack();
  const pin = await pins();
  await write(path.join(output, 'tuple/sdk/bin/cjcj-stage1'), 'different compiler');
  assert.throws(() => invoke('verify', '--root', path.join(output, 'tuple'), ...pin), /SOURCE_TUPLE_PAYLOAD sdk\/bin\/cjcj-stage1/);
}));

test('source consumer refuses a wrong externally pinned manifest digest', () => fixture(async ({output, pack, pins}) => {
  pack();
  const pin = await pins();
  pin[1] = '0'.repeat(64);
  assert.throws(() => invoke('verify', '--root', path.join(output, 'tuple'), ...pin), /SOURCE_TUPLE_MANIFEST_DIGEST/);
}));
