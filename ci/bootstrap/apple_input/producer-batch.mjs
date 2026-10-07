#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {read, write, hash} from './identity.mjs';
import {capture} from './capture.mjs';
import {prepare} from './prepare.mjs';
import {prelaunch} from './first-build.mjs';
import {expectCaptureRejection} from './producer-target.mjs';

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
const captures = {}, specs = {};
for (const name of ['A', 'B']) {
  const apple = path.join(root, 'SDK-' + name);
  put(path.join(apple, 'SDKSettings.json'), '{"Version":"15.5"}\n');
  put(path.join(apple, 'usr/include/signal.h'), '#include <sys/signal.h>\n');
  put(path.join(apple, 'usr/include/sys/signal.h'), 'SYNTHETIC_HEADER_BYTES\n');
  const deps = path.join(root, name + '.deps');
  put(deps, 'probe.o: ' + path.join(apple, 'usr/include/signal.h') + ' \\\n ' + path.join(apple, 'usr/include/sys/signal.h') + '\n');
  const layoutFile = path.join(root, name + '.layout'); put(layoutFile, JSON.stringify(layout));
  const raw = path.join(root, name + '.versions'); put(raw, 'SYNTHETIC_VERSION_OUTPUT_NOT_REAL_SDK');
  const spec = {apple_sdkroot: apple, dependencies_path: deps, layout_path: layoutFile,
    tools: {clang: tools.clang, xcrun: tools.xcrun, xcodebuild: tools.xcodebuild}, layout,
    xcode: 'Xcode 16.4\nBuild version 16F6\n', sdk_version: '15.5', batch: 'SYNTHETIC_TRANSPORT_ONLY-' + name,
    started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    argv: [[tools.clang, '-isysroot', apple, '-M', 'probe.c']], environment: {}, raw_outputs: [raw]};
  captures[name] = path.join(root, name + '.capture.json');
  specs[name] = spec;
  capture(spec, captures[name]);
}
const environment = {HOME: root, TMPDIR: root, CANGJIE_HOME: sdk,
  PATH: sdk + '/bin:' + sdk + '/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  DYLD_LIBRARY_PATH: ['runtime/lib/darwin_aarch64_cjnative', 'lib/darwin_aarch64_cjnative', 'third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p)).join(':')};
const inputs = {kind: 'SYNTHETIC_TRANSPORT_ONLY', sdk_archive: archive, sdk_root: sdk, sdk_lock: lock,
  environment, apple_sdkroot: path.join(root, 'SDK-A'), layout, clang: tools.clang, sccache: tools.sccache,
  runner_platform: 'macOS', runner_available_cores: 2, jobs: 2};
const legacyDir = path.join(input, 'legacy');
const firstBuild = fileURLToPath(new URL('./capture.mjs', import.meta.url));
const before = fs.readFileSync(firstBuild);
const beforeHash = hash(firstBuild);

