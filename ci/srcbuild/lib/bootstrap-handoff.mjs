import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {verifyColourTuple} from '../../release/bootstrap_tuple.mjs';
import {parseLlvmToolsManifest} from '../../llvm-tools-manifest.mjs';
import {readBootstrapStdOutput} from '../../bootstrap/std-output.mjs';
import {assembleBootstrapPhase} from '../../bootstrap/bootstrap-sdk.mjs';
import {readJson} from '../../bootstrap/sdk-manifest.mjs';

const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

export async function assertBootstrapCompiler({sdk, command, producer, producerSha256, targetLd}) {
  const plan = await readJson(path.join(sdk, 'SDK.plan.json'));
  const manifest = await readJson(path.join(sdk, 'SDK.manifest.json'));
  const entry = path.join(sdk, 'bin', 'cjc');
  const output = manifest.files['bin/cjc'];
  if (plan.stage !== 'stage2' || !producer || !output
    || manifest.components[output.component]?.source.kind !== 'git'
    || await sha256(producer) !== producerSha256 || output.sha256 !== producerSha256
    || await sha256(entry) !== producerSha256
    || await fs.realpath(command) !== await fs.realpath(entry)) {
    throw new Error('bootstrap compiler independent producer mismatch');
  }
  return {producer, compilerSha256: producerSha256, entrySha256: await sha256(entry)};
}

// Every installed byte comes from the stage2 plan. Handoff only materializes
// authenticated compiler shim inputs in the next compiler's source tree.
export async function prepareBootstrapHandoff({work, sdk, source, tuple, plans = process.env.CJCJ_BOOTSTRAP_SDK_PLANS}) {
  work = await fs.realpath(work);
  sdk = path.resolve(sdk);
  source = path.resolve(source);
  const compiler = path.join(work, 'cjcj-stage2');
  const stdOutput = await readBootstrapStdOutput({work, tuple});
  const objects = ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o'];
  for (const file of [compiler, path.join(stdOutput.prefix, 'lib', tuple, 'libcangjie-std-core.a')]) {
    if (!(await fs.stat(file)).isFile()) throw new Error(`bootstrap handoff input is not a file: ${file}`);
  }
  if (sdk === path.parse(sdk).root || sdk === work || work.startsWith(`${sdk}${path.sep}`)
    || sdk.startsWith(`${work}${path.sep}`)) {
    throw new Error('bootstrap handoff SDK must be separate from bootstrap work');
  }
  if (!plans) throw new Error('bootstrap handoff requires complete frozen SDK plans');
  await assembleBootstrapPhase({plans, phase: 'stage2', out: sdk});
  const manifest = await readJson(path.join(sdk, 'SDK.manifest.json'));
  const compilerRow = manifest.files['bin/cjc'];
  if (compilerRow?.sha256 !== await sha256(compiler)) throw new Error('bootstrap compiler independent producer mismatch');
  if (manifest.files[`lib/${tuple}/libcangjie-std-core.a`]?.sha256 !== stdOutput.coreSha256) {
    throw new Error('bootstrap handoff std producer mismatch');
  }
  const targetLd = [path.join(sdk, 'runtime', 'lib', tuple), path.join(sdk, 'lib', tuple),
    path.join(sdk, 'third_party', 'llvm', 'lib'), path.join(sdk, 'tools', 'lib'),
    '/usr/lib/x86_64-linux-gnu'].join(':');
  await fs.mkdir(path.join(source, 'runtime_shim'), {recursive: true});
  for (const name of objects) {
    const rel = `share/cjcj/runtime_shim/${name}`;
    const row = manifest.files[rel];
    if (!row || row.component !== compilerRow.component || await sha256(path.join(sdk, rel)) !== row.sha256) {
      throw new Error(`bootstrap handoff compiler shim receipt mismatch: ${name}`);
    }
    await fs.copyFile(path.join(sdk, rel), path.join(source, 'runtime_shim', name));
  }
  return {compiler, targetLd, stdOutput, assemblyLockSha: await sha256(path.join(sdk, 'SDK.lock.json'))};
}

// Expectations come from the authenticated tuple and process-library inputs,
// independently of the promoted SDK and its pre-runner assembly lock.
export async function bootstrapBackendIdentity(env = process.env) {
  const {directory} = verifyColourTuple(env.CJCJ_BOOTSTRAP_COLOUR_TUPLE, {
    pinFile: env.CJCJ_BOOTSTRAP_INPUTS_PIN,
    sumsSha: env.LLVM_TUPLE_SUMS_SHA,
  });
  const {values} = parseLlvmToolsManifest(await fs.readFile(path.join(directory, 'fixed-llc', 'llvm-tools.manifest'), 'utf8'));
  const llvmSha = env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA;
  const library = env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SO;
  const librarySha = env.CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256;
  const libraryName = process.platform === 'darwin' ? 'libLLVM.dylib' : 'libLLVM-15.so';
  if (!library || path.basename(library) !== libraryName) throw new Error('BOOTSTRAP_BACKEND_LIBRARY_NAME_MISMATCH');
  const manifest = JSON.parse(await fs.readFile(path.join(path.dirname(library), 'manifest.json'), 'utf8'));
  if (!/^[a-f0-9]{40}$/.test(llvmSha || '') || values.get('LLVM_SHA') !== llvmSha
    || !/^[a-f0-9]{64}$/.test(librarySha || '') || await sha256(library) !== librarySha
    || manifest.llvm_sha !== llvmSha || manifest.sha256 !== librarySha
    || JSON.stringify(manifest.targets) !== JSON.stringify(['X86', 'ARM', 'AArch64'])) {
    throw new Error('BOOTSTRAP_BACKEND_INPUT_MISMATCH');
  }
  return {llvmSha, files: {
    'bin/opt-stage1': values.get('OPT_SHA256'),
    'bin/llc-stage1': values.get('LLC_SHA256'),
    [`bin/${values.get('LLD_TOOL')}-stage1`]: values.get('LLD_SHA256'),
    [`lib/${path.basename(library)}`]: librarySha,
  }};
}

export async function assertBootstrapBackends({sdk, targetLd, identity}) {
  const root = path.join(sdk, 'third_party', 'llvm');
  for (const [rel, expected] of Object.entries(identity.files)) {
    const file = path.join(root, rel.replace(/-stage1$/, ''));
    const bytes = await fs.readFile(file);
    if (await sha256(file) !== expected) throw new Error(`BOOTSTRAP_BACKEND_HASH_MISMATCH: ${rel}`);
    const stamps = [...new Set(bytes.toString('latin1').match(/CJLLVM-COMMIT:[A-Za-z0-9_-]+/g) || [])];
    if (stamps.length !== 1 || stamps[0] !== `CJLLVM-COMMIT:${identity.llvmSha}`) {
      throw new Error(`BOOTSTRAP_BACKEND_STAMP_MISMATCH: ${rel}`);
    }
  }
  const library = Object.keys(identity.files).find(rel => rel.startsWith('lib/'));
  const libraryPath = path.join(root, library);
  const resolved = await Promise.all(targetLd.split(':').map(async dir => {
    const file = path.join(dir, path.basename(library));
    try { return await fs.realpath(file); } catch { return null; }
  }));
  if (resolved.find(Boolean) !== await fs.realpath(libraryPath)) {
    throw new Error('BOOTSTRAP_BACKEND_LOADER_MISMATCH');
  }
  console.log(`BOOTSTRAP_BACKEND_CONSUMER_VERIFIED llvm=${identity.llvmSha}`);
}
