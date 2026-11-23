// node build/cli.mjs sdk <plan|build|package|verify>: the single SDK production entry.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadPins} from './pins.mjs';
import {ASSETS, assetFileName, findAsset} from './targets.mjs';
import {createRunner} from './run.mjs';
import {STAGES, layout, runBootstrap} from './bootstrap.mjs';
import {nativeConfig, nativeSteps} from './native.mjs';
import {checkTools, stdxArgs, toolsArgs} from './tools.mjs';
import {verifySdk} from './verify.mjs';
import {packArchive, relocateAndVerify, writeSums} from './archive.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const CLI = path.join(repo, 'build/cli.mjs');
const STEPS = Object.freeze(['native', 'sources', 'bootstrap', 'stdx', 'tools']);
const USAGE = `usage: node build/cli.mjs sdk plan [--asset KEY]
       node build/cli.mjs sdk build --config FILE [--step ${STEPS.join('|')}|all]
       node build/cli.mjs sdk package --config FILE --asset KEY
       node build/cli.mjs sdk verify --sdk DIR --asset KEY [--work DIR] [--java-home DIR]`;

export function parseArgs(argv) {
  const [command, ...rest] = argv, options = {};
  for (let i = 0; i < rest.length; i += 2) {
    const key = rest[i];
    if (!/^--[a-z-]+$/.test(key ?? '') || rest[i + 1] === undefined || rest[i + 1].startsWith('--')) throw new Error(`SDK_ARGS ${key}\n${USAGE}`);
    options[key.slice(2)] = rest[i + 1];
  }
  if (!['plan', 'build', 'package', 'verify'].includes(command)) throw new Error(`SDK_COMMAND ${command}\n${USAGE}`);
  return {command, options};
}

export function readConfig(file) {
  const config = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const key of ['work', 'evidence', 'cjcj', 'platform', 'asset', 'nativeInstall', 'runtimeInstall', 'seedInputs', 'sources', 'commits', 'env'])
    if (config[key] === undefined) throw new Error(`SDK_CONFIG missing ${key}`);
  const pins = loadPins();
  for (const [name, key] of [['runtime', 'runtime'], ['llvm', 'llvm'], ['ast', 'compiler'], ['tools', 'tools'], ['stdx', 'stdx']])
    if (config.commits[name] !== pins.repos[key].commit) throw new Error(`SDK_CONFIG_PIN ${name} ${config.commits[name]} != ${pins.repos[key].commit}`);
  findAsset(config.asset);
  return {...config, version: pins.version, hostVersion: pins.hostVersion, pins};
}

export function plan(assetKey) {
  const pins = loadPins(), assets = assetKey ? [findAsset(assetKey)] : ASSETS;
  return {version: pins.version, hostVersion: pins.hostVersion, repos: pins.repos, wasi: pins.wasi, steps: STEPS, bootstrapStages: STAGES,
    assets: assets.map(asset => ({...asset, file: assetFileName(asset.key, pins.version)}))};
}

function globals(config) {
  return ['--workspace', config.workspace, '--build-root', `${config.work}/build-tools`, '--target', config.target ?? 'linux-x64',
    '--build-type', 'release', '--stdx-profile', 'full', '--cangjie-version', config.version, '--official-sdk-root', config.hostSdk,
    '--jobs', String(config.jobs), '--tools-package-jobs', '3'];
}

