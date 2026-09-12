import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {prepareBootstrapHandoff} from '../../ci/srcbuild/lib/bootstrap-handoff.mjs';

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
  await write(path.join(inputSdk, 'bin', 'cjc'), '#!/bin/bash\nexit 99\n');
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
  assert.match(await fs.readFile(path.join(f.work, 'sdk-stage1', 'bin', 'cjc'), 'utf8'), /exit 99/);
});

test('missing bootstrap stage2 compiler cannot consume an unrelated old product', async t => {
  const f = await fixture(t);
  await fs.rm(path.join(f.work, 'cjcj-stage2'));
  await assert.rejects(prepareBootstrapHandoff(f), {code: 'ENOENT'});
  assert.equal(await fs.readFile(path.join(f.sdk, 'stale-sdk'), 'utf8'), 'old pipeline');
});
