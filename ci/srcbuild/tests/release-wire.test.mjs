import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {load as loadYaml} from '../../vendor/js-yaml/js-yaml.mjs';
import {allReleasePlatforms, allTargets, getTarget, getReleasePlatform, releasePlatformReadiness} from '../../../build/lib/targets.mjs';
import {planMatrix, crossStdArtifacts} from '../../release/platform-matrix.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const workflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');
const plan = planMatrix('all');
// Unknown cross tuples stay visible as blocked inputs but have no producer to
// wire. Source-blocked native rows still have packageDeclared and remain owed.
const declaredKeys = allReleasePlatforms().filter(key => releasePlatformReadiness(key).packageDeclared);
const nativeKeys = declaredKeys.filter(key => getReleasePlatform(key).archiveKey === getReleasePlatform(key).host);
const releaseWorkflow = async () => loadYaml(await workflow('release.yml'));
const jobsOf = release => Object.entries(release.jobs).map(([id, job]) => ({...job, id}));
const packageJobsOf = release => jobsOf(release)
  .filter(job => job.uses === './.github/workflows/build-release-package.yml');

const platforms = allTargets();

test('explicit runtime pair reaches every source, package and cross-runtime pin loader', async () => {
  const names = ['native_llvm_ref','native_runtime_ref','native_host_version'];
  for (const file of ['release.yml','release-matrix.yml','arm-soak.yml','srcbuild.yml']) {
    const parsed = loadYaml(await workflow(file));
    for (const job of Object.values(parsed.jobs)) {
      if (!/^\.\/\.github\/workflows\/(srcbuild|srcbuild-target|build-release-package|build-windows-runtime)\.yml$/.test(job.uses || '')) continue;
      for (const name of names) assert.equal(job.with[name], '${{ inputs.'+name+' }}', file+': '+name);
    }
  }
  for (const file of ['srcbuild-target.yml','build-release-package.yml','build-windows-runtime.yml']) {
    const parsed = loadYaml(await workflow(file));
    const loaders = Object.values(parsed.jobs).flatMap(job => job.steps || []).filter(step => step.run?.includes('ci/load_runtime_pin.mjs'));
    assert.ok(loaders.length, file);
    for (const step of loaders) for (const name of names)
      assert.equal(step.env['CJCJ_'+name.toUpperCase()], '${{ inputs.'+name+' }}', file+': '+name);
  }
});

test('srcbuild exposes reusable inputs, artifact uploads, and the runtime override chain', async () => {
  const sourceBuild = await workflow('srcbuild-target.yml');
  for (const contract of [
    'workflow_call:',
    'runtime_ref:',
    'CJCJ_RUNTIME_REF_OVERRIDE: ${{ inputs.runtime_ref }}',
    'run: npx --yes zx@8 ci/load_runtime_pin.mjs',
  ]) assert.ok(sourceBuild.includes(contract), contract);
  assert.match(sourceBuild, /name: final-std-\$\{\{ matrix.target \}\}/);
  assert.match(sourceBuild, /name: final-std-windows-x64/);
  assert.doesNotMatch(sourceBuild, /final_(std|compiler)_/);
});

test('release connects each platform row to its same-platform final std', async () => {
  const release = await releaseWorkflow();
  assert.ok(jobsOf(release).some(job => job.uses === './.github/workflows/srcbuild.yml'));
  assert.ok(jobsOf(release).some(job => job.with?.runtime_ref === '${{ inputs.runtime_ref }}'));
  // The pairing, not the row that used to carry it. Phase control replaced the
  // matrix with one job per phase, so platform and std_artifact now sit on
  // separate lines of the same with: block; a line-shaped check reads a correct
  // wiring as missing.
  const packageJobs = packageJobsOf(release)
    .filter(job => nativeKeys.includes(job.with?.release_key));
  assert.equal(packageJobs.length, platforms.length,
    `expected one package job per platform, found ${packageJobs.length}`);
  for (const platform of platforms) {
    const job = packageJobs.find(entry => entry.with?.platform === platform);
    assert.ok(job, `no package job declares platform: ${platform}`);
    assert.equal(job.with?.std_artifact, platform==='windows-x64'?'final-std-native-windows-x64':`final-std-${platform}`,
      `the ${platform} package job does not ask for final-std-${platform}`);
  }
  assert.deepEqual(packageJobsOf(release).map(job => job.with?.release_key).sort(),
    [...declaredKeys].sort(),
    'release package key symmetric difference');
  assert.ok(jobsOf(release).some(job => job.steps?.some(step => step.with?.pattern === 'pkg-*')));
});

