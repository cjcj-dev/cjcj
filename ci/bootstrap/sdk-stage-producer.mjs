// The existing shim/trimpath/cjpm recipes, fed only by a complete input SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {assembleSdk} from './toolchain-sdk.mjs';
import {canonical, readJson, fileDigest, atomicJson, reject, PLATFORMS, sourceIdentity, registeredSourceIdentity} from './sdk-manifest.mjs';
import {prepareTrimpath} from '../release/trimpath.mjs';
import {resolveProductBinary} from '../srcbuild/lib/product-binary.mjs';
import {stdIdentity} from '../srcbuild/lib/final-compiler.mjs';

const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
// This is the existing bootstrap runner binding, now confined to the private
// build SDK. Published SDK payloads keep the ordinary compiler alias contract.
const runnerText = (sdk, real, ld) => `#!/usr/bin/env bash\nexport CANGJIE_HOME=${quote(sdk)}\nexport LD_LIBRARY_PATH=${quote(ld)}\nexec ${quote(real)} "$@"\n`;

export async function buildStageCompiler(request, run) {
  const {component, source, directory, dependencies, plan} = request;
  const options = component.config.options;
  const selected = new Set(options.sdkComponents);
  const closure = new Set();
  const include = id => {
    if (closure.has(id)) return;
    const output = dependencies[id];
    if (!output) reject('PRODUCER_DEPENDENCY', component.id, `input SDK dependency ${id} is absent`);
    closure.add(id); output.component.dependencies.forEach(include);
  };
  options.sdkComponents.forEach(include);
  const components = [...closure].map(id => {
    const original = plan.components.find(row => row.id === id), output = dependencies[id];
    const {inputOnly, ...produced} = structuredClone(original);
    if (!selected.has(id)) produced.inputOnly = true;
    produced.producer = {...produced.producer, receipt: output.directory, receiptSha256: output.receiptSha256,
      originBuildRoot: original.producer.originBuildRoot || plan.buildRoot};
    return produced;
  });
  const inputPlan = {...plan, stage: options.stage === 'stage2' ? 'stage1' : 'stage2', components};
  const sdk = path.join(directory, 'build', 'sdk');
  await assembleSdk(inputPlan, sdk);
  const manifest = await readJson(path.join(sdk, 'SDK.manifest.json'));
  const parent = manifest.files['bin/cjcj-stage1'];
  const std = manifest.files[`lib/${PLATFORMS[plan.platform][2]}/libcangjie-std-core.a`];
  if (!parent || !std) reject('PRODUCER_DEPENDENCY', component.id, 'compiler and full std must be installed from the selected input plan');
  const tuple = PLATFORMS[plan.platform][2];
  const systemLib = plan.platform === 'linux_aarch64' ? '/usr/lib/aarch64-linux-gnu' : '/usr/lib/x86_64-linux-gnu';
  const targetLd = [path.join(sdk, 'runtime/lib', tuple), path.join(sdk, 'lib', tuple),
    path.join(sdk, 'third_party/llvm/lib'), path.join(sdk, 'tools/lib'), systemLib].join(':');
  const seed = components.find(row => selected.has(row.id) && row.source.kind === 'distribution' && row.roles.includes('official-host'));
  const hostSdk = dependencies[seed?.id]?.artifacts;
  if (!hostSdk) reject('PRODUCER_DEPENDENCY', component.id, 'explicit host tool producer required');
  const hostLd = [plan.verification.hostRuntimeDir, path.join(hostSdk, 'lib', tuple),
    path.join(hostSdk, 'third_party/llvm/lib'), path.join(hostSdk, 'tools/lib'), systemLib].join(':');
  const compilerLd = options.stage === 'stage3' ? targetLd
    : [plan.verification.hostRuntimeDir, path.join(sdk, 'third_party/llvm/lib'), path.join(hostSdk, 'tools/lib'), systemLib].join(':');
  const parentLockSha256 = await fileDigest(path.join(sdk, 'SDK.lock.json'));
  await fs.copyFile(path.join(hostSdk, 'tools/bin/cjpm'), path.join(sdk, 'tools/bin/cjpm-stage1'));
  await fs.chmod(path.join(sdk, 'tools/bin/cjpm-stage1'), 0o755);
  for (const [entry, real, ld] of [['bin/cjc', 'bin/cjcj-stage1', compilerLd], ['tools/bin/cjpm', 'tools/bin/cjpm-stage1', hostLd]]) {
    await fs.rm(path.join(sdk, entry), {force: true});
    await fs.writeFile(path.join(sdk, entry), runnerText(sdk, path.join(sdk, real), ld), {mode: 0o755});
  }
  if (await fileDigest(options.runtimePin.path) !== options.runtimePin.sha256) reject('VERIFICATION_INPUT', component.id, 'stage runtime pin changed');
  const tools = component.config.tools;
  const env = {...process.env, CANGJIE_HOME: sdk, LD_LIBRARY_PATH: targetLd,
    CJCJ_LLVM_SHIM_O: path.join(sdk, 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o'),
    CJCJ_COMMIT: component.source.commit, CC: tools.clang.path, CXX: tools['clang++'].path,
    CANGJIE_BUILD_JOBS: String(os.availableParallelism()), CMAKE_BUILD_PARALLEL_LEVEL: String(os.availableParallelism()),
    cjHeapSize: options.heap, PATH: `${sdk}/bin:${sdk}/tools/bin:${sdk}/third_party/llvm/bin:/usr/bin:/bin`};
  if (options.launcher) env.CMAKE_C_COMPILER_LAUNCHER = env.CMAKE_CXX_COMPILER_LAUNCHER = options.launcher;
  await run(['node', path.join(source, 'ci/check-codegen-runtime-layout.mjs'), path.join(directory, 'build/layout-sources'), options.runtimePin.path], {cwd: source, env});
  await run(['zx', path.join(source, 'runtime_shim/build_shim.mjs')], {cwd: source, env});
  const config = path.join(source, 'cjpm.toml'), before = await fs.readFile(config);
  await prepareTrimpath(source);
  const sourceChanges = before.equals(await fs.readFile(config)) ? {} : {'cjpm.toml': {sha256: await fileDigest(config), mode: (await fs.stat(config)).mode & 0o777}};
  // Expected transform bytes are captured before cjpm executes and checked
  // afterwards. A build cannot retrospectively bless other source changes.
  await atomicJson(path.join(directory, 'native-execution.json'), {sourceChanges, inputPlanSha256: manifest.planSha256, parentLockSha256});
  await run([path.join(sdk, 'tools/bin/cjpm'), 'build', '-j', String(os.availableParallelism())], {cwd: source, env});
  await registeredSourceIdentity(source, component.source, component.id, sourceChanges, tools.git.path);
  const product = await resolveProductBinary(path.join(source, 'target/release/bin'), options.stage);
  const artifacts = path.join(directory, 'artifacts'); await fs.mkdir(artifacts);
  await run(['python3', '-B', path.join(component.producer.repository, 'ci/bootstrap/compiler_identity.py'), artifacts, '--install', product]);
  const shim = {};
  for (const name of ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o']) {
    const input = path.join(source, 'runtime_shim', name), destination = path.join(artifacts, 'share/cjcj/runtime_shim', name);
    await fs.mkdir(path.dirname(destination), {recursive: true}); await fs.copyFile(input, destination);
    shim[name] = await fileDigest(destination);
  }
  const lineage = {stage: options.stage, tuple, compilerSha256: await fileDigest(product), parentSha256: parent.sha256,
    parentBuildId: parent.buildId, stdCoreSha256: std.sha256, stdBuildId: std.buildId,
    stdSha256: options.stage === 'stage3' ? await stdIdentity(std.artifacts) : undefined,
    runtimeSha256: manifest.files[`runtime/lib/${tuple}/libcangjie-runtime.so`].sha256,
    llvmManifestSha256: manifest.files['third_party/llvm/fixed-llc/llvm-tools.manifest'].sha256,
    shimSha256: shim, inputPlanSha256: manifest.planSha256, parentLockSha256};
  await atomicJson(path.join(artifacts, 'stage-compiler.json'), lineage);
  console.log(`STAGE_COMPILER_PRODUCED ${canonical(lineage).trim()}`);
  return sourceChanges;
}
