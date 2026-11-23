// Stage0 -> Stage1/2/3 self-hosting chain (one implementation). A local-mode compiler cannot read the
// non-modal seed std, and an SDK that carries it leaks it into a std build (its lib/ precedes the build
// tree at link), so std is never built inside such an SDK: the chain follows the H1 same-source order of ci/bootstrap/sdk-targets.mjs
// (std-bootstrap -> stage1-initial -> stage1-std -> stage2 -> final-std -> stage3). The seed std is
// only used to compile Stage1 itself; every std is then built by a compiler whose SDK holds either
// no target std (the std-free view) or a std produced earlier in this chain from the same source.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {installDescriptor, installSdk} from './install.mjs';
import {readNativeBinding} from './native.mjs';
import {stdProducerArgs} from './std.mjs';

export const STAGES = Object.freeze(['runtime-input', 'ast-input', 'stage1-bootstrap', 'stage1', 'stage1-generator',
  'std-bootstrap-view', 'std-bootstrap', 'stage1-initial', 'stage1-std', 'stage1-std-sdk', 'stage2', 'stage2-generator',
  'final-std', 'stage3-generator', 'stage3', 'install']);

export function layout(work) {
  return {seed0: `${work}/sdk-stage1-bootstrap`, c1: `${work}/compiler-stage1-product`, c1Sdk: `${work}/sdk-stage1-generator`,
    stdView: `${work}/sdk-std-bootstrap-view`, stdBoot: `${work}/std-bootstrap`, s1Init: `${work}/sdk-stage1-initial`,
    std1: `${work}/stage1-std`, s1Std: `${work}/sdk-stage1-std`, c2: `${work}/compiler-stage2-product`,
    c2Sdk: `${work}/sdk-stage2-generator`, std: `${work}/final-std`, seed3: `${work}/sdk-stage3-generator`,
    product: `${work}/compiler-product`, sdk: `${work}/cangjie`};
}

// The executed chain after the Stage1 bootstrap SDK (seed0 = Stage A generator + seed std). 'seed' names
// the frozen non-modal seed std; every other std is a directory produced by an earlier 'std' step.
export function chainPlan(L) {
  return [
    {id: '05b-stage1', stage: 'stage1', kind: 'compiler', phase: 'stage2', sdk: L.seed0, stdInput: 'seed', output: L.c1, parent: 'seed0'},
    {id: '05c-stage1-generator', stage: 'stage1-generator', kind: 'install', compiler: L.c1, std: 'seed', output: L.c1Sdk, phase: 'stage2'},
    {id: '05d-std-bootstrap-view', stage: 'std-bootstrap-view', kind: 'view', from: L.c1Sdk, output: L.stdView},
    {id: '06a-std-bootstrap', stage: 'std-bootstrap', kind: 'std', sdk: L.stdView, output: L.stdBoot},
    {id: '06b-stage1-initial', stage: 'stage1-initial', kind: 'install', compiler: L.c1, std: L.stdBoot, output: L.s1Init, phase: 'stage2'},
    {id: '06c-stage1-std', stage: 'stage1-std', kind: 'std', sdk: L.s1Init, output: L.std1},
    {id: '06d-stage1-std-sdk', stage: 'stage1-std-sdk', kind: 'install', compiler: L.c1, std: L.std1, output: L.s1Std, phase: 'stage2'},
    {id: '06e-stage2', stage: 'stage2', kind: 'compiler', phase: 'stage2', sdk: L.s1Std, stdInput: L.std1, output: L.c2, parent: L.c1},
    {id: '06f-stage2-generator', stage: 'stage2-generator', kind: 'install', compiler: L.c2, std: L.std1, output: L.c2Sdk, phase: 'stage2'},
    {id: '06-stdlib', stage: 'final-std', kind: 'std', sdk: L.c2Sdk, output: L.std},
    {id: '07-stage3-generator', stage: 'stage3-generator', kind: 'install', compiler: L.c2, std: L.std, output: L.seed3, phase: 'stage2-target-sdk'},
    {id: '08-stage3', stage: 'stage3', kind: 'compiler', phase: 'stage3', sdk: L.seed3, stdInput: L.std, output: L.product, parent: L.c2},
  ];
}

