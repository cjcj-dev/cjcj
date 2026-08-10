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
const readWorkflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');

const uncommented = text => text.split('\n').filter(line => !/^\s*#/.test(line)).join('\n');

// One entry per reusable-workflow *call*, not per distinct file: two jobs calling
// one producer upload its artifacts twice, so the repeat has to survive here.
async function invokedWorkflows(entry, stack = []) {
  assert.ok(!stack.includes(entry), `reusable workflow cycle: ${[...stack, entry].join(' -> ')}`);
  const text = uncommented(await readWorkflow(entry));
  const invocations = [entry];
  for (const [, called] of text.matchAll(/uses:\s*\.\/\.github\/workflows\/([\w.-]+\.yml)/g)) {
    invocations.push(...await invokedWorkflows(called, [...stack, entry]));
  }
  return invocations;
}

// The values a ${{ matrix.KEY }} placeholder can take inside one workflow file.
const matrixValues = (text, key) =>
  [...text.matchAll(new RegExp(String.raw`^\s*(?:- )?${key}: (\S+)$`, 'gm'))].map(([, value]) => value);

function expandMatrix(name, text) {
  const placeholder = name.match(/\$\{\{\s*matrix\.(\w+)\s*\}\}/);
  if (!placeholder) return [name];
  const values = matrixValues(text, placeholder[1]);
  assert.ok(values.length > 0, `no matrix values for ${placeholder[1]} in ${name}`);
  return values.flatMap(value => expandMatrix(name.replace(placeholder[0], value), text));
}

// Artifact names one workflow file uploads, with its own matrix fanout expanded.
function uploadedArtifacts(text) {
  const lines = text.split('\n');
  const names = [];
  for (const [index, line] of lines.entries()) {
    if (!line.includes('uses: actions/upload-artifact@')) continue;
    const nameLine = lines.slice(index + 1, index + 10).find(entry => /^\s+name: /.test(entry));
    assert.ok(nameLine, `upload step at line ${index + 1} declares no artifact name`);
    names.push(...expandMatrix(nameLine.replace(/^\s+name: /, '').trim(), text));
  }
  return names;
}

// [artifact, producing workflow] for everything a dispatch entry point uploads.
async function runArtifacts(entry) {
  const produced = [];
  for (const name of await invokedWorkflows(entry)) {
    const text = uncommented(await readWorkflow(name));
    for (const artifact of uploadedArtifacts(text)) produced.push([artifact, name]);
  }
  return produced;
}

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

test('arm soak produces every artifact its package job downloads, each exactly once', async () => {
  const armSoak = await readWorkflow('arm-soak.yml');
  const consumer = await readWorkflow('build-release-package.yml');

  // build-release-package.yml refuses any std artifact that is not same-platform,
  // so linux-aarch64 fixes which artifact this run has to produce.
  assert.ok(consumer.includes('EXPECTED_STD_ARTIFACT: final-std-${{ inputs.platform }}'));
  assert.ok(armSoak.includes('platform: linux-aarch64'));
  assert.ok(armSoak.includes('default: final-std-linux-aarch64'));
  assert.ok(armSoak.includes('std_artifact: ${{ inputs.std_artifact }}'));

  const produced = await runArtifacts('arm-soak.yml');

  // Exactly one producer, and it is the source build.
  assert.deepEqual(
    produced.filter(([artifact]) => artifact === 'final-std-linux-aarch64').map(([, source]) => source),
    ['srcbuild.yml'],
  );

  // The other two fail-closed downloads in the same package job.
  for (const artifact of ['source-cjpm-linux-aarch64', 'fixed-llvm-tools-linux_aarch64']) {
    assert.equal(produced.filter(([entry]) => entry === artifact).length, 1, artifact);
  }

  // upload-artifact rejects a name already uploaded in the same run, so two callers
  // of one producer workflow break the run rather than merging. Checked before the
  // wiring strings below so a second caller cannot be masked by an earlier failure.
  const names = produced.map(([artifact]) => artifact);
  assert.deepEqual(names.filter((artifact, index) => names.indexOf(artifact) !== index), []);

  // The package job waits for that producer before it downloads.
  assert.ok(armSoak.includes('uses: ./.github/workflows/srcbuild.yml'));
  assert.ok(armSoak.includes('needs: source-final-std'));
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