function runCase(name, fn, wanted) {
  let rc = 0, reason = null, observed;
  try {observed = fn();} catch (error) {reason = error.message; rc = 2;}
  const ok = rc === (wanted ? 2 : 0) && reason === wanted;
  console.log(`TARGET_ASSERTION ${name} expected=${wanted ?? 'BOUNDARY'} actual=${reason ?? observed?.status} ${ok ? 'PASS' : 'FAIL'}`);
  results.push({name, status: 'ran', rc, expected: wanted, reason, target_reached: true, ok,
    observed: observed ?? null, entry_sha256: hash(firstBuild)});
  write(path.join(root, 'results.json'), {kind: 'SYNTHETIC_TRANSPORT_ONLY', results, beforeHash});
  if (!ok) throw new Error('first-error-stop:' + name);
}
function recipe(name, captureFile = captures.A, inps = inputs) {
  const output = path.join(root, name);
  prepare(path.join(input, 'source'), output, inps, legacyDir, captureFile, archiveHash);
  return path.join(output, 'build-recipe.json');
}
function auth(p) {
  const r = read(p);
  return {stage: 'offline-launch-boundary', count: 1, recipe_sha256: hash(p), source_head: r.source_head,
    input_manifest_sha256: r.input_manifest_sha256, archive_reserve_seconds: 30,
    absolute_deadline_epoch: Date.now() / 1000 + 600, new_batch_id: read(r.header_capture.path).source_ref};
}
const negative = {...specs.A, dependencies_path: path.join(root, 'missing-required.deps')};
put(negative.dependencies_path, 'probe.o: ' + path.join(root, 'SDK-A/usr/include/signal.h') + '\n');
const destination = path.join(root, 'negative.capture.json');
// Candidate-new producer cut: omit validation immediately before manifest write.
try {
  const anchor = '  snapshot(root, record);';
  if (!before.toString().includes(anchor)) throw new Error('cut-anchor');
  fs.writeFileSync(firstBuild, before.toString().replace(anchor, '  // controlled producer cut: snapshot omitted'));
  fs.writeFileSync(path.join(root, 'producer-cut.diff'), 'diff --git a/ci/bootstrap/apple_input/capture.mjs b/ci/bootstrap/apple_input/capture.mjs\n--- a/ci/bootstrap/apple_input/capture.mjs\n+++ b/ci/bootstrap/apple_input/capture.mjs\n@@ -26 +26 @@\n-  snapshot(root, record);\n+  // controlled producer cut: snapshot omitted\n');
  const code = `import {capture} from ${JSON.stringify(pathToFileURL(firstBuild).href)}; import {expectCaptureRejection} from ${JSON.stringify(new URL('./producer-target.mjs', import.meta.url).href)}; expectCaptureRejection(capture, ${JSON.stringify(negative)}, ${JSON.stringify(destination)});`;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', code], {encoding: 'utf8'});
  put(path.join(root, 'cut.stdout'), child.stdout ?? ''); put(path.join(root, 'cut.stderr'), child.stderr ?? '');
  process.stdout.write(child.stdout ?? '');
  results.push({name: 'producer-cut', rc: child.status, status: 'ran', entry_sha256: hash(firstBuild),
    ok: child.status === 1 && child.stdout.includes('TARGET_ASSERTION apple-required-header actual=CAPTURE_WRITTEN FAIL') && child.stderr.includes('TARGET_ASSERTION:apple-required-header')});
  write(path.join(root, 'results.json'), {results, beforeHash});
  if (!results.at(-1).ok) throw new Error('cut-not-causal');
} finally {fs.writeFileSync(firstBuild, before); fs.rmSync(destination, {force: true});}
runCase('producer-restored', () => {
  expectCaptureRejection(capture, negative, destination);
  capture(specs.A, captures.A);
  const r = recipe('restored'); let value;
  for (let step = 0; step < 2; step++) value = prelaunch(r, auth(r), legacyDir, step, archiveHash);
  if (value.step !== 1 || value.status !== 'AUTHORIZED_BOUNDARY_NOT_LAUNCHED') throw new Error('boundary-result');
  return value;
}, null);
function driftTarget(file, reason, r) {
  const bytes = fs.readFileSync(file); let actual = null, value = null;
  try {
    fs.appendFileSync(file, 'ONLY_THIS_ENTITY_CHANGED');
    try {value = prelaunch(r, auth(r), legacyDir, 0, archiveHash);} catch (e) {actual = e.message;}
    const ok = actual === reason && value === null;
    console.log(`TARGET_ASSERTION ${reason} actual=${actual ?? value?.status} ${ok ? 'PASS' : 'FAIL'}`);
    if (!ok) throw new Error('TARGET_ASSERTION:' + reason);
    return {reason: actual, admitted: value};
  } finally {fs.writeFileSync(file, bytes);}
}
const settingsRecipe = recipe('settings');
runCase('settings-drift', () => driftTarget(path.join(root, 'SDK-A/SDKSettings.json'), 'apple-settings-drift', settingsRecipe), null);
const toolsRecipe = recipe('tools-raw');
runCase('tools-raw-output-drift', () => {
  // One recipe, two independently restored entity checks; neither launches.
  const tool = driftTarget(tools.xcrun, 'apple-tool-drift:xcrun', toolsRecipe);
  const raw = driftTarget(specs.A.raw_outputs[0], 'apple-raw-output-drift', toolsRecipe);
  return {tool, raw};
}, null);
write(path.join(root, 'results.json'), {kind: 'SYNTHETIC_TRANSPORT_ONLY', results, beforeHash,
  restoredHash: hash(firstBuild), qualification: null});
if (hash(firstBuild) !== beforeHash || results.length !== 4 || results.some(r => !r.ok)) throw new Error('batch-result');
console.log('PRODUCER_TARGETS_COMPLETE recipes=4 compiler_native_dispatch=absent');