// Invariant (not mechanism): a std is only ever built by an SDK whose target std is absent or was
// itself built earlier in this chain; Stage2 and Stage3 are compiled against same-source std only.
export function assertSameSourceChain(plan) {
  const sdkStd = new Map(), builtStd = new Set(), compilers = new Set();
  for (const step of plan) {
    if (step.kind === 'install') {
      if (!compilers.has(step.compiler)) throw new Error(`CHAIN_UNBUILT_COMPILER ${step.id}`);
      if (step.std !== 'seed' && !builtStd.has(step.std)) throw new Error(`CHAIN_UNBUILT_STD ${step.id}`);
      sdkStd.set(step.output, step.std);
    } else if (step.kind === 'view') {
      if (!sdkStd.has(step.from)) throw new Error(`CHAIN_VIEW_SOURCE ${step.id}`);
      sdkStd.set(step.output, null);
    } else if (step.kind === 'std') {
      if (!sdkStd.has(step.sdk)) throw new Error(`CHAIN_UNKNOWN_SDK ${step.id}`);
      if (sdkStd.get(step.sdk) === 'seed') throw new Error(`CHAIN_SEED_STD ${step.id}`);
      builtStd.add(step.output);
    } else if (step.kind === 'compiler') {
      if (step.stdInput === 'seed' ? compilers.size !== 0 : !builtStd.has(step.stdInput)) throw new Error(`CHAIN_COMPILER_STD ${step.id}`);
      if (sdkStd.has(step.sdk) && sdkStd.get(step.sdk) !== step.stdInput) throw new Error(`CHAIN_COMPILER_SDK_STD ${step.id}`);
      compilers.add(step.output);
    } else throw new Error(`CHAIN_KIND ${step.id}`);
  }
  if (!builtStd.size || ![...sdkStd.values()].includes(null)) throw new Error('CHAIN_NO_STD_BOOTSTRAP');
  return plan;
}

// The std-free view of a generator SDK: hard links of every member except the target std modules and
// libraries (modules/<tuple>/std*, lib/<tuple>/libcangjie-std*). The compiler's own execution std under
// .compiler-exec/ is kept, so the compiler still runs; only the target std it would import is gone.
export function stdFreeView(from, to, tuple) {
  if (fs.existsSync(`${to}/STD-BOOTSTRAP-VIEW.json`)) return read(`${to}/STD-BOOTSTRAP-VIEW.json`);
  const partial = `${to}.partial`;
  fs.rmSync(partial, {recursive: true, force: true});
  const cp = spawnSync('cp', ['-al', from, partial], {encoding: 'utf8'});
  if (cp.status !== 0) throw new Error(`STD_VIEW_COPY rc=${cp.status} ${cp.stderr}`);
  const removed = [];
  for (const [dir, pattern] of [[`modules/${tuple}`, /^std([.]|$)/], [`lib/${tuple}`, /^libcangjie-std([.-]|$)/]]) {
    const root = path.join(partial, dir);
    for (const name of fs.existsSync(root) ? fs.readdirSync(root).sort() : []) if (pattern.test(name)) {
      fs.rmSync(path.join(root, name), {recursive: true, force: true});
      removed.push(`${dir}/${name}`);
    }
  }
  if (!removed.some(row => row.startsWith('modules/')) || !removed.some(row => row.startsWith('lib/'))) {
    fs.rmSync(partial, {recursive: true, force: true});
    throw new Error(`STD_VIEW_NOTHING_REMOVED ${from}`);
  }
  const facts = {from, tuple, removed};
  fs.writeFileSync(`${partial}/STD-BOOTSTRAP-VIEW.json`, JSON.stringify(facts, null, 2) + '\n');
  fs.renameSync(partial, to);
  return facts;
}


// Every std of the chain is built from the same source checkout, whose stdlib/build tree (git-ignored
// build output) would otherwise let ninja keep objects compiled by the previous step's compiler. The
// H1 chain gets this from one checkout per std step; here each std step starts from an empty tree.
// The staged std dependencies (stdlib/third_party/{boundscheck-v1.1.16,pcre2}) are copies of the pinned
// roots that prepareStdDependencies (ci/bootstrap/stdlib-build.mjs:23-41) only accepts again when the same
// std output recorded them, so they are cleared with the build tree and staged afresh for each std step.
export const STD_BUILD_OUTPUTS = Object.freeze(['stdlib/build', 'stdlib/third_party/boundscheck-v1.1.16', 'stdlib/third_party/pcre2']);
export function freshStdBuildTree(runtimeSource) {
  for (const rel of STD_BUILD_OUTPUTS) {
    const ignored = spawnSync('git', ['-C', runtimeSource, 'check-ignore', '-q', `${rel}/x`], {encoding: 'utf8'});
    if (ignored.status !== 0) throw new Error(`STD_BUILD_TREE_NOT_IGNORED ${path.join(runtimeSource, rel)}`);
  }
  for (const rel of STD_BUILD_OUTPUTS) fs.rmSync(path.join(runtimeSource, rel), {recursive: true, force: true});
  return STD_BUILD_OUTPUTS.map(rel => path.join(runtimeSource, rel));
}

