#!/usr/bin/env zx
// Small native fixture producer for the real sharedbuild engine. These ELF
// files exercise SDK assembly/identity, and are not Cangjie compiler evidence.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import {gzipSync} from 'node:zlib';
const env = process.env, output = env.SB_OUTPUT, build = env.TMPDIR;
const options = JSON.parse(await fs.readFile(env.SB_PARAMETERS, 'utf8'));
const run = args => {
  const result = spawnSync(args[0], args.slice(1), {cwd: env.SB_SOURCE, env, stdio: 'inherit'});
  if (result.error || result.status !== 0) throw new Error(`fixture producer rc=${result.status}: ${args[0]}`);
};
const mkdir = async file => { await fs.mkdir(path.dirname(file), {recursive: true}); return file; };
const write = async (rel, text) => fs.writeFile(await mkdir(path.join(output, rel)), text);
const sha = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
if (options.mode === 'fail') { console.error('FIXTURE_PRODUCER_FAILURE rc=17'); process.exit(17); }
let mode = options.mode;
if (mode === 'runtime-fail-once') {
  // Model a failed incremental build step inside its declared work directory,
  // without changing source, recipe, tool bytes or external fixture inputs.
  const marker = path.join(build, 'first-attempt-failed');
  try { await fs.access(marker); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    await fs.writeFile(marker, 'deliberate fixture failure\n');
    console.error('FIXTURE_PRODUCER_FAILURE rc=17'); process.exit(17);
  }
  mode = 'runtime';
}
const tuple = 'linux_x86_64_cjnative';
if (mode === 'runtime') {
  const shared = await mkdir(path.join(output, 'install/runtime/lib', tuple, 'libcangjie-runtime.so'));
  run(['cc', '-shared', '-fPIC', `-DCJRT_SHA="${env.SB_SHA}"`, '-DFIXTURE_COLOUR=1', 'runtime.c', '-o', shared]);
  run(['cc', '-c', '-fPIC', `-DCJRT_SHA="${env.SB_SHA}"`, '-DFIXTURE_COLOUR=1', 'runtime.c', '-o', path.join(build, 'runtime.o')]);
  run(['ar', 'rcs', await mkdir(path.join(output, 'install/lib', tuple, 'libcangjie-runtime.a')), path.join(build, 'runtime.o')]);
  run(['cc', '-shared', '-fPIC', 'boundscheck.c', '-o', await mkdir(path.join(output, 'install/runtime/lib', tuple, 'libboundscheck.so'))]);
} else if (options.mode === 'compiler') {
  const binary = await mkdir(path.join(output, 'cjcj-stage1'));
  run(['cc', `-DCJLLVM_SHA="${env.SB_SHA}"`, 'tool.c', '-o', binary]);
} else if (options.mode === 'std') {
  run(['cc', '-c', '-fPIC', '-DFIXTURE_COLOUR=1', 'std.c', '-o', path.join(build, 'std.o')]);
  run(['ar', 'rcs', await mkdir(path.join(output, 'lib', tuple, 'libcangjie-std-core.a')), path.join(build, 'std.o')]);
  run(['cc', '-shared', '-fPIC', '-DFIXTURE_COLOUR=1', 'std.c', '-o', await mkdir(path.join(output, 'runtime/lib', tuple, 'libcangjie-std-core.so'))]);
  await write(`modules/${tuple}/std/core/core.Int64.ti`, 'fixture module\n');
  await write('std-producer.json', JSON.stringify({compiler_sha256: await sha(path.join(env.SB_INPUTS, 'compiler'))}) + '\n');
} else if (options.mode === 'llvm-tools') {
  const values = {PLATFORM: 'linux_x86_64', LLVM_SHA: env.SB_SHA,
    CANGJIE_COMPILER_SHA: options.compilerSha, FLATBUFFERS_SHA: options.flatbuffersSha};
  for (const [name, prefix] of [['llc', 'LLC'], ['opt', 'OPT'], ['ld.lld', 'LLD']]) {
    const binary = await mkdir(path.join(output, 'bin', name));
    run(['cc', `-DCJLLVM_SHA="${env.SB_SHA}"`, 'tool.c', '-o', binary]);
    await write(`fixed-llc/${name}.gz`, gzipSync(await fs.readFile(binary)));
    values[`${prefix}_SOURCE`] = `tuple:${env.SB_SHA}`; values[`${prefix}_VERSION`] = 'fixture tool version 1';
    values[`${prefix}_SHA256`] = await sha(binary);
  }
  const manifest = `PLATFORM=linux_x86_64\nLLVM_SHA=${env.SB_SHA}\n`;
  await write('MANIFEST', manifest); await write('lib/STATIC_LLVM.txt', manifest);
  await write('fixed-llc/cjselfhost_llvmshim.o', 'fixture AST shim\n');
  values.LLD_TOOL = 'ld.lld'; values.SHIM_SHA256 = await sha(path.join(output, 'fixed-llc/cjselfhost_llvmshim.o'));
  await write('fixed-llc/llvm-tools.manifest', Object.entries(values).map(([name, value]) => `${name}=${value}\n`).join(''));
  const files = ['MANIFEST', 'bin/llc', 'bin/opt', 'bin/ld.lld', 'lib/STATIC_LLVM.txt',
    'fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/llc.gz', 'fixed-llc/opt.gz', 'fixed-llc/ld.lld.gz', 'fixed-llc/llvm-tools.manifest'];
  await write('SHA256SUMS', (await Promise.all(files.map(async rel => `${await sha(path.join(output, rel))}  ./${rel}\n`))).join(''));
} else if (options.mode === 'llvm-dylib') {
  run(['cc', '-shared', '-fPIC', `-DCJLLVM_SHA="${env.SB_SHA}"`, 'llvm.c', '-o', await mkdir(path.join(output, 'libLLVM-15.so'))]);
  await write('manifest.json', JSON.stringify({llvm_sha: env.SB_SHA, sha256: await sha(path.join(output, 'libLLVM-15.so'))}) + '\n');
} else throw new Error('unknown fixture producer mode');
console.log(`FIXTURE_PRODUCER_EXECUTED mode=${options.mode} actual_sha=${env.SB_SHA}`);
