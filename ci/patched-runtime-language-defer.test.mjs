import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {patchedRuntimeBuildEnv} from './build_patched_runtime.mjs';

const HOST_RUNTIME_FAIL = 'GC_UNIT_GATE_FAIL: GC_UNIT_CJC_RUNTIME_LIB_DIR must select the compiler host runtime';
const PRODUCT_SOURCE = new URL('./build_patched_runtime.mjs', import.meta.url);

function writeExecutable(file, contents) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents, {mode: 0o755});
}

function sdkFixture(root) {
  const sdk = path.join(root, 'sdk');
  writeExecutable(path.join(sdk, 'bin/cjc'), '#!/bin/sh\nexit 0\n');
  writeExecutable(path.join(sdk, 'third_party/llvm/bin/llc'), '#!/bin/sh\nexit 0\n');
  writeExecutable(path.join(sdk, 'third_party/llvm/bin/opt'), '#!/bin/sh\nexit 0\n');
  const stdArchive = path.join(sdk, 'lib/linux_x86_64_cjnative/libcangjie-std-core.a');
  fs.mkdirSync(path.dirname(stdArchive), {recursive: true});
  fs.writeFileSync(stdArchive, 'fixture\n');
  const soDir = path.join(root, 'so');
  fs.mkdirSync(soDir, {recursive: true});
  execFileSync('gcc', ['-shared', '-fPIC', '-x', 'c', '-o', path.join(soDir, 'libcangjie-runtime.so'), '-'], {
    input: 'int cjcj_gate_fixture;\n',
  });
  return {sdk, soDir};
}

function publishOverlay(buildEnv, fixture, root) {
  return {
    ...buildEnv,
    GCV2_RUNTIME_LIB_DIR: fixture.soDir,
    GCV2_RUNTIME_OUTPUT_ROOT: path.join(root, 'output'),
    MRT_TESTABLE_INTERNALS: '0',
    MRT_GC_UNIT_OHOS_HOST: '0',
    GC_UNIT_GATE_CONTRACT_SELFTEST: '1',
    GC_UNIT_OUT: path.join(root, 'unit-out'),
    GC_UNIT_GATE_STATUS: path.join(root, 'gc_unit_gate.status'),
    GC_UNIT_TIMEOUT: '20',
  };
}

function runGate(gate, env) {
  return spawnSync('bash', [gate], {env, encoding: 'utf8'});
}

test('patched runtime build.py inherits GC_UNIT_GATE_LANGUAGE_TESTS=defer', () => {
  const source = fs.readFileSync(PRODUCT_SOURCE, 'utf8');
  assert.match(source, /env: patchedRuntimeBuildEnv\(\)/);
  assert.match(source, /python3 build\.py build --target native --build-type release/);

  const base = {
    PATH: process.env.PATH,
    HOME: process.env.HOME || '/root',
    CANGJIE_HOME: '/ci/sdk',
    RUNTIME_VERSION: 'fixture',
  };
  assert.equal(base.GC_UNIT_GATE_LANGUAGE_TESTS, undefined);
  assert.equal(base.GC_UNIT_CJC_RUNTIME_LIB_DIR, undefined);

  const control = spawnSync('python3', ['-c', 'import os; print(os.environ.get("GC_UNIT_GATE_LANGUAGE_TESTS", "unset"))'], {
    env: base,
    encoding: 'utf8',
  });
  assert.equal(control.status, 0);
  assert.equal(control.stdout.trim(), 'unset');

  const buildEnv = patchedRuntimeBuildEnv(base);
  assert.equal(buildEnv.CANGJIE_HOME, '/ci/sdk');
  assert.equal(buildEnv.GC_UNIT_CJC_RUNTIME_LIB_DIR, undefined);

  const child = spawnSync('python3', ['-c', 'import os; print(os.environ.get("GC_UNIT_GATE_LANGUAGE_TESTS", "unset"))'], {
    env: buildEnv,
    encoding: 'utf8',
  });
  assert.equal(child.status, 0);
  const observed = child.stdout.trim();
  console.log(`TARGET_ASSERT_EXECUTED language_tests=${observed}`);
  assert.equal(observed, 'defer');
});

test('deferred build env does not enter the compiler-host runtime check', (t) => {
  const gate = process.env.CANGJIE_RUNTIME_GATE;
  if (!gate) {
    t.skip('CANGJIE_RUNTIME_GATE unset');
    return;
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'patched-runtime-defer-'));
  try {
    const fixture = sdkFixture(root);
    const base = {
      PATH: process.env.PATH,
      HOME: process.env.HOME || '/root',
      CANGJIE_HOME: fixture.sdk,
    };
    const controlEnv = publishOverlay(base, fixture, path.join(root, 'control'));
    const control = runGate(gate, controlEnv);
    assert.equal(control.status, 2);
    assert.ok(control.stderr.includes(HOST_RUNTIME_FAIL));

    const productEnv = publishOverlay(patchedRuntimeBuildEnv(base), fixture, path.join(root, 'product'));
    const product = runGate(gate, productEnv);
    const hitLines = product.stderr.split('\n').filter(line => line === HOST_RUNTIME_FAIL);
    const hits = hitLines.length;
    console.log(`TARGET_ASSERT_EXECUTED host_runtime_message=${hits} gate_rc=${product.status} line=${JSON.stringify(hitLines[0] || '')}`);
    assert.equal(hits, 0);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
