#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {read, write, hash} from './identity.mjs';
import {capture} from './capture.mjs';
import {prepare} from './prepare.mjs';
import {prelaunch} from './first-build.mjs';
import {expectHeaderRejection} from './offline-target.mjs';

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
const captures = {};
for (const name of ['A', 'B']) {
  const apple = path.join(root, 'SDK-' + name);
  put(path.join(apple, 'SDKSettings.json'), '{"Version":"15.5"}\n');
  put(path.join(apple, 'usr/include/signal.h'), '#include <sys/signal.h>\n');
  put(path.join(apple, 'usr/include/sys/signal.h'), 'SYNTHETIC_HEADER_BYTES\n');
  const deps = path.join(root, name + '.deps');
  put(deps, 'probe.o: ' + path.join(apple, 'usr/include/signal.h') + ' \\\n+ ' + path.join(apple, 'usr/include/sys/signal.h') + '\n');
  const layoutFile = path.join(root, name + '.layout'); put(layoutFile, JSON.stringify(layout));
  const raw = path.join(root, name + '.versions'); put(raw, 'SYNTHETIC_VERSION_OUTPUT_NOT_REAL_SDK');
  const spec = {apple_sdkroot: apple, dependencies_path: deps, layout_path: layoutFile,
    tools: {clang: tools.clang, xcrun: tools.xcrun, xcodebuild: tools.xcodebuild}, layout,
    xcode: 'Xcode 16.4\nBuild version 16F6\n', sdk_version: '15.5', batch: 'SYNTHETIC_TRANSPORT_ONLY-' + name,
    started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    argv: [[tools.clang, '-isysroot', apple, '-M', 'probe.c']], environment: {}, raw_outputs: [raw]};
  captures[name] = path.join(root, name + '.capture.json');
  capture(spec, captures[name]);
}
const environment = {HOME: root, TMPDIR: root, CANGJIE_HOME: sdk,
  PATH: sdk + '/bin:' + sdk + '/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  DYLD_LIBRARY_PATH: ['runtime/lib/darwin_aarch64_cjnative', 'lib/darwin_aarch64_cjnative', 'third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p)).join(':')};
const inputs = {kind: 'SYNTHETIC_TRANSPORT_ONLY', sdk_archive: archive, sdk_root: sdk, sdk_lock: lock,
  environment, apple_sdkroot: path.join(root, 'SDK-A'), layout, clang: tools.clang, sccache: tools.sccache,
  runner_platform: 'macOS', runner_available_cores: 2, jobs: 2};
const legacyDir = path.join(input, 'legacy');
const firstBuild = fileURLToPath(new URL('./first-build.mjs', import.meta.url));
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
const normal = recipe('normal');
runCase('normal', () => {
  const a = auth(normal);
  let result;
  for (let step = 0; step < 2; step++) result = prelaunch(normal, a, legacyDir, step, archiveHash);
  if (result.status !== 'AUTHORIZED_BOUNDARY_NOT_LAUNCHED' || result.step !== 1) throw new Error('boundary-result');
  return result;
}, null);
runCase('same-version-wrong-root', () => recipe('wrong-root', captures.A, {...inputs, apple_sdkroot: path.join(root, 'SDK-B')}), 'header-isysroot');
const drift = recipe('drift');
const header = path.join(root, 'SDK-A/usr/include/sys/signal.h');
const bytes = fs.readFileSync(header);
fs.appendFileSync(header, 'CHANGED_ONLY_CONSUMED_HEADER');
runCase('post-prepare-header-drift', () => expectHeaderRejection(prelaunch, [drift, auth(drift), legacyDir, 0, archiveHash]), null);
// Candidate-new consumer cut: same recipe, same byte mutation, same test target.
// The expected rejection disappears at the actual prelaunch association call.
try {
  const text = before.toString();
  if (!text.includes('  association(recipe, capture);')) throw new Error('cut-anchor');
  fs.writeFileSync(firstBuild, text.replace('  association(recipe, capture);', '  // controlled consumer cut: association omitted'));
  fs.writeFileSync(path.join(root, 'consumer-cut.diff'), '--- first-build.mjs\n+++ first-build.mjs\n@@\n-  association(recipe, capture);\n+  // controlled consumer cut: association omitted\n');
  const target = new URL('./offline-target.mjs', import.meta.url).href;
  const code = `import {prelaunch} from ${JSON.stringify(pathToFileURL(firstBuild).href)}; import {expectHeaderRejection} from ${JSON.stringify(target)}; expectHeaderRejection(prelaunch, ${JSON.stringify([drift, auth(drift), legacyDir, 0, archiveHash])});`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', code], {encoding: 'utf8'});
  fs.writeFileSync(path.join(root, 'cut.stdout'), result.stdout ?? '');
  fs.writeFileSync(path.join(root, 'cut.stderr'), result.stderr ?? '');
  process.stdout.write(result.stdout ?? '');
  const targetRc = result.status;
  results.push({name: 'consumer-cut', status: 'ran', rc: targetRc, expected: 'apple-header-drift',
    observed: result.stdout, target_reached: true, ok: targetRc === 1, entry_sha256: hash(firstBuild)});
  write(path.join(root, 'cut.rc.json'), {rc: targetRc});
  if (targetRc !== 1 || !result.stdout.includes('TARGET_ASSERTION apple-header-drift actual=AUTHORIZED_BOUNDARY_NOT_LAUNCHED FAIL') ||
    !result.stderr.includes('TARGET_ASSERTION:apple-header-drift')) throw new Error('cut-not-causal');
} finally {fs.writeFileSync(firstBuild, before); fs.writeFileSync(header, bytes);}
runCase('restored', () => {
  const a = auth(drift); let result;
  for (let step = 0; step < 2; step++) result = prelaunch(drift, a, legacyDir, step, archiveHash);
  return result;
}, null);
write(path.join(root, 'results.json'), {kind: 'SYNTHETIC_TRANSPORT_ONLY', results, beforeHash,
  restoredHash: hash(firstBuild), launch_count: 0, qualification: null});
if (hash(firstBuild) !== beforeHash || results.length !== 5 || results.some(r => !r.ok)) throw new Error('batch-result');
console.log('OFFLINE_TARGETS_COMPLETE recipes=5 compiler_native_launches=0');
