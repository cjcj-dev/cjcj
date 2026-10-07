#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {prepareBootstrapHandoff} from '../../ci/srcbuild/lib/bootstrap-handoff.mjs';

const repo = path.resolve(import.meta.dirname, '../..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
const parent = process.env.BOOTSTRAP_STD_TEST_ROOT || process.env.RELEASE_EVIDENCE_TEST_ROOT || os.tmpdir();
await fs.mkdir(parent, {recursive: true});
const evidence = await fs.mkdtemp(path.join(parent, 'bootstrap-std-output-'));
let serial = 0;

// Only native build/SDK prerequisites are fixtures. The shell dispatcher,
// stage1_inputs, both recipe branches, stage1_compiler, install and publication
// are the product functions. No record is manufactured by the test.
async function fixture(recipe) {
  const root = path.join(evidence, `${recipe}-${++serial}`);
  await fs.mkdir(root, {recursive: true});
  const work = path.join(root, 'work');
  const tuple = 'linux_x86_64_cjnative';
  const write = async (relative, bytes) => {
    const file = path.join(root, relative);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, bytes, {mode: 0o755});
  };
  const compiler = '#!/bin/bash\ncat "$CANGJIE_HOME/lib/linux_x86_64_cjnative/libcangjie-std-core.a"\n';
  await write('work/cjcj-stage1', 'fixture stage1 compiler');
  await write('stage1-input', 'fixture stage1 compiler');
  await write('work/.cjcj-stage1', `${work}/cjcj-stage1\n`);
  await write('seed', compiler);
  await write(`std/lib/${tuple}/libcangjie-std-core.a`, `std bytes from ${recipe}`);
  await write('std/std-producer.json', JSON.stringify({compiler_sha256: hash('fixture stage1 compiler')}));
  await write('std/modules/full-prefix-member', 'another std member');
  await write('work/sdk-stage1/.stage1-host/binding.txt', 'host_ld=/fixture/host\n');
  await write('work/sdk-stage1/bin/cjc', '#!/bin/bash\nexit 0\n');
  await write(`work/sdk-stage1/lib/${tuple}/libcangjie-std-core.a`, 'old sdk std');
  for (const rel of ['tools/bin/cjpm-stage1', ...['opt', 'llc', 'ld.lld'].map(n => `third_party/llvm/bin/${n}-stage1`)]) {
    await write(`work/sdk-stage1/${rel}`, '#!/bin/bash\nexit 0\n');
  }
  for (const name of ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o']) {
    await write(`work/cjcj-src-stage1/runtime_shim/${name}`, `fixture ${name}`);
  }
  const script = `source ${quote(path.join(repo, 'ci/bootstrap/bootstrap.sh'))}
WORK=${quote(work)}; SRC=${quote(repo)}; FIXTURE=${quote(root)}
CJCJ_SHA=fixture; STDSRC=fixture; CPP_SRC=fixture; HOST_LLVM_SO=fixture; HOST_LLVM_SHA256=fixture
COLOUR_LLVM_SO=fixture; COLOUR_LLVM_SHA256=fixture; AST_SUPPORT=fixture; AST_SUPPORT_SHA256=fixture
COLOUR_TUPLE=fixture; COLOUR_LLVM_SHA=fixture; CRT=fixture; HRT=fixture; HOST_SDK=fixture; STAGE1_ELF="$FIXTURE/stage1-input"
record() { :; }; assert_llvm() { :; }; assert_cjcj_sha() { :; }; assert_cjcj_root() { :; }
host_tuple_init() { HOST_TUPLE=${tuple}; }; supplied_stage1_validate() { :; }
stage0() { :; }; prepare_stage0_run_sdk() { :; }; assemble_stage1_sdk() { :; }
bootstrap_target_std() { stdlib_build stdlib-stage1 fixture fixture "$2"; }
stdlib_build() { cp -a "$FIXTURE/std" "$4"; }
isolate_cjcj_src() { :; }; shim_build() { :; }; cjpm_build() { :; }
resolve_cjpm_product() { printf '%s\\n' "$FIXTURE/seed"; }
assert_executable() { test -x "$2"; }; assert_version() { :; }; stage2_forensic() { :; }
sdk_ld_path() { printf '/fixture/loader'; }
cmd() { case "$1" in python3*|env*|cp*) printf 'FIXTURE_NATIVE_BOUNDARY %s\\n' "$1";; *) eval "$1" || exit $?;; esac; }
main --stage ${recipe}
`;
  const run = spawnSync('bash', ['-c', script], {encoding: 'utf8'});
  await fs.writeFile(path.join(root, 'producer.log'), run.stdout + run.stderr);
  await fs.writeFile(path.join(root, 'producer.rc'), `${run.status}\n`);
  assert.equal(run.status, 0, run.stdout + run.stderr);
  const f = {root, work, tuple, sdk: path.join(root, 'consumer-sdk'), source: path.join(root, 'source')};
  f.recordFile = path.join(work, 'bootstrap-std-output.json');
  f.record = JSON.parse(await fs.readFile(f.recordFile, 'utf8'));
  return f;
}