const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const git = (dir, ...argv) => {
  const p = spawnSync('git', ['-C', dir, ...argv], {encoding: 'utf8'});
  if (p.status !== 0) throw new Error(`GIT ${dir} ${argv.join(' ')} rc=${p.status}`);
  return p.stdout.trim();
};
const tree = (dir, ref) => git(dir, 'rev-parse', `${ref}^{tree}`);

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
    await install('05-stage1-bootstrap', L.seed0, selection, {generator: config.stage2Generator, llvm: k.llvm, runtime: k.runtime, seedStd: targets.std.commit});
  }
  if (digest(`${L.seed0}/${read(`${L.seed0}/STAGE-INPUTS.json`).compilerFile}`) !== oldFacts.compilerSha256) throw new Error('STAGE0_INSTALL_IDENTITY');
  // Same-source chain: each step is skipped when its product already exists (resume), then re-checked.
  const plan = assertSameSourceChain(chainPlan(L));
  const facts = new Map([['seed0', {compilerSha256: oldFacts.compilerSha256}]]);
  const stdMemberOf = dir => dir === 'seed' ? targets.std : {...stdMember, install: dir};
  const coreOf = dir => dir === 'seed' ? `${L.seed0}/${core}` : `${dir}/${core}`;
  const sourceOf = step => step.phase === 'stage3' ? src.stage3 : src.stage2;
  for (const step of plan) {
    if (step.kind === 'compiler') {
      if (!fs.existsSync(`${step.output}/compiler-inputs.json`)) runner.run(step.id, [node, st, '--kind', 'compiler', '--phase', step.phase,
        '--source', sourceOf(step), '--commit', k.cjcj, '--sdk', step.sdk, '--runtime', config.runtimeInstall, '--host', H.install,
        '--output', step.output, '--std-input', step.stdInput === 'seed' ? targets.std.install : step.stdInput,
        '--target-dir', `${work}/${path.basename(step.output)}-target`, ...stdArgs], {cwd: work});
      facts.set(step.output, producer(step.output, sourceOf(step), facts.get(step.parent).compilerSha256,
        step.stdInput === 'seed' ? L.seed0 : step.stdInput));
    } else if (step.kind === 'install') {
      const made = facts.get(step.compiler);
      if (!fs.existsSync(`${step.output}/STAGE-INPUTS.json`)) await install(step.id, step.output,
        compilerSelection(src.stage2, step.compiler, step.phase, stdMemberOf(step.std)),
        {generator: k.cjcj, generatorSha256: made.compilerSha256, llvm: k.llvm, runtime: k.runtime,
          ...(step.std === 'seed' ? {seedStd: targets.std.commit} : {std: k.runtime})});
      if (digest(`${step.output}/${read(`${step.output}/STAGE-INPUTS.json`).compilerFile}`) !== made.compilerSha256)
        throw new Error(`GENERATOR_IDENTITY ${step.id}`);
      if (digest(`${step.output}/${core}`) !== digest(coreOf(step.std))) throw new Error(`GENERATOR_STD ${step.id}`);
    } else if (step.kind === 'view') {
      const view = stdFreeView(step.from, step.output, tuple);
      if (fs.existsSync(`${step.output}/${core}`) || !fs.existsSync(`${step.output}/.compiler-exec`)) throw new Error(`STD_VIEW_LAYOUT ${view.from}`);
    } else {
      if (!fs.existsSync(`${step.output}/PROVENANCE.txt`)) freshStdBuildTree(src.runtime);
      if (!fs.existsSync(`${step.output}/PROVENANCE.txt`)) runner.run(step.id, [node, st, '--kind', 'std', '--source', src.runtime, '--commit', k.runtime,
        '--sdk', step.sdk, '--runtime', config.runtimeInstall, '--output', step.output, '--compiler-runtime', 'target', '--build-type', 'release',
        '--std-dependencies', JSON.stringify(deps.std), ...stdProducerArgs(tuple, {localModeApi: config.localModeApi === true}), ...stdArgs], {cwd: work});
      const prov = fs.readFileSync(`${step.output}/PROVENANCE.txt`, 'utf8');
      if (!prov.includes(`STD_SOURCE_COMMIT = ${k.runtime}`) || !prov.includes(`BUILT_BY_CJC = ${k.cjcj}`) || !prov.includes('COLOURED = true'))
        throw new Error(`STD_PROVENANCE ${step.id}`);
    }
  }
  const p1 = facts.get(L.c1), p2 = facts.get(L.c2), p3 = facts.get(L.product);
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
    stdCoreSha256: p3.stdCoreSha256, ast: k.ast, host: H.version, stage2Generator: config.stage2Generator,
    stage1CompilerSha256: p1.compilerSha256, chain: plan.map(step => step.id)};
  fs.writeFileSync(path.join(evidence, 'bootstrap-summary.json'), JSON.stringify(summary, null, 2) + '\n');
  return summary;
}