test('release cross packages depend on their native phase and cross producer with same-host std', async () => {
  const release = await releaseWorkflow();
  const packages = packageJobsOf(release);
  const cross = packages.filter(job => !nativeKeys.includes(job.with?.release_key));
  const rows = declaredKeys.filter(key => !nativeKeys.includes(key)).map(key => {
    const r = releasePlatformReadiness(key);
    return {release_key: key, platform: r.host, std_artifact: r.host==='windows-x64'?'final-std-native-windows-x64':`final-std-${r.host}`, cross_std_artifacts: JSON.stringify(crossStdArtifacts(r))};
  });
  assert.deepEqual(cross.map(job => job.with?.release_key).sort(), rows.map(row => row.release_key).sort(),
    'every non-native package must have an explicit cross contract');
  const sources = jobsOf(release).filter(job => job.uses === './.github/workflows/srcbuild.yml');
  const jobId = job => job.id;
  for (const row of rows) {
    const {release_key: key, platform: host} = row;
    const job = cross.find(entry => entry.with?.release_key === key);
    assert.equal(job.with?.platform, host, `${key}: package host`);
    assert.equal(job.with?.std_artifact, row.std_artifact, `${key}: same-host final std`);
    const native = packages.find(entry => nativeKeys.includes(entry.with?.release_key) && entry.with?.platform === host);
    assert.ok(native, `${key}: native package dependency`);
    const producerJobs = Object.values(releasePlatformReadiness(key).crossStd).map(target => {
      const producer = sources.find(entry => entry.with?.targets === target);
      assert.ok(producer, `${key}: cross std source ${target}`);
      return jobId(producer);
    });
    assert.deepEqual([...job.needs].sort(),
      [...new Set([jobId(native), ...producerJobs])].sort(), `${key}: native phase and cross producer dependencies`);
    const tuples = JSON.parse(job.with?.cross_std_artifacts);
    assert.deepEqual(tuples, JSON.parse(row.cross_std_artifacts), `${key}: cross std tuples`);
    const publish = release.jobs.publish;
    assert.ok(publish.needs.includes(jobId(job)),
      `${key}: publish waits for the cross package`);
    assert.ok(publish.if.includes(`needs.${jobId(job)}.result == 'success'`), `${key}: publish requires cross success`);
  }
  assert.ok(release.jobs.plan.steps.some(step => step.run === 'node ci/srcbuild/target-matrix.mjs --targets all --require-ready'));
  assert.equal(release.jobs['source-p1-linux-x64'].needs, 'plan');
  for (const family of ['android', 'ohos', 'ios']) {
    for (const target of new Set(declaredKeys.flatMap(key => Object.entries(releasePlatformReadiness(key).crossStd)
      .filter(([tuple]) => tuple.startsWith(family === 'ios' ? 'ios_' : `linux_${family}_`)).map(([, producer]) => producer)))) {
      const producer = sources.find(job => job.with?.targets === target);
      assert.ok(producer, `${target}: ${family} producer exists`);
      assert.equal(producer.with?.[`build_${family}`], true, `${target}: ${family} producer is enabled`);
    }
  }

});