for (const recipe of ['all', 'supplied-stage1']) {
  test(`real bootstrap ${recipe} publishes and handoff consumes its actual full std prefix`, async () => {
    const f = await fixture(recipe);
    const expected = path.join(f.work, recipe === 'all' ? 'stdlib-stage2' : 'stdlib-stage1');
    // Print before asserting, so a producer cut reaches the identity assertion.
    console.log(`STD_PRODUCER_ASSERT_REACHED recipe=${recipe} expected=${expected} actual=${f.record.prefix}`);
    assert.equal(f.record.prefix, expected);
    if (recipe === 'supplied-stage1') await assert.rejects(fs.stat(path.join(f.work, 'stdlib-stage2')), {code: 'ENOENT'});
    const result = await prepareBootstrapHandoff(f);
    const run = spawnSync(path.join(f.sdk, 'bin', 'cjc'), {encoding: 'utf8'});
    await fs.writeFile(path.join(f.root, 'consumer.log'), run.stdout + run.stderr);
    await fs.writeFile(path.join(f.root, 'consumer.rc'), `${run.status}\n`);
    console.log(`STD_CONSUMER_ASSERT_REACHED recipe=${recipe} prefix=${result.stdOutput.prefix} bytes=${run.stdout}`);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, `std bytes from ${recipe}`);
    assert.equal(await fs.readFile(path.join(f.sdk, 'modules/full-prefix-member'), 'utf8'), 'another std member');
  });
}

for (const mutation of ['prefix', 'compiler', 'stage2', 'std-byte']) {
  test(`handoff input admission rejects ${mutation} before replacing the SDK`, async () => {
    const f = await fixture('supplied-stage1');
    await fs.mkdir(f.sdk);
    await fs.writeFile(path.join(f.sdk, 'sentinel'), 'preserve consumer');
    let restore;
    if (mutation === 'prefix') {
      await fs.writeFile(f.recordFile, JSON.stringify({...f.record, prefix: f.root}));
      restore = () => fs.writeFile(f.recordFile, JSON.stringify(f.record));
    } else {
      const file = mutation === 'compiler' ? path.join(f.work, 'cjcj-stage1')
        : mutation === 'stage2' ? path.join(f.work, 'cjcj-stage2')
          : path.join(f.record.prefix, 'modules/full-prefix-member');
      const original = await fs.readFile(file);
      await fs.appendFile(file, 'X');
      restore = () => fs.writeFile(file, original);
    }
    const expected = {prefix: /BOOTSTRAP_STD_PREFIX_MISMATCH/, compiler: /BOOTSTRAP_STD_COMPILER_MISMATCH/,
      stage2: /BOOTSTRAP_STD_IDENTITY_MISMATCH: stage2Sha256/, 'std-byte': /BOOTSTRAP_STD_IDENTITY_MISMATCH: prefixSha256/}[mutation];
    await assert.rejects(prepareBootstrapHandoff(f), error => {
      console.log(`STD_ADMISSION_ASSERT_REACHED mutation=${mutation} error=${error.message}`);
      return expected.test(error.message);
    });
    assert.equal(await fs.readFile(path.join(f.sdk, 'sentinel'), 'utf8'), 'preserve consumer');
    await restore();
    await prepareBootstrapHandoff(f);
    console.log(`STD_ADMISSION_RESTORED_PASS mutation=${mutation}`);
  });
}
