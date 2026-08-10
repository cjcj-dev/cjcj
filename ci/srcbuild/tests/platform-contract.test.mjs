import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../../../build/lib/config.mjs';
import {baseEnv} from '../../../build/srcbuild/stages/common.mjs';
import {assembleCjcLinkOption} from '../../platform_matrix/link_option.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';

const root = path.resolve(import.meta.dirname, '../../..');

test('source-build workflow connects every native runner to its LLVM and std artifact', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const fixed = await fs.readFile(path.join(root, '.github/workflows/build-fixed-llc.yml'), 'utf8');
  const cells = [
    ['linux-aarch64', 'ubuntu-24.04-arm', 'linux_aarch64'],
    ['darwin-arm64', 'macos-15', 'darwin_aarch64'],
    ['darwin-x64', 'macos-15-intel', 'darwin_x86_64'],
    ['linux-x64', 'ubuntu-22.04', 'linux_x86_64'],
  ];
  for (const [target, runner, llvmPlatform] of cells) {
    assert.ok(workflow.includes(`- target: ${target}\n            runner: ${runner}\n            llvm_platform: ${llvmPlatform}`));
    assert.ok(fixed.includes(`runner: ${runner}\n            platform: ${llvmPlatform}`));
  }
  for (const edge of [
    'needs: fixed-llvm',
    'name: fixed-llvm-tools-${{ matrix.llvm_platform }}',
    'name: final-std-${{ matrix.target }}',
    'path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-stage2',
  ]) assert.ok(workflow.includes(edge), edge);

  const order = [
    'Build compiler oracle', 'Build runtime from source', 'Build stdlib from source',
    'Build stage 1 compiler', 'Build stage 2 compiler', 'Build stage 3 compiler and final std',
    'Upload final source-built std install root', 'Compose self-hosted SDK', 'Verify self-hosted SDK',
  ].map(name => workflow.indexOf(`name: ${name}`));
  assert.ok(order.every(index => index >= 0));
  assert.deepEqual([...order].sort((a, b) => a - b), order);

  for (const payload of ['llc.gz', 'opt.gz', 'llvm-tools.manifest', 'cjselfhost_llvmshim.o']) {
    assert.ok(fixed.includes(payload), payload);
  }
});

test('source-build cache makes durable GHA writes primary and retains write diagnostics', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  assert.ok(workflow.includes('SCCACHE_MULTILEVEL_CHAIN: "gha"'));
  assert.ok(!workflow.includes('SCCACHE_MULTILEVEL_CHAIN: "disk,gha"'));
  assert.ok(workflow.includes('SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY: "l0"'));
  assert.ok(workflow.includes('SCCACHE_ERROR_LOG=$RUNNER_TEMP/sccache-error.log'));
  assert.ok(workflow.includes('name: Capture sccache diagnostics'));
  assert.ok(workflow.includes('name: sccache-diagnostics-${{ matrix.target }}-${{ github.run_attempt }}'));
  assert.ok(workflow.includes('retention-days: 1'));
});

test('Windows MinGW product cache has one bounded rate-limit retry', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/build-windows-runtime.yml'), 'utf8');
  const start = workflow.indexOf('- name: Restore official MinGW toolchain');
  const end = workflow.indexOf('- name: Cross-build pinned Windows runtime');
  assert.ok(start >= 0 && end > start);
  const cacheBlock = workflow.slice(start, end);
  assert.equal(cacheBlock.match(/uses: actions\/cache\/save@v6/g)?.length, 2);
  assert.equal(cacheBlock.match(/lookup-only: true/g)?.length, 2);
  assert.equal(cacheBlock.match(/run: sleep 5/g)?.length, 1);
  assert.ok(cacheBlock.includes("steps.mingw-cache-probe.outputs.cache-hit != 'true'"));
  assert.ok(cacheBlock.includes('still absent after one bounded retry'));
});

