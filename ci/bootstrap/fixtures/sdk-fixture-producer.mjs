#!/usr/bin/env zx
// Small native fixture producer for the real sharedbuild engine. These ELF
// files exercise SDK assembly/identity, and are not Cangjie compiler evidence.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
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
const tuple = 'linux_x86_64_cjnative';
if (options.mode === 'runtime') {
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
  for (const name of ['llc', 'opt', 'ld.lld']) run(['cc', `-DCJLLVM_SHA="${env.SB_SHA}"`, 'tool.c', '-o', await mkdir(path.join(output, 'bin', name))]);
  await write('MANIFEST', `PLATFORM=linux_x86_64\nLLVM_SHA=${env.SB_SHA}\n`);
  await write('fixed-llc/cjselfhost_llvmshim.o', 'fixture AST shim\n');
} else if (options.mode === 'llvm-dylib') {
  run(['cc', '-shared', '-fPIC', `-DCJLLVM_SHA="${env.SB_SHA}"`, 'llvm.c', '-o', await mkdir(path.join(output, 'libLLVM-15.so'))]);
} else throw new Error('unknown fixture producer mode');
console.log(`FIXTURE_PRODUCER_EXECUTED mode=${options.mode} actual_sha=${env.SB_SHA}`);