test('component provenance, final std, and Python inputs are fail-closed in the native package consumer', async () => {
  const consumer = loadYaml(await workflow('build-release-package.yml'));
  const steps = consumer.jobs.package.steps;
  const download = steps.find(step => step.name === 'Download complete native SDK');
  assert.equal(download.with.name, 'cjcj-srcbuild-${{ inputs.platform }}-${{ inputs.version }}');
  assert.equal(download['continue-on-error'], undefined);
  const std = steps.find(step => step.name === 'Download same-platform source-built final std');
  assert.equal(std.with.name, '${{ inputs.std_artifact }}');
  assert.equal(std['continue-on-error'], undefined);
  const compose = steps.find(step => step.name === 'Consume and rearchive complete native SDK');
  assert.equal(compose.run, 'node ci/release/compose-package.mjs');
  assert.equal(compose.if, undefined, 'dry-run cannot skip installation consumption');
  const checks = await fs.readFile(path.join(root, 'ci/release/verify_native_release.mjs'), 'utf8');
  for (const gate of ['assertNativeReleaseInputs(options)', 'assertSdkCompilerRuntimeAbi({sdk, target})',
    'selectInstalledColourSdk(sdk,', 'scripts/verify_packaged_cjdb.mjs', 'ci/smoke/run_smoke.mjs', 'readInstalledStdxInputs({sdk,platform:target.spec.llvmPlatform,requireFull:true})'])
    assert.ok(checks.includes(gate), gate);
  const stdx = await fs.readFile(path.join(root, 'build/lib/installed-stdx-inputs.mjs'), 'utf8');
  for (const gate of ['STDX_BUILD_INPUTS', "fail('FULL_CONFIGURATION"])
    assert.ok(stdx.includes(gate), gate);
  assert.doesNotMatch(await workflow('build-release-package.yml'), /setup_sdk|install_cjpm_artifact|install_hle_artifact|prepare_base_sdk|build_cjcj/);
});

test('private toolchain setup retains base SDK provenance and content-addressed bytes', async () => {
  const [setup, platformSetup, provenance] = await Promise.all([
    fs.readFile(path.join(root, 'ci/setup_sdk.mjs'), 'utf8'),
    fs.readFile(path.join(root, 'ci/platform_matrix/build_cjcj.mjs'), 'utf8'),
    fs.readFile(path.join(root, 'build/lib/release-component-provenance.mjs'), 'utf8'),
  ]);
  for (const source of [setup, platformSetup]) {
    assert.ok(source.includes('persistBaseSdkProvenance({'));
    assert.ok(source.includes('toolchainDir: cangjieHome'));
  }
  assert.ok(provenance.includes("path.join(root, '.cjv')"));
  assert.ok(provenance.includes("path.join('archives', 'sha256', value.artifact.sha256, expected.archive)"));
  assert.ok(provenance.includes('await fs.rename(temporary, destination)'));
});

test('release package runs the packaged std checker as a bounded fail-closed step', async () => {
  const consumer = await workflow('build-release-package.yml');
  const compose = await fs.readFile(path.join(root, 'ci/release/compose-package.mjs'), 'utf8');
  const checks = await fs.readFile(path.join(root, 'ci/release/verify_native_release.mjs'), 'utf8');
  assert.ok(consumer.includes('run: node ci/release/compose-package.mjs'));
  assert.ok(compose.includes('await verifyNativeRelease(options, env)'));
  assert.ok(compose.includes('await archiveInstall('));
  assert.ok(compose.includes("new URL('./verify_native_release.mjs'"));
  assert.ok(checks.includes('scripts/check_packaged_std.mjs'));
  assert.ok(checks.includes('signal: AbortSignal.timeout(120000)'));
  for (const argument of ['--sdk', '--std', '--platform']) assert.ok(checks.includes(argument));
});

