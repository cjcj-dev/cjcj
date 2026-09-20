import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {prepareBootstrapHandoff, assertBootstrapCompiler} from '../../ci/srcbuild/lib/bootstrap-handoff.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'bootstrap-handoff-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const work = path.join(root, 'bootstrap-work');
  const sdk = path.join(root, 'software', 'cangjie');
  const source = path.join(root, 'source');
  const tuple = 'linux_x86_64_cjnative';
  const write = async (name, contents) => {
    await fs.mkdir(path.dirname(name), {recursive: true});
    await fs.writeFile(name, contents, {mode: 0o755});
  };
  const inputSdk = path.join(work, 'sdk-stage1');
  await write(path.join(work, 'cjcj-stage2'), '#!/bin/bash\nprintf "compiler home=%s ld=%s\\n" "$CANGJIE_HOME" "$LD_LIBRARY_PATH"\n');
  await write(path.join(work, 'stdlib-stage2', 'lib', tuple, 'libcangjie-std-core.a'), 'coloured std');
  await write(path.join(inputSdk, 'lib', tuple, 'libcangjie-std-core.a'), 'bootstrap std');
  await write(path.join(inputSdk, '.stage1-host', 'binding.txt'), 'host_ld=/host/runtime:/host/llvm\n');
  await write(path.join(inputSdk, 'tools', 'bin', 'cjpm-stage1'), '#!/bin/bash\nprintf "cjpm home=%s ld=%s\\n" "$CANGJIE_HOME" "$LD_LIBRARY_PATH"\n"$CANGJIE_HOME/bin/cjc"\n');
  for (const name of ['opt', 'llc']) await write(path.join(inputSdk, 'third_party', 'llvm', 'bin', `${name}-stage1`), '#!/bin/bash\nprintf "backend home=%s ld=%s\\n" "$CANGJIE_HOME" "$LD_LIBRARY_PATH"\n');
  for (const name of ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o']) await write(path.join(work, 'cjcj-src-stage1', 'runtime_shim', name), name);
  await fs.symlink('libcangjie-std-core.a', path.join(inputSdk, 'lib', tuple, 'core-relative.a'));
  await write(path.join(inputSdk, 'bin', 'cjc'), '#!/bin/bash\nprintf "old-stage1 compiler\\n"\n');
  await write(path.join(sdk, 'stale-sdk'), 'old pipeline');
  return {root, work, sdk, source, tuple};
}

test('bootstrap handoff consumes stage2 std and compiler and rebinds host and target processes', async t => {
  const f = await fixture(t);
  const result = await prepareBootstrapHandoff(f);
  assert.equal(result.compiler, path.join(f.work, 'cjcj-stage2'));
  assert.equal(await fs.readlink(path.join(f.sdk, 'lib', f.tuple, 'core-relative.a')), 'libcangjie-std-core.a');
  assert.equal(await fs.readFile(path.join(f.sdk, 'lib', f.tuple, 'libcangjie-std-core.a'), 'utf8'), 'coloured std');
  await assert.rejects(fs.stat(path.join(f.sdk, 'stale-sdk')), {code: 'ENOENT'});
  const run = spawnSync(path.join(f.sdk, 'tools', 'bin', 'cjpm'), {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout, `cjpm home=${f.sdk} ld=/host/runtime:/host/llvm\ncompiler home=${f.sdk} ld=${result.targetLd}\n`);
  for (const name of ['opt', 'llc']) {
    const backend = spawnSync(path.join(f.sdk, 'third_party', 'llvm', 'bin', name), {encoding: 'utf8'});
    assert.equal(backend.status, 0, backend.stderr);
    assert.equal(backend.stdout, `backend home=${f.sdk} ld=${result.targetLd}\n`);
  }
  assert.equal(await fs.readFile(path.join(f.source, 'runtime_shim', 'cjselfhost_llvmshim.o'), 'utf8'), 'cjselfhost_llvmshim.o');
  assert.match(await fs.readFile(path.join(f.work, 'sdk-stage1', 'bin', 'cjc'), 'utf8'), /old-stage1 compiler/);
});

test('missing bootstrap stage2 compiler cannot consume an unrelated old product', async t => {
  const f = await fixture(t);
  await fs.rm(path.join(f.work, 'cjcj-stage2'));
  await assert.rejects(prepareBootstrapHandoff(f), {code: 'ENOENT'});
  assert.equal(await fs.readFile(path.join(f.sdk, 'stale-sdk'), 'utf8'), 'old pipeline');
});

for (const mutation of ['none', 'entry', 'installed', 'producer', 'command']) {
  test(`bootstrap compiler identity validates real handoff: ${mutation}`, async t => {
    const f = await fixture(t);
    await prepareBootstrapHandoff(f);
    let command = path.join(f.sdk, 'bin', 'cjc');
    const files = {
      entry: command,
      installed: path.join(f.sdk, 'bin', 'cjcj-stage2'),
      producer: path.join(f.work, 'cjcj-stage2'),
    };
    if (files[mutation]) await fs.appendFile(files[mutation], '\n# replaced input\n');
    if (mutation === 'command') command = path.join(f.work, 'sdk-stage1', 'bin', 'cjc');
    if (mutation === 'none') {
      const identity = await assertBootstrapCompiler({sdk: f.sdk, command});
      assert.equal(identity.producer, path.join(f.work, 'cjcj-stage2'));
      const result = spawnSync(command, {encoding: 'utf8'});
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /compiler home=/);
    } else {
      await assert.rejects(assertBootstrapCompiler({sdk: f.sdk, command}), /bootstrap compiler identity mismatch/);
    }
  });
}