async function build(config, step) {
  const runner = createRunner({evidence: config.evidence, env: config.env});
  const steps = step === 'all' ? STEPS : [step];
  for (const name of steps) {
    if (!STEPS.includes(name)) throw new Error(`SDK_STEP ${name}`);
    const L = layout(config.work), node = process.execPath;
    if (name === 'native') {
      const file = path.join(config.evidence, 'native-config.json');
      fs.writeFileSync(file, JSON.stringify(nativeConfig({template: config.nativeTemplate, sources: {...config.sources, cjcj: config.sources.stage3},
        build: `${config.work}/native/build`, install: config.nativeInstall, commits: config.commits}), null, 2) + '\n');
      for (const s of nativeSteps({cjcj: config.sources.stage3, config: file, runtimeEnv: {...config.env, ...config.runtimeEnv}, zx: config.zx}))
        runner.run(s.label, s.argv, {cwd: s.cwd ?? config.work, environment: s.env ?? config.env});
    } else if (name === 'sources') {
      const r = config.pins.repos;
      runner.run('03-sources', [node, CLI, ...globals(config), 'fetch', '--repo-tag', `tools=${r.tools.commit}`, '--repo-tag', `stdx=${r.stdx.commit}`,
        '--repo-url', `tools=${r.tools.url}`, '--repo-url', `stdx=${r.stdx.url}`, '--repo-tag', `compiler=${r.compiler.commit}`,
        '--repo-tag', `runtime=${r.runtime.commit}`, '--repo-tag', `llvm=${r.llvm.commit}`, '--repo-url', `compiler=${config.origins.compiler}`,
        '--repo-url', `runtime=${config.origins.runtime}`, '--repo-url', `llvm=${config.origins.llvm}`], {cwd: config.cjcj});
    } else if (name === 'bootstrap') {
      // Native LLVM/cjdb hands its Python/cjdb payload to the installer once, from the same install.
      if (!fs.existsSync(`${config.nativeInstall}/share/cjcj/build-inputs/python-original.json`))
        runner.run('04-native-handoff', [node, path.join(config.sources.stage3, 'ci/bootstrap/native-cjdb-job.mjs'), 'package',
          config.nativeInstall, `${config.work}/native/handoff`], {cwd: config.work});
      await runBootstrap({config, runner, cli: CLI});
    } else if (name === 'stdx') {
      runner.run('10-stdx', [node, CLI, ...stdxArgs({globals: globals(config)})], {cwd: config.cjcj, environment: {...config.env,
        CJCJ_SRCBUILD_CONSUMER_SDK: L.sdk, CJCJ_SRCBUILD_BOOTSTRAP_SDK: config.hostSdk, STDX_HOST_CANGJIE_HOME: L.sdk}});
      const p = JSON.parse(fs.readFileSync(`${L.sdk}/share/cjcj/build-inputs/stdx.json`, 'utf8'));
      if (p.source.commit !== config.commits.stdx || p.build.rc !== 0 || p.install.rc !== 0) throw new Error('STDX_PRODUCER');
    } else if (name === 'tools') {
      const tuple = `${config.platform}_cjnative`;
      runner.run('11-tools', [node, CLI, ...toolsArgs({globals: globals(config), sdk: L.sdk, frontend: config.sources.stage3,
        frontendRef: config.commits.cjcj, product: L.product, llvmLibrary: `${config.nativeInstall}/third_party/llvm/lib/libLLVM-15.so`,
        stdxJsonBuild: `${config.workspace}/cangjie_stdx/build_temp/build`, jdk: config.deps.javaHome,
        runtimeHeader: `${config.runtimeInstall}/include/Cangjie.h`, lombok: config.deps.lombok})], {cwd: config.cjcj, environment: {...config.env,
        CJCJ_SRCBUILD_CONSUMER_SDK: L.sdk, CJCJ_SRCBUILD_BOOTSTRAP_SDK: config.hostSdk, CANGJIE_STDX_PATH: `${L.sdk}/stdx/${tuple}/static/stdx`,
        CJFMT_FRONTEND_CJO: `${L.product}/share/cjcj/cjo`, CJFMT_FRONTEND_LIB: `${L.product}/share/cjcj/cjo`,
        CJFMT_FRONTEND_NATIVE: `${L.product}/share/cjcj/runtime_shim/cjc_runtime_config.o`, CJFMT_FRONTEND_REF: config.commits.cjcj}});
      checkTools(JSON.parse(fs.readFileSync(`${L.sdk}/TOOLS-INPUTS.json`, 'utf8')), config.commits.tools);
    }
  }
  return runner.records;
}

async function pack(config, assetKey) {
  const L = layout(config.work), out = path.join(config.work, 'release');
  const verify = (sdk, label) => verifySdk({sdk, asset: assetKey, work: path.join(config.work, `verify-${label}`), javaHome: config.deps?.javaHome,
    report: path.join(config.evidence, `verify-${label}.json`)});
  await verify(L.sdk, 'installed');
  const archive = packArchive({sdk: L.sdk, asset: assetKey, version: config.version, output: out});
  writeSums(out, [archive]);
  const relocated = await relocateAndVerify({file: archive.file, asset: assetKey, version: config.version, sdk: L.sdk,
    work: path.join(config.work, 'relocate'), verify: root => verify(root, 'relocated')});
  const manifest = {asset: assetKey, file: archive.name, sha256: archive.sha256, bytes: archive.bytes, version: config.version,
    commits: config.commits, relocatedRoot: relocated.root, status: 'PACKAGED_AND_RELOCATED'};
  fs.writeFileSync(path.join(out, 'SDK-MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n');
  fs.writeFileSync(path.join(config.evidence, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

export async function main(argv) {
  const {command, options} = parseArgs(argv);
  if (command === 'plan') { process.stdout.write(JSON.stringify(plan(options.asset), null, 2) + '\n'); return; }
  if (command === 'verify') {
    if (!options.sdk || !options.asset) throw new Error(USAGE);
    const result = await verifySdk({sdk: options.sdk, asset: options.asset, work: options.work ?? path.join(path.dirname(path.resolve(options.sdk)), 'verify-work'),
      javaHome: options['java-home'], report: options.report});
    process.stdout.write(JSON.stringify({status: result.status, asset: result.asset, colourOnlyCount: result.colourOnlyCount}) + '\n');
    return;
  }
  if (!options.config) throw new Error(USAGE);
  const config = readConfig(options.config);
  if (command === 'build') { await build(config, options.step ?? 'all'); return; }
  const manifest = await pack(config, options.asset ?? config.asset);
  process.stdout.write(JSON.stringify(manifest) + '\n');
}
