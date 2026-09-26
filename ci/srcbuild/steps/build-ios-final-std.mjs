#!/usr/bin/env zx
// Runtime build.py:283-328 and stdlib/build.py:48-50,97-102 define the
// three upstream iOS targets. Build each in its own source/build directory.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {assertBootstrapCompiler} from '../lib/bootstrap-handoff.mjs';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';

$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
const expectedRef = required('RUNTIME_REF');
const version = required('CJCJ_STAGE3_CANGJIE_VERSION');
if (process.platform !== 'darwin' || process.arch !== 'arm64') throw new Error('iOS source build requires darwin/arm64');
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be filesystem root');
const probe = probeRequirement('xcode-ios');
if (!probe.present) throw new Error(probe.detail);
const repository = path.join(workspace, 'cangjie_runtime');
const actualRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
if (actualRef !== expectedRef) throw new Error(`runtime source mismatch: ${actualRef} != ${expectedRef}`);
const sdk = path.join(workspace, 'software', 'cangjie');
const compiler = path.join(sdk, 'bin', 'cjcj-stage2');
const compilerKind = (await $({stdio: 'pipe'})`file -b ${compiler}`).stdout.trim();
if (!compilerKind.includes('Mach-O') || !compilerKind.includes('arm64')) throw new Error(`wrong host compiler: ${compilerKind}`);
const output = path.join(workspace, 'software', 'final-std-ios');
await fs.rm(output, {recursive: true, force: true});
await fs.mkdir(output, {recursive: true});
const targets = [
  {target: 'ios-aarch64', tuple: 'ios_aarch64_cjnative', sdk: 'iphoneos', arch: 'arm64'},
  {target: 'ios-simulator-aarch64', tuple: 'ios_simulator_aarch64_cjnative', sdk: 'iphonesimulator', arch: 'arm64'},
  {target: 'ios-simulator-x86_64', tuple: 'ios_simulator_x86_64_cjnative', sdk: 'iphonesimulator', arch: 'x86_64'},
];
const sha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
await Promise.all(targets.map(async target => {
  const started = Date.now();
  const source = path.join(workspace, 'ios-source', target.target);
  await fs.rm(source, {recursive: true, force: true});
  await fs.mkdir(source, {recursive: true});
  await $`set -o pipefail; git -C ${repository} archive ${expectedRef} | tar -x -C ${source}`;
  const sysroot = (await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --show-sdk-path`).stdout.trim();
  const clang = (await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --find clang`).stdout.trim();
  const toolBin = path.dirname(clang);
  const runtime = path.join(source, 'runtime');
  const stdlib = path.join(source, 'stdlib');
  const install = path.join(output, target.tuple);
  const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_VERSION: version,
    SDKROOT: sysroot, PATH: [path.join(sdk, 'bin'), toolBin, process.env.PATH].join(path.delimiter)};
  const assertCompiler = async () => {
    const command = (await $({env, stdio: 'pipe'})`command -v cjc`).stdout.trim();
    await assertBootstrapCompiler({sdk, command});
  };
  await assertCompiler();
  await $({cwd: runtime, env})`python3 build.py build -t release --target ${target.target} --target-toolchain ${path.dirname(toolBin)} --target-sysroot ${sysroot} -v ${version}`;
  await $({cwd: runtime, env})`python3 build.py install`;
  const runtimeOutput = path.join(runtime, 'output');
  await $({cwd: stdlib, env})`python3 build.py build -t release --target ${target.target} --target-lib=${runtimeOutput} --target-sysroot ${sysroot} --target-toolchain ${toolBin}`;
  await $({cwd: stdlib, env})`python3 build.py install --prefix ${install}`;
  await assertCompiler();
  await writeStdProvenance({sourceDir: path.join(repository, 'stdlib'), installPrefix: install, compiler,
    note: `stage2 Darwin host cjc cross-built ${target.tuple}; runtime ${actualRef}; SDK ${sysroot}`});
  const runtimeDir = path.join(install, 'runtime', 'lib', target.tuple);
  await fs.mkdir(runtimeDir, {recursive: true});
  const records = [];
  for (const name of ['libcangjie-runtime.dylib', 'libboundscheck.dylib']) {
    const destination = path.join(runtimeDir, name);
    await fs.copyFile(path.join(runtimeOutput, 'lib', name), destination);
    const kind = (await $({stdio: 'pipe'})`file -b ${destination}`).stdout.trim();
    if (!kind.includes('Mach-O') || !kind.includes(target.arch)) throw new Error(`${target.tuple}/${name}: ${kind}`);
    records.push({file: path.relative(install, destination), sha256: await sha256(destination), kind});
  }
  const core = path.join(install, 'lib', target.tuple, 'libcangjie-std-core.a');
  const kind = (await $({stdio: 'pipe'})`file -b ${core}`).stdout.trim();
  const arches = (await $({stdio: 'pipe'})`lipo -archs ${core}`).stdout.trim();
  if (arches !== target.arch) throw new Error(`${target.tuple} core architectures: ${arches}`);
  records.push({file: path.relative(install, core), sha256: await sha256(core), kind, arches});
  await fs.access(path.join(install, 'modules', target.tuple, 'std.cjo'));
  await fs.writeFile(path.join(install, 'ios-build.json'), JSON.stringify({target, runtimeRef: actualRef,
    compilerSha256: await sha256(compiler), sysroot, records, wall: (Date.now() - started) / 1000}, null, 2) + '\n');
  console.log(`IOS_FINAL_STD_BUILT tuple=${target.tuple} records=${JSON.stringify(records)}`);
}));