test('all package cells consume the produced cjpm bytes inside the native SDK', async () => {
  const sourceBuild = await workflow('srcbuild-target.yml');
  const consumer = await workflow('build-release-package.yml');
  const checks = await fs.readFile(path.join(root, 'ci/release/native-release-inputs.mjs'), 'utf8');
  assert.ok(sourceBuild.includes('ci/srcbuild/steps/package-install.mjs'));
  assert.ok(consumer.includes('name: cjcj-srcbuild-${{ inputs.platform }}-${{ inputs.version }}'));
  assert.ok(checks.includes("['cjpm', ...sourceOwnedTools("));
  for (const check of ['TOOLS-INPUTS.json', 'produced?.sha256', 'produced.producer?.source', 'source.commit', 'produced.producer?.build', "toolSdkInputs(tool).includes('runtime') && runtimeInputs.stage?.runtimeCommit !== runtimeRef", 'await toolReadiness(sdk)', 'NATIVE_RELEASE_TOOL_DEPENDENCIES', 'rows[0].source'])
    assert.ok(checks.includes(check), check);
});

test('release has one LLVM producer per tuple', async () => {
  const [release, tuples] = await Promise.all([releaseWorkflow(), workflow('platform-tuples.yml')]);
  assert.ok(!jobsOf(release).some(job => job.with?.platform_set === 'windows-only'));
  const native = loadYaml(await workflow('srcbuild-target.yml'));
  assert.equal(native.jobs['fixed-llvm'].if, "inputs.native_runtime_artifact == ''");
  assert.equal(native.jobs['native-cjdb'].if, "inputs.native_build_inputs_artifact != ''");
  assert.ok(native.jobs['native-cjdb'].steps.some(step => step.run?.includes('native-cjdb-job.mjs build')));
  assert.ok(jobsOf(release).some(job => job.uses === './.github/workflows/srcbuild.yml' && job.with?.targets === 'windows-x64'));
  assert.ok(!jobsOf(release).some(job => job.with?.platform_set === 'darwin-windows'));
  assert.ok(!jobsOf(release).some(job => job.uses === './.github/workflows/build-fixed-llc.yml'));
  assert.equal(loadYaml(tuples).jobs['build-tuple'].uses, './.github/workflows/build-llvm-tools.yml');
  assert.equal(loadYaml(tuples).jobs['build-tuple'].with.platform_set, "${{ inputs.platform_set || 'all' }}");

  const artifacts = [
    ...platforms.map(platform => `fixed-llvm-tools-${getTarget(platform).spec.llvmPlatform}`),
    ...platforms.map(platform => `final-std-${platform}`),
    ...platforms.filter(platform => !getTarget(platform).spec.crossCompile).map(platform => `source-cjpm-${platform}`),
    ...platforms.map(platform => `pkg-${platform}`),
    ...platforms.filter(platform => getTarget(platform).spec.crossCompile).flatMap(platform =>
      [`runtime-install-${getTarget(platform).spec.llvmPlatform}`, `patched-cjpm-${getTarget(platform).spec.llvmPlatform}`]),
  ];
  assert.equal(new Set(artifacts).size, artifacts.length);
});

test('release packages select the installed final compiler in each native phase', async () => {
  const release = await releaseWorkflow();
  const jobs = packageJobsOf(release);
  for (const platform of platforms) assert.ok(jobs.some(job => job.with?.platform === platform), platform);
  const checks = await fs.readFile(path.join(root, 'ci/release/native-release-inputs.mjs'), 'utf8');
  for (const gate of ['metadata.compilerCommit !== sourceSha', 'metadata.runtimeCommit !== runtimeRef',
    'installedStageOutput(sdk, metadata.phase)', 'compiler.compilerSha256 !== output.lineage.compilerSha256'])
    assert.ok(checks.includes(gate), gate);
  assert.ok((await workflow('build-release-package.yml')).includes('CJCJ_RELEASE_SOURCE_SHA: ${{ github.sha }}'));
});

