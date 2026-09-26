import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
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

async function fixture(body, nativeHost = false) {
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
    // Execute official tools with a real self-built compiler child and a
    // distinct runtime pair. This device fixture does not qualify stage3.
    if (nativeHost) await fs.copyFile(process.env.SOURCE_TUPLE_COMPILER, path.join(sdk, 'bin/cjc'));
    await fs.chmod(path.join(sdk, 'bin/cjc'), 0o755);
    const runtimeFiles = {};
    const hostPins = [];
    for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      const rel = `runtime/lib/${tuple}/${name}`;
      await write(path.join(runtime, rel), `coloured fixture ${name}`);
      await write(path.join(sdk, rel), `coloured fixture ${name}`);
      if (nativeHost) {
        await fs.copyFile(path.join(process.env.SOURCE_TUPLE_COMPILER_SDK, rel), path.join(runtime, rel));
        await fs.copyFile(path.join(runtime, rel), path.join(sdk, rel));
      }
      runtimeFiles[rel] = await fileSha256(path.join(runtime, rel));
      await write(path.join(host, name), `official host fixture ${name}`);
      if (nativeHost) await fs.copyFile(path.join(process.env.SOURCE_TUPLE_OFFICIAL_SDK, `runtime/lib/${tuple}/${name}`), path.join(host, name));
      hostPins.push(`${name} ${await fileSha256(path.join(host, name))}`);
    }
    const hostLlvm = path.join(host, 'libLLVM-15.so');
    await write(hostLlvm, 'official host LLVM fixture');
    if (nativeHost) {
      await fs.copyFile(process.env.SOURCE_TUPLE_HOST_LLVM, hostLlvm);
      assert.equal(await fileSha256(hostLlvm), '30e8ba8c8a30b8b8ea36b4d7ada4cce7b7e12e1a07a66439556b1bd6cb2b3981');
    }
    hostPins.push(`libLLVM-15.so ${await fileSha256(hostLlvm)}`);
    for (const relative of ['tools/bin/cjpm', 'third_party/llvm/bin/llvm-ar', 'third_party/llvm/bin/llvm-objcopy']) {
      await write(path.join(sdk, relative), `#!/bin/bash\nexec '${sdk}/producer-only-tool' "$@"\n`);
      await fs.copyFile('/usr/bin/true', path.join(sdk, relative + '-stage1'));
      if (nativeHost) await fs.copyFile(path.join(process.env.SOURCE_TUPLE_OFFICIAL_SDK, relative), path.join(sdk, relative + '-stage1'));
      await fs.chmod(path.join(sdk, relative + '-stage1'), 0o755);
    }
    const hostPin = path.join(root, 'host-pins');
    await write(hostPin, hostPins.join('\n'));
    const inputs = {compiler: await fileSha256(path.join(sdk, 'bin/cjc')), runtime: runtimeFiles[`runtime/lib/${tuple}/libcangjie-runtime.so`]};
    for (const name of ['llc', 'opt']) {
      await write(path.join(sdk, `third_party/llvm/bin/${name}-stage1`), `native backend fixture ${name}`);
      await write(path.join(sdk, `third_party/llvm/bin/${name}`), 'workspace wrapper fixture');
      inputs[name] = await fileSha256(path.join(sdk, `third_party/llvm/bin/${name}-stage1`));
    }
    await write(path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so'), 'coloured LLVM library fixture');
    if (nativeHost) await fs.copyFile(hostLlvm, path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so'));
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
      lineage: {stage: 'stage3', stdCompilerSha256: compilerSha, bootstrap: {parentSource: {commit: 'd'.repeat(40)}}, source: {commit: 'a'.repeat(40)}, llvmLibrarySha256: inputs.llvmLibrary, parentSha256: 'd'.repeat(64), compilerSha256: compilerSha,
        llvmManifestSha256: inputs.llvmManifest, stdSha256: await stdIdentity(std), runtimeSha256: inputs.runtime}});
    await json(path.join(runtime, 'manifest.json'), {runtime_sha: 'b'.repeat(40), files: runtimeFiles, build: {sourceCommit: 'b'.repeat(40), installed: runtimeFiles, buildInputs: {commands: ['synthetic build'], compiler_state: {fixture: true}}}});
    const pack = () => invoke('pack', '--sdk', sdk, '--std', std, '--compiler', compiler,
      '--runtime', runtime, '--host', host, '--host-llvm', hostLlvm, '--host-pins', hostPin, '--host-identity', 'test fixture',
      '--llvm-manifest', llvmManifest, '--output', output, '--cjcj-sha', 'a'.repeat(40), '--runtime-sha', 'b'.repeat(40),
      '--llvm-sha', 'c'.repeat(40), '--run-id', '42', '--run-attempt', '1', '--node', process.execPath);
    const pins = async () => ['--manifest-sha256', await fileSha256(path.join(output, 'language-tuple.json')),
      '--compiler-sha256', compilerSha];
    await body({root, sdk, std, runtime, host, compiler, output, pack, pins, hostLlvm});
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


test('source producer refuses std built by the bootstrap parent instead of shipped compiler', () => fixture(async ({root, std, pack}) => {
  const receiptPath = path.join(std, 'SOURCE-BUILD.json');
  const receipt = JSON.parse(await fs.readFile(receiptPath));
  receipt.inputs.compiler = 'd'.repeat(64);
  await json(receiptPath, receipt);
  // Keep the outer std digest consistent: the refusal must concern compiler
  // identity, rather than being hidden by a stale payload digest.
  const compilerPath = path.join(root, 'compiler/FINAL-COMPILER-PROVENANCE.json');
  const compiler = JSON.parse(await fs.readFile(compilerPath));
  compiler.production.stdSha256 = await stdIdentity(std);
  await json(compilerPath, compiler);
  assert.throws(pack, /source tuple stage\/source\/parent mismatch/);
}));

