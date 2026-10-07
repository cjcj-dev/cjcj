#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {read, write, hash} from './identity.mjs';
import {capture} from './capture.mjs';
import {prepare, bindPrepared} from './prepare.mjs';
import {prelaunch} from './first-build.mjs';
import {dependencyArgv} from './identity.mjs';

const [rootArg, inputArg] = process.argv.slice(2);
const root = path.resolve(rootArg), input = path.resolve(inputArg);
fs.mkdirSync(root, {recursive: false});
fs.writeFileSync(path.join(root, 'batch-started'), new Date().toISOString());
const results = [];
const put = (p, text) => {fs.mkdirSync(path.dirname(p), {recursive: true}); fs.writeFileSync(p, text);};
const sdk = path.join(root, 'cangjie');
const names = ['bin/cjc', 'tools/bin/cjpm', 'lib/darwin_aarch64_cjnative/libstd.core.a',
  'runtime/lib/darwin_aarch64_cjnative/libcangjie-runtime.dylib',
  'runtime/lib/darwin_aarch64_cjnative/libboundscheck.dylib', 'third_party/llvm/lib/libLLVM.dylib'];
for (const n of names) {put(path.join(sdk, n), 'SYNTHETIC_TRANSPORT_ONLY_NOT_EXECUTABLE ' + n); fs.chmodSync(path.join(sdk, n), 0o755);}
const archive = path.join(root, 'SYNTHETIC.tar');
execFileSync('tar', ['-cf', archive, '-C', root, 'cangjie']);
const archiveHash = hash(archive);
const lock = path.join(root, 'SDK.lock');
write(lock, {archive_sha256: archiveHash, files: Object.fromEntries(names.map(n => [n, hash(path.join(sdk, n))]))});
const toolDir = path.join(root, 'tools');
const tools = Object.fromEntries(['clang', 'xcrun', 'xcodebuild', 'sccache'].map(n => {
  const p = path.join(toolDir, n); put(p, 'SYNTHETIC_TRANSPORT_ONLY_NOT_EXECUTABLE ' + n); fs.chmodSync(p, 0o755); return [n, p];
}));
const layout = {stack_size: 131072, flags: 0};
// Synthetic entities, real pinned helper and prepare/admission entries. No tools launch.
const apple = path.join(root, 'SDK-A');
put(path.join(apple, 'SDKSettings.json'), '{"Version":"15.5"}\n');
const environment = {HOME: root, TMPDIR: root, CANGJIE_HOME: sdk,
  PATH: sdk + '/bin:' + sdk + '/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  DYLD_LIBRARY_PATH: ['runtime/lib/darwin_aarch64_cjnative', 'lib/darwin_aarch64_cjnative', 'third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p)).join(':')};
const inputs = {kind: 'SYNTHETIC_TRANSPORT_ONLY', sdk_archive: archive, sdk_root: sdk, sdk_lock: lock,
  environment, apple_sdkroot: apple, layout, clang: tools.clang, sccache: tools.sccache,
  runner_platform: 'macOS', runner_available_cores: 2, jobs: 2};
