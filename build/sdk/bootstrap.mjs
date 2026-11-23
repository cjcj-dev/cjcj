// Stage0/H1 -> Stage1/2/3 self-hosting chain (one implementation). Stage2 consumes the same-source
// final std to produce Stage3; every produced compiler is checked against its declared inputs.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {installDescriptor, installSdk} from './install.mjs';
import {readNativeBinding} from './native.mjs';
import {stdProducerArgs} from './std.mjs';

export const STAGES = Object.freeze(['runtime-input', 'ast-input', 'stage2-bootstrap', 'stage2', 'std-generator', 'stdlib',
  'stage3-generator', 'stage3', 'install']);

const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const git = (dir, ...argv) => {
  const p = spawnSync('git', ['-C', dir, ...argv], {encoding: 'utf8'});
  if (p.status !== 0) throw new Error(`GIT ${dir} ${argv.join(' ')} rc=${p.status}`);
  return p.stdout.trim();
};
const tree = (dir, ref) => git(dir, 'rev-parse', `${ref}^{tree}`);

export function layout(work) {
  return {seed0: `${work}/sdk-stage2-bootstrap`, c2: `${work}/compiler-stage2-product`, c2Sdk: `${work}/sdk-std-generator`,
    std: `${work}/final-std`, seed3: `${work}/sdk-stage3-generator`, product: `${work}/compiler-product`, sdk: `${work}/cangjie`};
}