test('source producer rejects a different official host LLVM identity', () => fixture(async ({hostLlvm, pack, output}) => {
  await write(hostLlvm, 'wrong host LLVM');
  assert.throws(pack, /SOURCE_TUPLE_OFFICIAL_HOST_PIN libLLVM-15.so/);
  console.log('HOST_LLVM_BEFORE_COPY_ASSERT_REACHED');
  await assert.rejects(fs.stat(output), {code: 'ENOENT'});
}));

test('official native tools survive transport and deletion of producer SDK', {
  skip: !(process.env.SOURCE_TUPLE_OFFICIAL_SDK && process.env.SOURCE_TUPLE_HOST_LLVM && process.env.SOURCE_TUPLE_COMPILER_SDK && process.env.SOURCE_TUPLE_COMPILER),
}, () => fixture(async ({root, sdk, std, runtime, host, compiler, output, pack, pins}) => {
  pack();
  const pin = await pins();
  const archive = path.join(output, (await fs.readdir(output)).find(name => name.endsWith('.tar.gz')));
  const downloaded = path.join(root, 'downloaded');
  invoke('unpack', '--archive', archive, '--archive-sha256', await fileSha256(archive), '--output', downloaded, ...pin);
  const target = path.join(root, 'target');
  const options = [];
  for (const [name, flag] of [['libcangjie-runtime.so', 'target-runtime'], ['libboundscheck.so', 'target-boundscheck']]) {
    await write(path.join(target, name), `independent target fixture ${name}`);
    options.push(`--${flag}-sha256`, await fileSha256(path.join(target, name)));
  }
  const active = path.join(root, 'active');
  invoke('activate', '--root', path.join(downloaded, 'tuple'), '--target', target, '--output', active, ...options, ...pin);
  const moved = path.join(root, 'moved');
  await fs.rename(active, moved);
  for (const dir of [sdk, std, runtime, host, compiler, output]) await fs.rm(dir, {recursive: true});
  const manifest = JSON.parse(await fs.readFile(path.join(downloaded, 'tuple/language-tuple.json'), 'utf8'));
  console.log('OFFICIAL_TOOLS_PATCH_RECORD ' + JSON.stringify(manifest.official_host));
  console.log('OFFICIAL_TOOLS_ROLE_DIGESTS ' + JSON.stringify(manifest.role_sha256));
  const observations = [];
  for (const relative of ['tools/bin/cjpm', 'third_party/llvm/bin/llvm-ar', 'third_party/llvm/bin/llvm-objcopy']) {
    const native = path.join(moved, 'sdk', relative + '-stage1');
    assert.deepEqual((await fs.readFile(native)).subarray(0, 4), Buffer.from([0x7f, 0x45, 0x4c, 0x46]));
    const result = spawnSync(path.join(moved, 'sdk', relative), ['--version'], {
      encoding: 'utf8', timeout: 30000, env: {...process.env, LD_LIBRARY_PATH: '/nonexistent-colour-loader', cjHeapSize: '1GB', LD_DEBUG: 'libs', LD_DEBUG_OUTPUT: path.join(root, 'loader')},
    });
    observations.push({tool: relative, rc: result.status, signal: result.signal,
      sha256: await fileSha256(native), output: result.stdout + result.stderr, error: result.error?.message});
  }
  console.log('OFFICIAL_TOOLS_RELOCATION_ASSERT_REACHED ' + JSON.stringify(observations));
  assert.deepEqual(observations.map(row => row.rc), [0, 0, 0], JSON.stringify(observations));
  const traces = await Promise.all((await fs.readdir(root)).filter(name => name.startsWith('loader.')).map(name => fs.readFile(path.join(root, name), 'utf8')));
  console.log('LOADER_PROGRAMS ' + JSON.stringify(traces.flatMap(text => text.match(/initialize program: .*/g) ?? [])));
  const compilerTrace = traces.find(text => text.includes('initialize program:') && /initialize program: (?:.*\/bin\/)?(cjc|cjc-frontend|cjcj-stage1)\s/.test(text));
  const hostTrace = traces.find(text => /initialize program: .*\/cjpm-stage1\s/.test(text));
  // Preserve the actually executed patched ELFs and loader traces when the
  // integration runner provides its durable artifact directory.
  if (process.env.SOURCE_TUPLE_EVIDENCE_DIR) {
    const evidence = path.resolve(process.env.SOURCE_TUPLE_EVIDENCE_DIR);
    await fs.mkdir(evidence, {recursive: true});
    await json(path.join(evidence, 'manifest.json'), manifest);
    await json(path.join(evidence, 'loader-traces.json'), traces);
    await json(path.join(evidence, 'observations.json'), observations);
    for (const row of observations) {
      const native = path.join(moved, 'sdk', row.tool + '-stage1');
      await fs.copyFile(native, path.join(evidence, path.basename(native)));
    }
  }
  console.log('COMPILER_CHILD_LOADER_ASSERT_REACHED ' + JSON.stringify({compiler: compilerTrace?.match(/calling init: .*libcangjie-runtime.so/g), host: hostTrace?.match(/calling init: .*libcangjie-runtime.so/g)}));
  assert.match(compilerTrace ?? '', /calling init: .*\/compiler-runtime\/linux_x86_64_cjnative\/libcangjie-runtime.so/);
  assert.match(hostTrace ?? '', /calling init: .*\/official-host\/linux_x86_64_cjnative\/libcangjie-runtime.so/);
  for (const row of observations) assert.match(row.output, row.tool === 'tools/bin/cjpm' ? /^Cangjie Project Manager: \d+\.\d+/ : /LLVM version \d+\.\d+/);
}, true));