const legacyDir = path.join(input, 'legacy');
const output = path.join(root, 'prepared');
const unbound = prepare(path.join(input, 'source'), output, inputs, legacyDir, null, archiveHash);
const recipePath = path.join(output, 'build-recipe.json');
const compilation = unbound.steps[0].argv.slice(1);
const source = compilation[compilation.indexOf('-c') + 1];
// Preserve an explicitly synthetic dependency output covering this helper's
// actual direct includes plus signal.h's sys/signal.h. This is not clang evidence.
const includeNames = [...fs.readFileSync(source, 'utf8').matchAll(/^#include <([^>]+)>/gm)].map(m => m[1]);
includeNames.push('sys/signal.h');
const headerPaths = includeNames.map(n => path.join(apple, 'usr/include', n));
for (const p of headerPaths) put(p, 'SYNTHETIC_HEADER_NOT_REAL_SDK ' + p + '\n');
const deps = path.join(root, 'helper.deps');
put(deps, 'helper.o: ' + [source, ...headerPaths].join(' ') + '\n');
const layoutFile = path.join(root, 'layout.json'); put(layoutFile, JSON.stringify(layout));
const raw = path.join(root, 'tool-output'); put(raw, 'SYNTHETIC_NOT_TOOL_EXECUTION');
const capturePath = path.join(root, 'capture.json');
capture({apple_sdkroot: apple, dependencies_path: deps, layout_path: layoutFile,
  tools: {clang: tools.clang, xcrun: tools.xcrun, xcodebuild: tools.xcodebuild}, layout,
  xcode: 'Xcode 16.4\nBuild version 16F6\n', sdk_version: '15.5', batch: 'SYNTHETIC-HELPER-CONSUMER',
  started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
  argv: [dependencyArgv(compilation)], cwd: unbound.steps[0].cwd, environment,
  consumer: {source, argv: compilation, cwd: unbound.steps[0].cwd, environment}, raw_outputs: [raw]}, capturePath);
bindPrepared(recipePath, capturePath, legacyDir, archiveHash);
const originalRecipe = fs.readFileSync(recipePath);
const entry = fileURLToPath(new URL('./first-build.mjs', import.meta.url));
const entryBytes = fs.readFileSync(entry);
const target = fileURLToPath(new URL('./consumer-target.mjs', import.meta.url));
function auth() {
  const r = read(recipePath);
  return {stage: 'offline-launch-boundary', count: 1, recipe_sha256: hash(recipePath), source_head: r.source_head,
    input_manifest_sha256: r.input_manifest_sha256, archive_reserve_seconds: 30,
    absolute_deadline_epoch: Number(process.env.APPLE_BATCH_DEADLINE), new_batch_id: read(capturePath).source_ref};
}
function run(name, expected, wantedRc = 0) {
  const code = `import {prelaunch} from ${JSON.stringify(pathToFileURL(entry).href)};
    import {assertAdmission} from ${JSON.stringify(pathToFileURL(target).href)};
    assertAdmission(prelaunch, ${JSON.stringify([recipePath, auth(), legacyDir, archiveHash])}, ${JSON.stringify(expected)});`;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', code], {encoding: 'utf8'});
  put(path.join(root, name + '.stdout'), child.stdout ?? '');
  put(path.join(root, name + '.stderr'), child.stderr ?? '');
  process.stdout.write(child.stdout ?? ''); process.stderr.write(child.stderr ?? '');
  const ok = child.status === wantedRc && child.stdout.includes('TARGET_ASSERTION ' + expected + ' ') &&
    child.stdout.includes(wantedRc === 0 ? ' PASS' : ' FAIL');
  results.push({name, rc: child.status, signal: child.signal, error: child.error?.message ?? null,
    expected, ok, entry_sha256: hash(entry), target_sha256: hash(target), recipe_sha256: hash(recipePath),
    capture_sha256: hash(capturePath)});
  write(path.join(root, 'results.json'), {kind: 'SYNTHETIC_TRANSPORT_ONLY', results});
  if (!ok) throw new Error('first-error-stop:' + name);
}
run('green', 'BOUNDARY');
const header = path.join(apple, 'usr/include/pthread.h');
const headerBytes = fs.readFileSync(header);
try {
  fs.appendFileSync(header, 'CHANGED_ONLY_PTHREAD_HEADER');
  run('header-drift', 'apple-header-drift');
} finally {fs.writeFileSync(header, headerBytes);}
run('header-restored', 'BOUNDARY');
try {
  const recipe = read(recipePath);
  const changedHome = path.join(root, 'other-valid-home'); fs.mkdirSync(changedHome);
  recipe.environment.HOME = changedHome; recipe.inputs.environment.HOME = changedHome;
  write(recipePath, recipe);
  run('environment-drift', 'apple-consumer-binding');
} finally {fs.writeFileSync(recipePath, originalRecipe);}
run('environment-restored', 'BOUNDARY');
try {
  fs.appendFileSync(header, 'CHANGED_ONLY_PTHREAD_HEADER');
  const text = entryBytes.toString();
  if (!text.includes('  association(recipe, capture);')) throw new Error('cut-anchor');
  fs.writeFileSync(entry, text.replace('  association(recipe, capture);', '  // controlled consumer cut'));
  put(path.join(root, 'consumer-cut.diff'), 'diff --git a/ci/bootstrap/apple_input/first-build.mjs b/ci/bootstrap/apple_input/first-build.mjs\n--- a/ci/bootstrap/apple_input/first-build.mjs\n+++ b/ci/bootstrap/apple_input/first-build.mjs\n@@ -20,1 +20,1 @@\n-  association(recipe, capture);\n+  // controlled consumer cut\n');
  run('consumer-cut', 'apple-header-drift', 1);
} finally {fs.writeFileSync(entry, entryBytes); fs.writeFileSync(header, headerBytes);}
write(path.join(root, 'results.json'), {kind: 'SYNTHETIC_TRANSPORT_ONLY', results,
  restored_entry_sha256: hash(entry), restored_header_sha256: hash(header),
  original_header_sha256: hashBuffer(headerBytes), qualification: null, compiler_native_launches: 0});
function hashBuffer(bytes) {return execFileSync('sha256sum', {input: bytes, encoding: 'utf8'}).split(' ')[0];}
if (results.length !== 6 || results.some(r => !r.ok) || hash(entry) !== hashBuffer(entryBytes)) throw new Error('batch-result');
console.log('CONSUMER_TARGETS_COMPLETE recipes=6 compiler_native_launches=0');