test('native build environments use configured architecture, OpenSSL, and loader', () => {
  const oldDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  try {
    for (const targetKey of ['linux-aarch64', 'darwin-arm64', 'darwin-x64', 'linux-x64']) {
      const config = buildConfig({targetKey});
      const env = baseEnv(config);
      assert.equal(env.ARCH, config.target.spec.arch);
      assert.equal(env.OPENSSL_PATH, config.target.spec.opensslLibDir);
      assert.ok(env.PATH.startsWith(config.target.spec.llvmBinDir));
      assert.ok(env[config.target.spec.loaderEnv].includes(config.target.spec.opensslLibDir));
      assert.equal('LDFLAGS' in env, config.target.spec.os === 'linux');
    }
  } finally {
    if (oldDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = oldDryRun;
  }
});

test('Darwin selfhost link uses the source SDK dylib and libc++', () => {
  const link = assembleCjcLinkOption('darwin', '/source-sdk', 'linux-only');
  assert.match(link, /\/source-sdk\/third_party\/llvm\/lib\/libLLVM\.dylib/);
  assert.match(link, /-lc\+\+/);
  assert.doesNotMatch(link, /libLLVM-15\.so|-lstdc\+\+/);
});

test('Windows final std is cross-built by the stage2 Linux host compiler', async () => {
  const workflow = await fs.readFile(path.join(root, '.github/workflows/srcbuild.yml'), 'utf8');
  const producer = await fs.readFile(path.join(root, 'ci/srcbuild/steps/build-windows-final-std.mjs'), 'utf8');
  for (const edge of [
    "if: matrix.target == 'linux-x64'",
    'run: npx --yes zx@8 ci/srcbuild/steps/build-windows-final-std.mjs',
    'name: final-std-windows-x64',
    'path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-windows-stage2',
  ]) assert.ok(workflow.includes(edge), edge);
  for (const contract of [
    "getTarget('windows-x64')",
    "path.join(sdk, 'bin', 'cjcj-stage2')",
    '--target windows-x86_64',
    '--target-sysroot ${mingwRoot}/',
    '--target-toolchain ${mingwBin}',
  ]) assert.ok(producer.includes(contract), contract);
});

test('final std install roots satisfy package_sdk layout (a) on every release target', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'srcbuild-final-std-'));
  try {
    for (const targetKey of ['linux-aarch64', 'darwin-arm64', 'darwin-x64', 'linux-x64', 'windows-x64']) {
      const target = buildConfig({targetKey}).target;
      const install = path.join(fixture, targetKey);
      const modulesTop = path.join(install, 'modules', target.spec.runtimeTuple);
      const modulesStd = path.join(modulesTop, 'std');
      const staticDir = path.join(install, 'lib', target.spec.runtimeTuple);
      const sharedDir = path.join(install, 'runtime', 'lib', target.spec.runtimeTuple);
      await Promise.all([modulesStd, staticDir, sharedDir].map(directory => fs.mkdir(directory, {recursive: true})));
      await Promise.all([
        fs.writeFile(path.join(modulesStd, 'std.core.cjo'), ''),
        fs.writeFile(path.join(staticDir, 'libcangjie-std-core.a'), ''),
        fs.writeFile(path.join(staticDir, 'libcangjie-std-coreFFI.a'), ''),
        fs.writeFile(path.join(sharedDir, `libcangjie-std-core${target.spec.sharedLibrarySuffix}`), ''),
        fs.writeFile(path.join(install, 'PROVENANCE.txt'), 'fixture\n'),
      ]);
      if (target.spec.expectedStdArtifacts.bitcode !== 0) {
        await fs.writeFile(path.join(modulesStd, 'libstd.core.bc'), '');
      }
      await assertFinalStd(install, target, {dryRun: true});
    }

    const consumer = await fs.readFile(path.join(root, 'scripts/package_sdk.mjs'), 'utf8');
    assert.ok(consumer.includes("modulesStd: path.join(root, 'modules', runtimeDir, 'std')"));
    assert.ok(consumer.includes("libDir: path.join(root, 'lib', runtimeDir)"));
  } finally {
    await fs.rm(fixture, {recursive: true, force: true});
  }
});