export async function runBootstrap({config, runner, cli}) {
  const {work, evidence, sources: src, commits: k, platform, jobs, zx, deps} = config;
  const L = layout(work), tuple = `${platform}_cjnative`;
  const rt = `runtime/lib/${tuple}/libcangjie-runtime.so`, core = `lib/${tuple}/libcangjie-std-core.a`;
  const library = 'third_party/llvm/lib/libLLVM-15.so';
  const {nf, rf} = readNativeBinding({nativeInstall: config.nativeInstall, runtimeInstall: config.runtimeInstall, commits: k, hostVersion: config.hostVersion});
  for (const [dir, rev] of [[src.stage2, k.cjcj], [src.stage3, k.cjcj], [src.runtime, k.runtime], [src.llvm, k.llvm], [src.ast, k.ast]])
    if (git(dir, 'rev-parse', 'HEAD') !== rev) throw new Error(`SOURCE_IDENTITY ${dir} != ${rev}`);
  const seed = read(config.seedInputs).selection, H = seed.bootstrapHost;
  if (H.version !== config.hostVersion) throw new Error(`HOST_VERSION ${H.version}`);
  const old = seed.targetComponents.compiler, oldFacts = read(`${old.install}/compiler-inputs.json`);
  if (oldFacts.commit !== config.stage2Generator || digest(old.product) !== oldFacts.compilerSha256) throw new Error('STAGE0_GENERATOR_IDENTITY');
  const llvm = {repository: src.llvm, sourceRepository: config.urls.llvm, commit: k.llvm, tree: tree(src.llvm, k.llvm), platform,
    install: config.nativeInstall, configuration: nf.configuration, buildResult: `${config.nativeInstall}/BUILD-INPUTS.json`,
    verification: {librarySha256: nf.llvmLibrary.sha256}};
  if (digest(`${config.nativeInstall}/${library}`) !== nf.llvmLibrary.sha256) throw new Error('NATIVE_LLVM_LIBRARY_SHA');
  const ast = {repository: src.ast, sourceRepository: config.urls.compiler, commit: k.ast, tree: tree(src.ast, k.ast), platform,
    install: config.nativeInstall, buildResult: llvm.buildResult, configuration: nf.configuration, astInstallation: nf.astInstallation};
  const runtime = {repository: src.runtime, sourceRepository: rf.source.repository, commit: k.runtime, tree: tree(src.runtime, k.runtime), platform,
    install: config.runtimeInstall, configuration: rf.configuration, buildResult: `${config.runtimeInstall}/NATIVE-INPUTS.json`,
    sourceRoot: `${config.runtimeInstall}/share/runtime-build`, gateStatus: `${config.runtimeInstall}/share/runtime-build/runtime/CMakebuild/gc-unit.status`};
  const stdMember = {repository: src.runtime, sourceRepository: rf.source.repository, commit: k.runtime, tree: runtime.tree, install: L.std, platform};
  const targets = {...seed.targetComponents, llvm, ast, runtime}, selection = {...seed, targetComponents: targets};
  const tools = nf.configuration.tools;
  const nk = path.join(config.cjcj, 'ci/bootstrap/sdk-native-input-check.mjs'), st = path.join(config.cjcj, 'ci/bootstrap/sdk-native-stage.mjs');
  const stdArgs = ['--platform', platform, '--jobs', String(jobs), '--heap', '24GB', '--zx', zx];
  const node = process.execPath;
  const compilerSelection = (source, result, phase, targetStd) => {
    const compiler = {repository: source, sourceRepository: config.urls.cjcj, commit: k.cjcj, tree: tree(source, k.cjcj), platform,
      install: result, product: `${result}/bin/cjcj-stage1`};
    const execution = `${result}/.compiler-exec`;
    return {...selection, targetComponents: {...targets, std: targetStd, compiler},
      compilerExecution: {role: 'separate', stage: phase, platform, compiler,
        ...Object.fromEntries(['runtime', 'std', 'llvm'].map(name => [name, {install: execution, platform}]))}};
  };
  const producer = (result, source, parentSha, buildStd) => {
    const facts = read(`${result}/compiler-inputs.json`), body = `${result}/bin/cjcj-stage1`;
    const checks = [[facts.commit, k.cjcj], [facts.nativeShim.source.commit, k.cjcj], [facts.nativeShim.llvm.commit, k.llvm],
      [facts.parentSha256, parentSha], [facts.compilerSha256, digest(body)],
      [digest(`${result}/.compiler-exec/${rt}`), digest(`${config.runtimeInstall}/${rt}`)],
      [digest(`${result}/.compiler-exec/${library}`), nf.llvmLibrary.sha256],
      [digest(`${result}/.compiler-exec/${core}`), facts.stdCoreSha256], [facts.stdCoreSha256, digest(`${buildStd}/${core}`)]];
    checks.forEach(([got, want], index) => { if (got !== want) throw new Error(`STAGE_PRODUCER_IDENTITY ${result} #${index}`); });
    return facts;
  };
  const install = (label, target, sel, production, extra = {}) => installSdk({runner, label, cli, evidence,
    descriptor: installDescriptor({label, work, install: target, selection: sel, tools, production, ...extra}), finalAsset: extra.finalAsset});
  if (!fs.existsSync(`${L.seed0}/STAGE-INPUTS.json`)) {
    runner.run('04-runtime-input', [node, nk, JSON.stringify({kind: 'runtime', install: config.runtimeInstall, commit: k.runtime, platform,
      work: `${work}/04-runtime-check`, repository: src.runtime, sourceRepository: rf.source.repository, configuration: rf.configuration})], {cwd: work});
    runner.run('04-ast-input', [node, nk, JSON.stringify({kind: 'ast', install: config.nativeInstall, commit: k.ast, llvmCommit: k.llvm,
      buildResult: llvm.buildResult, platform, work: `${work}/04-ast-check`, repository: src.ast})], {cwd: work});
    await install('05-stage2-bootstrap', L.seed0, selection, {generator: config.stage2Generator, llvm: k.llvm, runtime: k.runtime, seedStd: targets.std.commit});
  }
  if (digest(`${L.seed0}/${read(`${L.seed0}/STAGE-INPUTS.json`).compilerFile}`) !== oldFacts.compilerSha256) throw new Error('STAGE0_INSTALL_IDENTITY');
  if (!fs.existsSync(`${L.c2}/compiler-inputs.json`)) runner.run('05b-stage2', [node, st, '--kind', 'compiler', '--phase', 'stage2',
    '--source', src.stage2, '--commit', k.cjcj, '--sdk', L.seed0, '--runtime', config.runtimeInstall, '--host', H.install, '--output', L.c2,
    '--std-input', targets.std.install, '--target-dir', `${work}/compiler-stage2-target`, ...stdArgs], {cwd: work});
  const p2 = producer(L.c2, src.stage2, oldFacts.compilerSha256, L.seed0);
  if (!fs.existsSync(`${L.c2Sdk}/STAGE-INPUTS.json`)) await install('05c-std-generator', L.c2Sdk, compilerSelection(src.stage2, L.c2, 'stage2', targets.std),
    {generator: k.cjcj, generatorSha256: p2.compilerSha256, llvm: k.llvm, runtime: k.runtime, seedStd: targets.std.commit});
  if (digest(`${L.c2Sdk}/${read(`${L.c2Sdk}/STAGE-INPUTS.json`).compilerFile}`) !== p2.compilerSha256) throw new Error('STD_GENERATOR_IDENTITY');
  if (!fs.existsSync(`${L.std}/PROVENANCE.txt`)) runner.run('06-stdlib', [node, st, '--kind', 'std', '--source', src.runtime, '--commit', k.runtime,
    '--sdk', L.c2Sdk, '--runtime', config.runtimeInstall, '--output', L.std, '--compiler-runtime', 'target', '--build-type', 'release',
    '--std-dependencies', JSON.stringify(deps.std), ...stdProducerArgs(tuple, {localModeApi: config.localModeApi === true}), ...stdArgs], {cwd: work});
  const prov = fs.readFileSync(`${L.std}/PROVENANCE.txt`, 'utf8');
  if (!prov.includes(`STD_SOURCE_COMMIT = ${k.runtime}`) || !prov.includes(`BUILT_BY_CJC = ${k.cjcj}`) || !prov.includes('COLOURED = true')) throw new Error('STD_PROVENANCE');
  if (!fs.existsSync(`${L.seed3}/STAGE-INPUTS.json`)) await install('07-stage3-generator', L.seed3, compilerSelection(src.stage2, L.c2, 'stage2-target-sdk', stdMember),
    {generator: k.cjcj, generatorSha256: p2.compilerSha256, llvm: k.llvm, runtime: k.runtime, std: k.runtime});
  if (digest(`${L.seed3}/${core}`) !== digest(`${L.std}/${core}`)) throw new Error('STAGE3_GENERATOR_STD');
  if (!fs.existsSync(`${L.product}/compiler-inputs.json`)) runner.run('08-stage3', [node, st, '--kind', 'compiler', '--phase', 'stage3',
    '--source', src.stage3, '--commit', k.cjcj, '--sdk', L.seed3, '--runtime', config.runtimeInstall, '--host', H.install, '--output', L.product,
    '--std-input', L.std, '--target-dir', `${work}/compiler-target`, ...stdArgs], {cwd: work});
  const p3 = producer(L.product, src.stage3, p2.compilerSha256, L.std);
  if (!fs.existsSync(`${L.sdk}/STAGE-INPUTS.json`)) await install('09-install', L.sdk, compilerSelection(src.stage3, L.product, 'stage3', stdMember),
    {compiler: k.cjcj, compilerSha256: p3.compilerSha256, llvm: k.llvm, llvmSha256: nf.llvmLibrary.sha256, runtime: k.runtime, std: k.runtime},
    {buildJavaInterop: true, javaJdk: deps.javaHome, finalAsset: config.asset});
  const installed = read(`${L.sdk}/STAGE-INPUTS.json`);
  if (installed.compilerCommit !== k.cjcj || installed.selection.targetComponents.llvm.commit !== k.llvm
    || installed.selection.targetComponents.runtime.commit !== k.runtime || digest(`${L.sdk}/${installed.compilerFile}`) !== p3.compilerSha256)
    throw new Error('FINAL_INSTALL_IDENTITY');
  for (const dir of [src.stage2, src.stage3]) {
    const changed = git(dir, 'diff', '--name-only', 'HEAD', '--');
    if (changed && changed !== 'cjpm.lock') throw new Error(`COMPILER_SOURCE_MODIFIED ${dir}: ${changed}`);
    if (changed) git(dir, 'restore', '--source=HEAD', '--', 'cjpm.lock');
  }
  const summary = {sdk: L.sdk, compiler: k.cjcj, compilerSha256: p3.compilerSha256, stage2CompilerSha256: p2.compilerSha256,
    llvm: k.llvm, llvmSha256: nf.llvmLibrary.sha256, runtime: k.runtime, runtimeSha256: digest(`${L.sdk}/${rt}`), std: k.runtime,
    stdCoreSha256: p3.stdCoreSha256, ast: k.ast, host: H.version, stage2Generator: config.stage2Generator};
  fs.writeFileSync(path.join(evidence, 'bootstrap-summary.json'), JSON.stringify(summary, null, 2) + '\n');
  return summary;
}
