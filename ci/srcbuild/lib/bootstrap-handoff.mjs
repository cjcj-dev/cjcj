import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {verifyColourTuple} from '../../release/bootstrap_tuple.mjs';
import {parseLlvmToolsManifest} from '../../llvm-tools-manifest.mjs';

const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

export async function assertBootstrapCompiler({sdk, command, producer, producerSha256, targetLd}) {
  const identity = JSON.parse(await fs.readFile(path.join(sdk, 'bootstrap-compiler.json'), 'utf8'));
  const compiler = path.join(sdk, 'bin', 'cjcj-stage2');
  if (producer && (await fs.realpath(identity.producer) !== await fs.realpath(producer)
    || await sha256(producer) !== producerSha256 || identity.compilerSha256 !== producerSha256)) {
    throw new Error('bootstrap compiler independent producer mismatch');
  }
  const entry = path.join(sdk, 'bin', 'cjc');
  if (await fs.realpath(command) !== await fs.realpath(entry)
    || await sha256(entry) !== identity.entrySha256
    || await sha256(compiler) !== identity.compilerSha256
    || await sha256(identity.producer) !== identity.compilerSha256) {
    throw new Error('bootstrap compiler identity mismatch');
  }
  if (targetLd && await fs.readFile(entry, 'utf8') !== runnerText(sdk, compiler, targetLd)) {
    throw new Error('bootstrap compiler runner binding mismatch');
  }
  return identity;
}

const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
const runnerText = (sdk, real, ld) => `#!/usr/bin/env bash\nexport CANGJIE_HOME=${quote(sdk)}\nexport LD_LIBRARY_PATH=${quote(ld)}\nexec ${quote(real)} "$@"\n`;

// stage1_host_runner.sh binds absolute paths. Rebind its managed host tool and
// native backends when promoting the bootstrap SDK to the stage2 consumer.
export async function prepareBootstrapHandoff({work, sdk, source, tuple}) {
  work = await fs.realpath(work);
  sdk = path.resolve(sdk);
  source = path.resolve(source);
  const inputSdk = path.join(work, 'sdk-stage1');
  const compiler = path.join(work, 'cjcj-stage2');
  const std = path.join(work, 'stdlib-stage2');
  const shim = path.join(work, 'cjcj-src-stage1', 'runtime_shim');
  const objects = ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o'];
  // Check every producer before replacing the consumer tree.
  for (const file of [compiler, path.join(std, 'lib', tuple, 'libcangjie-std-core.a'),
    path.join(inputSdk, '.stage1-host', 'binding.txt'),
    path.join(inputSdk, 'tools', 'bin', 'cjpm-stage1'),
    ...['opt', 'llc', 'ld.lld'].map(name => path.join(inputSdk, 'third_party', 'llvm', 'bin', `${name}-stage1`)),
    ...objects.map(name => path.join(shim, name))]) {
    if (!(await fs.stat(file)).isFile()) throw new Error(`bootstrap handoff input is not a file: ${file}`);
  }
  if (sdk === path.parse(sdk).root || sdk === work || work.startsWith(`${sdk}${path.sep}`)
    || sdk.startsWith(`${work}${path.sep}`)) {
    throw new Error('bootstrap handoff SDK must be separate from bootstrap work');
  }
  const binding = Object.fromEntries((await fs.readFile(path.join(inputSdk, '.stage1-host', 'binding.txt'), 'utf8'))
    .trim().split('\n').map(line => { const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)]; }));
  if (!binding.host_ld) throw new Error('bootstrap handoff requires the stage1 host loader binding');
  await fs.rm(sdk, {recursive: true, force: true});
  // Materialize both producers: retaining library links makes the std overlay
  // collide with existing links and leaves the promoted SDK tied to its inputs.
  await fs.cp(inputSdk, sdk, {recursive: true, dereference: true});
  for (const entry of await fs.readdir(std)) {
    await fs.cp(path.join(std, entry), path.join(sdk, entry), {recursive: true, force: true, dereference: true});
  }
  const targetLd = [path.join(sdk, 'runtime', 'lib', tuple), path.join(sdk, 'lib', tuple),
    path.join(sdk, 'third_party', 'llvm', 'lib'), path.join(sdk, 'tools', 'lib'),
    '/usr/lib/x86_64-linux-gnu'].join(':');
  const runner = async (entry, real, ld) => {
    await fs.rm(entry, {force: true});
    await fs.writeFile(entry, runnerText(sdk, real, ld), {mode: 0o755});
  };
  await fs.copyFile(compiler, path.join(sdk, 'bin', 'cjcj-stage2'));
  await fs.chmod(path.join(sdk, 'bin', 'cjcj-stage2'), 0o755);
  // Heap policy belongs to the calling recipe. Both compiler and host tools
  // inherit its environment; only their loader bindings differ here.
  await runner(path.join(sdk, 'bin', 'cjc'), path.join(sdk, 'bin', 'cjcj-stage2'), targetLd);
  await runner(path.join(sdk, 'tools', 'bin', 'cjpm'), path.join(sdk, 'tools', 'bin', 'cjpm-stage1'), binding.host_ld);
  for (const name of ['opt', 'llc', 'ld.lld']) {
    await runner(path.join(sdk, 'third_party', 'llvm', 'bin', name),
      path.join(sdk, 'third_party', 'llvm', 'bin', `${name}-stage1`), targetLd);
  }
  await fs.rm(path.join(sdk, '.stage1-host'), {recursive: true});
  await fs.mkdir(path.join(source, 'runtime_shim'), {recursive: true});
  for (const name of objects) await fs.copyFile(path.join(shim, name), path.join(source, 'runtime_shim', name));
  await fs.writeFile(path.join(sdk, 'bootstrap-compiler.json'), `${JSON.stringify({
    producer: compiler,
    compilerSha256: await sha256(compiler),
    entrySha256: await sha256(path.join(sdk, 'bin', 'cjc')),
  }, null, 2)}\n`);
  return {compiler, targetLd};
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
    const file = path.join(root, rel);
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
  for (const name of ['opt', 'llc', 'ld.lld']) {
    const entry = path.join(root, 'bin', name);
    if (await fs.readFile(entry, 'utf8') !== runnerText(sdk, `${entry}-stage1`, targetLd)) {
      throw new Error(`BOOTSTRAP_BACKEND_RUNNER_MISMATCH: ${name}`);
    }
  }
  console.log(`BOOTSTRAP_BACKEND_CONSUMER_VERIFIED llvm=${identity.llvmSha}`);
}