test('bootstrap producer reaches actual stdx and tools subprocess entries', async t => {
  const {buildConfig} = await import('../lib/config.mjs');
  const tools = await import('../srcbuild/stages/tools.mjs');
  const stdx = await import('../srcbuild/stages/stdx.mjs');
  const f = await fixture(t);
  const host = path.join(f.root, 'host-sdk');
  const fakeBin = path.join(f.root, 'external-fixtures');
  const trace = path.join(f.root, 'compiler-invocations.jsonl');
  const write = async (file, data, mode = 0o755) => {
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, data, {mode});
  };
  // Actual ELF symbol tables exercise the existing runtime-split precondition.
  for (const [sdkRoot, source] of [[host, 'int host_runtime;'],
    [path.join(f.work, 'sdk-stage1'), 'long g_cjLoadBadMask;']]) {
    const output = path.join(sdkRoot, 'runtime', 'lib', f.tuple, 'libcangjie-runtime.so');
    await fs.mkdir(path.dirname(output), {recursive: true});
    const built = spawnSync('cc', ['-shared', '-fPIC', '-x', 'c', '-', '-o', output], {input: source, encoding: 'utf8'});
    assert.equal(built.status, 0, built.stderr);
  }
  await fs.appendFile(path.join(f.work, 'cjcj-stage2'), `cat "$CANGJIE_HOME/lib/${f.tuple}/libcangjie-std-core.a"\n`);
  await prepareBootstrapHandoff(f);
  const pin = (await fs.readFile(new URL('../../ci/cjpm_pin.env', import.meta.url), 'utf8')).match(/^CJPM_FORK_REF=(.+)$/m)[1];
  await write(path.join(fakeBin, 'git'), `#!/bin/sh\ncase "$1" in rev-parse) printf '%s\\n' '${pin}' ;; esac\n`);
  const previous = Object.fromEntries(['PATH', 'CJCJ_SRCBUILD_HOST_SDK', 'CANGJIE_BUILD_DRY_RUN'].map(key => [key, process.env[key]]));
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  });
  process.env.PATH = `${fakeBin}:${process.env.PATH}`;
  process.env.CJCJ_SRCBUILD_HOST_SDK = host;
  delete process.env.CANGJIE_BUILD_DRY_RUN;
  const original = buildConfig({workspace: f.root, buildRoot: f.root, consumerSdk: f.sdk});
  const dependencies = path.join(f.root, 'dependencies');
  await fs.mkdir(dependencies);
  const config = {...original, target: {...original.target, spec: {...original.target.spec,
    llvmBinDir: dependencies, opensslLibDir: dependencies}}};
  // Keep an executable old output available: a disconnected consumer must reach
  // the origin assertion, rather than fail merely because a file is absent.
  await write(path.join(config.repoPath('compiler'), 'output', 'bin', 'cjc'), '#!/bin/sh\nprintf "old output compiler\\n"\n');
  const oldRuntime = path.join(config.repoPath('compiler'), 'output', 'runtime', 'lib', f.tuple, 'libcangjie-runtime.so');
  await fs.mkdir(path.dirname(oldRuntime), {recursive: true});
  await fs.copyFile(path.join(f.sdk, 'runtime', 'lib', f.tuple, 'libcangjie-runtime.so'), oldRuntime);
  const python = `import json, os, pathlib, subprocess, sys\nif sys.argv[1] == 'build':\n r = subprocess.run(['cjc'], text=True, capture_output=True)\n r.check_returncode()\n with open(${JSON.stringify(trace)}, 'a') as out: out.write(json.dumps({'cwd': os.getcwd(), 'compiler': r.stdout}) + '\\n')\n p = pathlib.Path('build_temp/build/build.ninja')\n p.parent.mkdir(parents=True, exist_ok=True)\n p.write_text('LD_LIBRARY_PATH=' + os.environ['LD_LIBRARY_PATH'] + ' cjc file.cj\\n')\n`;
  await write(path.join(config.repoPath('stdx'), 'build.py'), python);
  for (const [, directory] of tools.toolsFor(config)) await write(path.join(config.repoPath('tools'), directory, 'build.py'), python);
  await write(path.join(config.repoPath('tools'), 'cjpm', 'dist', 'cjpm'), 'fixture tool product');
  await stdx.run(config);
  await tools.run(config);
  const invocations = (await fs.readFile(trace, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(invocations.length, 1 + tools.toolsFor(config).length);
  for (const row of invocations) {
    console.log(`CONSUMER_ORIGIN_ASSERT_REACHED ${row.cwd}`);
    assert.ok(row.compiler.includes(`compiler home=${f.sdk}`), JSON.stringify(row));
    assert.ok(row.compiler.endsWith('coloured std'), JSON.stringify(row));
  }
});
