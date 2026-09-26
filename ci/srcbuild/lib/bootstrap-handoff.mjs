import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

export async function assertBootstrapCompiler({sdk, command}) {
  const identity = JSON.parse(await fs.readFile(path.join(sdk, 'bootstrap-compiler.json'), 'utf8'));
  const compiler = path.join(sdk, 'bin', 'cjcj-stage2');
  const entry = path.join(sdk, 'bin', 'cjc');
  if (await fs.realpath(command) !== await fs.realpath(entry)
    || await sha256(entry) !== identity.entrySha256
    || await sha256(compiler) !== identity.compilerSha256
    || await sha256(identity.producer) !== identity.compilerSha256) {
    throw new Error('bootstrap compiler identity mismatch');
  }
  return identity;
}

const quote = value => `'${value.replaceAll("'", "'\\''")}'`;

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
    ...['opt', 'llc'].map(name => path.join(inputSdk, 'third_party', 'llvm', 'bin', `${name}-stage1`)),
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
  await fs.cp(inputSdk, sdk, {recursive: true, verbatimSymlinks: true});
  for (const entry of await fs.readdir(std)) {
    await fs.cp(path.join(std, entry), path.join(sdk, entry), {recursive: true, force: true, verbatimSymlinks: true});
  }
  const targetLd = [path.join(sdk, 'runtime', 'lib', tuple), path.join(sdk, 'lib', tuple),
    path.join(sdk, 'third_party', 'llvm', 'lib'), path.join(sdk, 'tools', 'lib'),
    '/usr/lib/x86_64-linux-gnu'].join(':');
  const runner = async (entry, real, ld, heap = null) => {
    await fs.rm(entry, {force: true});
    await fs.writeFile(entry, `#!/usr/bin/env bash\nexport CANGJIE_HOME=${quote(sdk)}\nexport LD_LIBRARY_PATH=${quote(ld)}\n${heap === null ? '' : `export cjHeapSize=${quote(heap)}\n`}exec ${quote(real)} "$@"\n`, {mode: 0o755});
  };
  await fs.copyFile(compiler, path.join(sdk, 'bin', 'cjcj-stage2'));
  await fs.chmod(path.join(sdk, 'bin', 'cjcj-stage2'), 0o755);
  // Only the coloured compiler needs the larger heap. The official host cjpm
  // must retain the resource-limited parent value (its limit excludes swap).
  await runner(path.join(sdk, 'bin', 'cjc'), path.join(sdk, 'bin', 'cjcj-stage2'), targetLd, '20GB');
  await runner(path.join(sdk, 'tools', 'bin', 'cjpm'), path.join(sdk, 'tools', 'bin', 'cjpm-stage1'), binding.host_ld);
  for (const name of ['opt', 'llc']) {
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
