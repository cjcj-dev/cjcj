#!/usr/bin/env zx
// Runtime build.py:283-328 and stdlib/build.py:48-50,97-102 define the
// three upstream iOS targets. Build each in its own source/build directory.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectBuildJobs} from '../../../../../ci/build-resources.mjs';
import {assertBootstrapCompiler} from '../lib/bootstrap-handoff.mjs';
import {installedStageOutput} from '../lib/installed-stage-output.mjs';
import {verifyStdBuildInputs} from '../../../../../ci/bootstrap/stdlib-build.mjs';
import {writeStdProvenance} from '../../../../lib/provenance.mjs';
import {buildIosRuntime, iosTargets} from '../lib/ios-runtime.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';

$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
const expectedRef = required('CJCJ_NATIVE_RUNTIME_REF');
const version = required('SOURCE_SDK_VERSION');
if (process.platform !== 'darwin' || process.arch !== 'arm64') throw new Error('iOS source build requires darwin/arm64');
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be filesystem root');
const probe = probeRequirement('xcode-ios');
if (!probe.present) throw new Error(probe.detail);
const sdk = path.join(workspace, 'native-bootstrap', 'sdk-stage2');
const originalCompiler = await installedStageOutput(sdk, 'stage2');
if (!/^[a-f0-9]{40}$/.test(expectedRef) || expectedRef !== originalCompiler.lineage.runtimeCommit) throw new Error('runtime source mismatch with stage2 compiler');
const compiler = originalCompiler.product;
const compilerKind = (await $({stdio: 'pipe'})`file -b ${compiler}`).stdout.trim();
if (!compilerKind.includes('Mach-O') || !compilerKind.includes('arm64')) throw new Error(`wrong host compiler: ${compilerKind}`);
const target = iosTargets.find(row => row.tuple === required('CROSS_STD_TUPLE'));
if (!target) throw new Error('unsupported iOS cross std tuple');
const output = path.join(workspace, 'software', target.artifact);
await fs.rm(output, {recursive: true, force: true});
await fs.mkdir(output, {recursive: true});
const jobs = await selectBuildJobs(process.env.STD_BUILD_JOBS);
const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
{
  const started = Date.now();
  // Each source-ios matrix cell builds runtime and std from one clean, pinned
  // checkout. Only the installed stage2 SDK is consumed from the handoff.
  const source = await fs.mkdtemp(path.join(workspace, target.target + '-'));
  await $`git init --quiet ${source}`;
  await $`git -C ${source} fetch --quiet --depth=1 ${required('RUNTIME_SRC_URL')} ${expectedRef}`;
  await $`git -C ${source} checkout --quiet --detach FETCH_HEAD`;
  const actualRef = (await $({stdio: 'pipe'})`git -C ${source} rev-parse HEAD`).stdout.trim();
  if (actualRef !== expectedRef) throw new Error(`runtime source mismatch: ${actualRef} != ${expectedRef}`);
  const sysroot = (await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --show-sdk-path`).stdout.trim();
  const clang = (await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --find clang`).stdout.trim();
  const toolBin = path.dirname(clang);
  const stdlib = path.join(source, 'stdlib');
  const install = output;
  const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_VERSION: version,
    SDKROOT: sysroot, PATH: [path.join(sdk, 'bin'), toolBin, process.env.PATH].join(path.delimiter)};
  const assertCompiler = async () => {
    const command = (await $({env, stdio: 'pipe'})`command -v cjc`).stdout.trim();
    await assertBootstrapCompiler({sdk, command, producer: originalCompiler.product, producerSha256: originalCompiler.lineage.compilerSha256});
  };
  await assertCompiler();
  await verifyStdBuildInputs(sdk, originalCompiler.lineage.platform);
  const runtimeOutput = await buildIosRuntime({source, target, sysroot, toolBin, version, runtimeRef: actualRef, env});
  await $({cwd: stdlib, env})`python3 build.py build -t release -j ${jobs} --target ${target.target} --target-lib=${path.join(runtimeOutput, 'lib', target.tuple)} --target-lib=${path.join(runtimeOutput, 'runtime', 'lib', target.tuple)} --target-sysroot ${sysroot} --target-toolchain ${toolBin}`;
  await $({cwd: stdlib, env})`python3 build.py install --prefix ${install}`;
  await assertCompiler();
  await writeStdProvenance({sourceDir: stdlib, sourceRoot: source, sourceRevision: actualRef, installPrefix: install, compiler, buildSdk: sdk,
    note: `stage2 Darwin host cjc cross-built ${target.tuple}; runtime ${actualRef}; SDK ${sysroot}`});
  // runtime/CMakeLists.txt installs tuple directories, not a flat lib/ tree.
  // Keep runtime provenance separate from final std as in the Android producer.
  const runtimeArtifact = path.join(install, 'cross-runtime');
  await fs.cp(runtimeOutput, runtimeArtifact, {recursive: true});
  const runtimeDir = path.join(runtimeArtifact, 'runtime', 'lib', target.tuple);
  const records = [];
  for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
    const destination = path.join(runtimeDir, name);
    const kind = (await $({stdio: 'pipe'})`file -b ${destination}`).stdout.trim();
    if (!kind.includes('Mach-O') || !kind.includes(target.arch)) throw new Error(`${target.tuple}/${name}: ${kind}`);
    records.push({file: path.relative(install, destination), sha256: await sha256(destination), kind});
  }
  const core = path.join(install, 'lib', target.tuple, 'libcangjie-std-core.a');
  const kind = (await $({stdio: 'pipe'})`file -b ${core}`).stdout.trim();
  const arches = (await $({stdio: 'pipe'})`lipo -archs ${core}`).stdout.trim();
  if (arches !== target.arch) throw new Error(`${target.tuple} core architectures: ${arches}`);
  records.push({file: path.relative(install, core), sha256: await sha256(core), kind, arches});
  await fs.access(path.join(install, 'modules', target.tuple, 'std', 'std.core.cjo'));
  await fs.writeFile(path.join(install, 'ios-build.json'), JSON.stringify({target, runtimeRef: actualRef,
    compilerSha256: await sha256(compiler), sysroot, records, wall: (Date.now() - started) / 1000}, null, 2) + '\n');
  console.log(`IOS_FINAL_STD_BUILT tuple=${target.tuple} records=${JSON.stringify(records)}`);
}
