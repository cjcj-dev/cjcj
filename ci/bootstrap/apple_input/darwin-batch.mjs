#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {read, write, hash, dependencyArgv} from './identity.mjs';
import {prepare, bindPrepared} from './prepare.mjs';
import {capture} from './capture.mjs';

const mode = process.env.APPLE_BATCH_MODE;
if (!['green', 'controls'].includes(mode)) throw new Error('mode');
const root = path.resolve(process.env.RUNNER_TEMP, 'apple-input-' + process.env.GITHUB_RUN_ID);
const evidence = path.resolve('evidence/apple-input');
fs.mkdirSync(root, {recursive: true}); fs.mkdirSync(evidence, {recursive: true});
const deadline = Number(process.env.APPLE_BATCH_DEADLINE);
const state = {mode, runner: process.env.RUNNER_NAME, image: process.env.ImageVersion,
  started_at: new Date().toISOString(), deadline, phase: 'preparation', commands: [], results: [], qualification: null};
const save = () => write(path.join(evidence, 'execution.json'), state);
save();
function command(name, argv, options = {}) {
  if (Date.now() / 1000 >= deadline - 60) throw new Error('collection-deadline');
  const started_at = new Date().toISOString();
  const r = spawnSync('/bin/zsh', ['-c', 'ulimit -c 0; exec "$@"', 'apple-input', ...argv], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    timeout: Math.min(600000, (deadline - 60) * 1000 - Date.now()), ...options});
  fs.writeFileSync(path.join(evidence, name + '.stdout'), r.stdout ?? '');
  fs.writeFileSync(path.join(evidence, name + '.stderr'), r.stderr ?? '');
  state.commands.push({name, argv, cwd: options.cwd ?? process.cwd(), environment: options.env ?? null,
    started_at, finished_at: new Date().toISOString(), rc: r.status, signal: r.signal,
    error: r.error ? {message: r.error.message, code: r.error.code, errno: r.error.errno} : null}); save();
  if (r.status !== 0) throw new Error('first-error-stop:' + name);
  return r.stdout;
}
try {
  if (process.platform !== 'darwin' || process.arch !== 'arm64') throw new Error('runner-platform');
  const developer = '/Applications/Xcode_16.4.app/Contents/Developer';
  if (!fs.existsSync(developer)) throw new Error('runner-image-Xcode16.4-missing');
  const metadataEnv = {PATH: process.env.PATH, HOME: root, TMPDIR: process.env.RUNNER_TEMP, DEVELOPER_DIR: developer};
  const xcode = command('xcode-version', ['/usr/bin/xcodebuild', '-version'], {env: metadataEnv});
  const sdkVersion = command('sdk-version', ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'], {env: metadataEnv}).trim();
  const origin = fs.realpathSync(command('sdk-root', ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], {env: metadataEnv}).trim());
  if (xcode !== 'Xcode 16.4\nBuild version 16F6\n' || sdkVersion !== '15.5') throw new Error('runner-image-identity');
  const clang = fs.realpathSync(command('clang-path', ['/usr/bin/xcrun', '--find', 'clang'], {env: metadataEnv}).trim());
  command('clang-version', [clang, '--version']);
  const apple = path.join(root, 'AppleSDK-headers');
  fs.mkdirSync(apple);
  fs.cpSync(path.join(origin, 'usr/include'), path.join(apple, 'usr/include'), {recursive: true, dereference: true});
  fs.copyFileSync(path.join(origin, 'SDKSettings.json'), path.join(apple, 'SDKSettings.json'));
  write(path.join(evidence, 'apple-origin.json'), {origin, consumed_root: apple, xcode, sdk_version: sdkVersion,
    scope: 'private byte copy of actual SDK usr/include and SDKSettings; no framework or link qualification', settings_sha256: hash(path.join(apple, 'SDKSettings.json'))});
  // These exact immutable inputs are packaged from the authorized local Git
  // objects; the pinned validators below independently verify every entity.
  command('materialize-pinned-inputs', ['/usr/bin/tar', '-xzf',
    fileURLToPath(new URL('./pinned-inputs.tar.gz', import.meta.url)), '-C', root]);
  const legacyDir = path.join(root, 'legacy');
  const frozen = read(path.join(legacyDir, 'frozen-inputs.json'));
  const sourceRoot = path.join(root, 'source');
  const archive = path.join(root, 'official-sdk.tar.gz');
  const url = 'https://gitcode.com/Cangjie/nightly_build/releases/download/1.3.0-alpha.20260925001050/cangjie-sdk-mac-aarch64-1.3.0-alpha.20260925001050.tar.gz';
  command('sdk-download', ['/usr/bin/curl', '--fail', '--location', '--max-time', '300', '--output', archive, url]);
  if (hash(archive) !== frozen.sdk_archive_sha256) throw new Error('official-sdk-archive-hash');
  command('sdk-extract', ['/usr/bin/tar', '-xzf', archive, '-C', root]);
  const sdk = path.join(root, 'cangjie'), lock = path.join(root, 'SDK.lock');
  const lockCode = 'import sys,json,hashlib\nfrom pathlib import Path\nr=Path(sys.argv[1]); f={p.relative_to(r).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in r.rglob("*") if p.is_file()}\nPath(sys.argv[2]).write_text(json.dumps({"archive_sha256":sys.argv[3],"files":f}))';
  command('sdk-lock', ['python3', '-c', lockCode, sdk, lock, frozen.sdk_archive_sha256]);
  const sccache = command('sccache-path', ['/usr/bin/which', 'sccache']).trim();
  const home = path.join(root, 'home'), tmp = path.join(root, 'tmp');
  fs.mkdirSync(home); fs.mkdirSync(tmp);
  const environment = {HOME: home, TMPDIR: tmp, CANGJIE_HOME: sdk,
    PATH: sdk + '/bin:' + sdk + '/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin',
    DYLD_LIBRARY_PATH: ['runtime/lib/darwin_aarch64_cjnative', 'lib/darwin_aarch64_cjnative', 'third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p)).join(':')};
  // The original calibrated layout is not replaced. This new raw record dump
  // supplies independent compile-time layout evidence, without native execution.
  const layout = {stack_size: 24, ss_sp_offset: 0, ss_size_offset: 8, ss_flags_offset: 16};
  const inputs = {sdk_archive: archive, sdk_root: sdk, sdk_lock: lock, environment, apple_sdkroot: apple,
    clang, sccache, layout, runner_platform: 'macOS', runner_available_cores: os.availableParallelism(), jobs: os.availableParallelism()};
  state.phase = 'prepare'; save();
  const output = path.join(root, 'prepared');
  const unbound = prepare(sourceRoot, output, inputs, legacyDir, null);
  const recipePath = path.join(output, 'build-recipe.json');
  const compilation = unbound.steps[0].argv.slice(1);
  const source = compilation[compilation.indexOf('-c') + 1];
  const depArgv = dependencyArgv(compilation);
  state.phase = 'collection'; save();
  const deps = path.join(evidence, 'helper.deps');
  fs.writeFileSync(deps, command('clang-dependencies', depArgv, {cwd: output, env: environment}));
  const preprocessArgv = depArgv.map(a => a === '-M' ? '-E' : a);
  const preprocessed = command('clang-preprocessed', preprocessArgv, {cwd: output, env: environment});
  // Read the definition from this consumer's actual include chain. Line markers
  // preserve the original header location, rather than naming a known SDK type.
  let currentFile = null, currentLine = 0;
  const definitions = [];
  const lines = preprocessed.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const marker = lines[i].match(/^#\s+(\d+)\s+"([^"]+)"/);
    if (marker) {currentFile = marker[2]; currentLine = Number(marker[1]); continue;}
    const definition = lines[i].match(/\bstruct\s+([A-Za-z_]\w*)\s*\{/);
    if (definition && definition[1].endsWith('sigaltstack')) definitions.push({name: definition[1], file: currentFile, line: currentLine,
      preprocessed_line: i + 1});
    currentLine++;
  }
  write(path.join(evidence, 'stack-definitions.json'), definitions);
  if (definitions.length !== 1 || !definitions[0].file?.startsWith(apple + path.sep))
    throw new Error('actual-stack-definition');
  const definition = definitions[0];
  console.log(`STACK_DEFINITION ${definition.file}:${definition.line} struct ${definition.name}`);
  const layoutArgv = dependencyArgv(compilation).map(a => a === '-M' ? '-fsyntax-only' : a);
  layoutArgv.push('-Xclang', '-fdump-record-layouts-complete');
  write(path.join(evidence, 'layout-invocation.json'), {argv: layoutArgv, cwd: output, environment});
  const layoutRaw = command('clang-layout', layoutArgv, {cwd: output, env: environment});
  const blocks = layoutRaw.split('*** Dumping AST Record Layout');
  const selectStack = name => blocks.filter(b => b.split('\n').some(line =>
    line.match(/^\s*0\s*\| struct ([A-Za-z_]\w*)\s*$/)?.[1] === name));
  const selected = selectStack(definition.name);
  write(path.join(evidence, 'stack-selector.json'), {definition, matches: selected.length,
    argv: preprocessArgv, cwd: output, environment});
  fs.writeFileSync(path.join(evidence, 'stack-selected.stdout'), selected.join('\n'));
  // Positive raw-output control plus a falsifiable exact-name negative control.
  const wrongName = definition.name + '_different_type';
  const mismatch = selectStack(wrongName).length;
  write(path.join(evidence, 'stack-selector-control.json'), {wrongName, matches: mismatch});
  if (mismatch !== 0) throw new Error('actual-stack-selector-control');
  console.log('STACK_SELECTOR_DIFFERENT_TYPE REJECT matches=' + mismatch);
  const stack = selected.length === 1 ? selected[0] : null;
  if (!stack || !/0\s*\|\s+void \* ss_sp/.test(stack) || !/8\s*\|\s+.* ss_size/.test(stack) ||
      !/16\s*\|\s+int ss_flags/.test(stack) || !/sizeof=24, align=8/.test(stack)) throw new Error('actual-stack-layout');
  const capturePath = path.join(evidence, 'capture.json');
  capture({apple_sdkroot: apple, dependencies_path: deps, layout_path: path.join(evidence, 'clang-layout.stdout'),
    tools: {clang, xcrun: '/usr/bin/xcrun', xcodebuild: '/usr/bin/xcodebuild'}, layout, xcode, sdk_version: sdkVersion,
    batch: 'GHA-' + process.env.GITHUB_RUN_ID, started_at: state.started_at, finished_at: new Date().toISOString(),
    argv: [depArgv], cwd: output, environment, consumer: {source, argv: compilation, cwd: output, environment},
    raw_outputs: [path.join(evidence, 'layout-invocation.json'), path.join(evidence, 'stack-definitions.json'), path.join(evidence, 'stack-selector.json'), path.join(evidence, 'stack-selected.stdout'), ...['xcode-version', 'sdk-version', 'sdk-root', 'clang-version', 'clang-dependencies', 'clang-preprocessed', 'clang-layout'].flatMap(n =>
      [path.join(evidence, n + '.stdout'), path.join(evidence, n + '.stderr')])]}, capturePath);
  state.phase = 'bind'; save();
  bindPrepared(recipePath, capturePath, legacyDir);
  const originalRecipe = fs.readFileSync(recipePath);
  const entry = new URL('./first-build.mjs', import.meta.url), target = new URL('./consumer-target.mjs', import.meta.url);
  function run(name, expected) {
    const r = read(recipePath);
    const auth = {stage: 'offline-launch-boundary', count: 1, recipe_sha256: hash(recipePath), source_head: r.source_head,
      input_manifest_sha256: r.input_manifest_sha256, archive_reserve_seconds: 60,
      absolute_deadline_epoch: deadline, new_batch_id: read(capturePath).source_ref};
    const code = `import {prelaunch} from ${JSON.stringify(entry.href)}; import {assertAdmission} from ${JSON.stringify(target.href)}; assertAdmission(prelaunch, ${JSON.stringify([recipePath, auth, legacyDir])}, ${JSON.stringify(expected)});`;
    const stdout = command(name, [process.execPath, '--input-type=module', '-e', code]);
    const matched = stdout.includes('TARGET_ASSERTION ' + expected + ' ') && stdout.includes(' PASS');
    state.results.push({name, expected, matched, rc: 0, recipe_sha256: hash(recipePath), capture_sha256: hash(capturePath),
      entry_sha256: hash(entry), target_sha256: hash(target)}); save();
    process.stdout.write(stdout);
    if (!matched) throw new Error('target-not-observed');
  }
  state.phase = 'admission'; save();
  run('green', 'BOUNDARY');
  {
    const header = read(capturePath).headers.find(h => h.path.endsWith('/pthread.h')).path;
    const bytes = fs.readFileSync(header);
    try {fs.appendFileSync(header, '\n/* authorized consumer header drift */\n'); run('header-drift', 'apple-header-drift');}
    finally {fs.writeFileSync(header, bytes);}
    run('header-restored', 'BOUNDARY');
    const otherHome = path.join(root, 'other-home'); fs.mkdirSync(otherHome);
    try {const r = read(recipePath); r.environment.HOME = otherHome; r.inputs.environment.HOME = otherHome; write(recipePath, r);
      run('environment-drift', 'apple-consumer-binding');}
    finally {fs.writeFileSync(recipePath, originalRecipe);}
    run('environment-restored', 'BOUNDARY');
  }
  state.phase = 'archive'; save();
  for (const name of ['build-recipe.json', 'input-manifest.json', 'manifest-deltas.json']) fs.copyFileSync(path.join(output, name), path.join(evidence, name));
  fs.copyFileSync(source, path.join(evidence, 'helper.c'));
  fs.copyFileSync(path.join(apple, 'SDKSettings.json'), path.join(evidence, 'SDKSettings.json'));
  const cap = read(capturePath);
  for (const ref of [...cap.headers, ...cap.external_headers]) {
    const dest = path.join(evidence, 'consumed-entities', ref.path.replace(/^\//, ''));
    fs.mkdirSync(path.dirname(dest), {recursive: true}); fs.copyFileSync(ref.path, dest);
  }
  state.phase = 'complete'; state.finished_at = new Date().toISOString(); state.compiler_native_launches = 0; save();
} catch (error) {state.failure = {message: error.message, stack: error.stack}; state.finished_at = new Date().toISOString(); save(); throw error;}