// The release package's tool set is the one the source matrix builds. Three
// places have to agree: the srcbuild cell that stages each artifact, the release
// cell that downloads and installs it, and the declaration the manifest is
// written from. When they disagree the package silently keeps the official bytes
// while the manifest describes them as ours, which is the failure this pairing
// exists to catch. Each side is read from its own artifact rather than restated
// here, so adding a tool to one list and forgetting another fails this test.
test('every source-built tool is staged, installed, and declared by the same list', async () => {
  const {sourceOwnedTools} = await import('../../../build/lib/release-component-provenance.mjs');
  const {sourceToolOutputs} = await import('../../../build/srcbuild/install-tools.mjs');
  const {buildConfig} = await import('../../../build/lib/config.mjs');
  const {releaseSelection} = await import('../../release/native-release-inputs.mjs');
  const source = await workflow('srcbuild-target.yml');
  const consumer = await workflow('build-release-package.yml');
  for (const platform of platforms) {
    const config = buildConfig({targetKey:platform});
    const produced = sourceToolOutputs(config).map(row => row.name.replace(/\.exe$/, '')).sort();
    const declared = ['cjpm', ...sourceOwnedTools(platform === 'windows-x64')].sort();
    assert.deepEqual(produced, declared, platform + ': actual installer/declaration');
    assert.deepEqual(releaseSelection(platform).tools.sort(), produced, platform + ': complete consumer');
    for (const tool of produced) {
      const dedicated = tool === 'cjpm' || tool === 'hle';
      assert.ok(source.includes(dedicated ? 'node ci/release/prepare_' + tool + '_artifact.mjs' : '--tool ' + tool + ' '), tool);
    }
  }
  assert.ok(source.includes('ci/srcbuild/steps/package-install.mjs'));
  assert.ok(consumer.includes('name: cjcj-srcbuild-${{ inputs.platform }}-${{ inputs.version }}'));
  assert.doesNotMatch(consumer, /install_(cjpm|hle|tools)_artifact/);
});

// Where each source-built tool lands is a property of that tool's own build.py,
// not something a workflow may choose. The path appears twice -- the staging step
// names the binary to publish, and the cross-tool step builds and checks it -- so
// a hand-written directory in either place names something no build produces, and
// nothing notices until the artifact is missing at release time.
test('the cross-tool step and the source installation name the same tool paths', async () => {
  const source = await workflow('srcbuild-target.yml');
  const installTools = await fs.readFile(path.join(root, 'build/srcbuild/tool-layout.mjs'), 'utf8');
  // The native installation's own relative paths, read from the producer module.
  const declared = [...installTools.matchAll(/\['([A-Za-z0-9-]+)','([^']+)'\]/g)]
    .map(([, tool, relative]) => [tool, relative])
    .filter(([tool]) => tool !== 'cjpm' && tool !== 'LSPServer' && tool !== 'cjfmt');
  assert.ok(declared.length > 0, 'the source installation must declare its tool paths');
  // Scope the search to the cross-build region of the workflow. The native
  // staging steps earlier in the same file name the same directories, so a
  // whole-file search would let a wrong cross path pass on the native line.
  const crossStart = source.indexOf('- name: Cross-build Windows SDK tools from source');
  const crossEnd = source.indexOf('- name: Upload Windows source-built std install root');
  assert.ok(crossStart >= 0 && crossEnd > crossStart, 'the cross tool-build region must be locatable');
  const crossRegion = source.slice(crossStart, crossEnd);
  for (const [tool, relative] of [['cjfmt', 'packages/cjfmt/dist/bin/cjfmt'],
    ['hle', 'packages/hle/target/bin/main'],
    ['LSPServer', 'packages/lsp/dist/bin/cangjie-lsp'],
    ...['cjlint','cjprof','cjcompat','cjhead'].map(name=>[name,name+'/dist/bin/'+name])]) {
    assert.ok(installTools.includes(relative), `${tool}: the source installation must name ${relative}`);
    const directory = path.posix.dirname(relative);
    const staged = crossRegion.match(new RegExp(`cangjie_tools/${directory}/[A-Za-z0-9_.-]+`));
    assert.ok(staged, `${tool}: the cross cell must stage its binary from ${directory}, not another directory`);
    assert.ok(staged[0].endsWith('.exe'),
      `${tool}: the cross binary is the target's executable, got ${staged[0]}`);
  }
});
