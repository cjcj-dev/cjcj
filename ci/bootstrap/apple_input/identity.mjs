import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
export const write = (p, value) => fs.writeFileSync(p, JSON.stringify(value, null, 2) + '\n');
export const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
export function requireValue(ok, reason) {
  console.log(`CHECK ${reason} ${ok ? 'PASS' : 'REJECT'}`);
  if (!ok) throw new Error(reason);
}
export const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function entity(p) {
  requireValue(path.isAbsolute(p) && fs.statSync(p).isFile(), 'apple-entity-path');
  return {path: fs.realpathSync(p), sha256: hash(p)};
}
export function verify(ref, reason) {
  const actual = entity(ref.path);
  requireValue(equal(actual, ref), reason);
  return actual;
}

// The dependency list is the original clang -M output, not a guessed header list.
export function dependencies(raw) {
  const text = raw.replace(/\\\r?\n/g, ' ');
  requireValue(text.includes(': '), 'apple-dependency-format');
  return text.slice(text.indexOf(': ') + 2).match(/(?:\\.|[^\s])+/g)
    .map(s => s.replace(/\\(.)/g, '$1'));
}

// Derive the dependency invocation from the actual compilation, preserving
// every preprocessing option. No probe source or guessed header inventory.
export function dependencyArgv(argv) {
  requireValue(argv.filter(a => a === '-c').length === 1 &&
    argv.filter(a => a === '-o').length === 1, 'apple-consumer-command');
  const result = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '-o') { i++; continue; }
    result.push(argv[i] === '-c' ? '-M' : argv[i]);
  }
  return result;
}

function consumerSnapshot(capture, depPaths) {
  const consumer = capture.consumer;
  requireValue(consumer && path.isAbsolute(consumer.cwd) &&
    equal(consumer.environment, capture.collection.environment) &&
    path.resolve(consumer.cwd) === capture.collection.cwd,
  'apple-consumer-context');
  verify(consumer.source, 'apple-consumer-source-drift');
  requireValue(consumer.argv.filter(a => a === consumer.source.path).length === 1 &&
    consumer.argv[0] === capture.tools.clang.path &&
    equal(capture.collection.argv.filter(a => a[0] === capture.tools.clang.path),
      [dependencyArgv(consumer.argv)]), 'apple-consumer-dependency-command');
  requireValue(depPaths.map(p => fs.realpathSync(p)).includes(consumer.source.path),
    'apple-consumer-dependency-source');
  return consumer;
}

export function snapshot(root, capture) {
  const resolved = fs.realpathSync(root);
  requireValue(path.isAbsolute(root), 'apple-sdkroot-absolute');
  requireValue(capture.apple_sdkroot === resolved, 'header-isysroot');
  requireValue(capture.kind === 'actual-header-layout-capture' && capture.source_ref &&
    capture.captured_at && capture.xcode === 'Xcode 16.4\nBuild version 16F6\n' &&
    capture.sdk_version === '15.5', 'apple-capture-provenance');
  requireValue(capture.qualification === null, 'apple-qualification-null');
  const settings = entity(path.join(resolved, 'SDKSettings.json'));
  requireValue(equal(settings, capture.sdk_settings), 'apple-settings-drift');
  verify(capture.dependencies, 'apple-dependencies-drift');
  verify(capture.layout_evidence, 'apple-layout-drift');
  for (const ref of capture.collection.raw_outputs) verify(ref, 'apple-raw-output-drift');
  const depPaths = dependencies(fs.readFileSync(capture.dependencies.path, 'utf8'));
  const consumer = consumerSnapshot(capture, depPaths);
  const sdkPaths = depPaths.map(p => fs.realpathSync(p)).filter(p => p.startsWith(resolved + path.sep));
  const headers = capture.headers.map(ref => {
    requireValue(ref.path.startsWith(resolved + path.sep), 'header-isysroot');
    return verify(ref, 'apple-header-drift');
  });
  requireValue(equal([...new Set(sdkPaths)].sort(), headers.map(r => r.path).sort()), 'apple-header-closure');
  for (const rel of ['usr/include/signal.h', 'usr/include/sys/signal.h']) {
    requireValue(headers.some(r => r.path === fs.realpathSync(path.join(resolved, rel))), 'apple-required-header');
  }
  const tools = Object.fromEntries(Object.entries(capture.tools).map(([name, ref]) => [name, verify(ref, 'apple-tool-drift:' + name)]));
  requireValue(['clang', 'xcrun', 'xcodebuild'].every(n => tools[n]), 'apple-tool-set');
  requireValue(capture.collection.argv.length > 0 && capture.collection.batch === capture.source_ref &&
    capture.collection.started_at && capture.collection.finished_at, 'apple-collection-record');
  requireValue(capture.collection.argv.some(argv => argv[0] === tools.clang.path &&
    argv.includes('-isysroot') && argv[argv.indexOf('-isysroot') + 1] === resolved), 'capture-isysroot-argv');
  const external = capture.external_headers.map(ref => verify(ref, 'apple-external-header-drift'));
  requireValue(equal([...new Set(depPaths.map(p => fs.realpathSync(p)))].sort(),
    [...headers, ...external].map(r => r.path).sort()), 'apple-complete-dependencies');
  return {apple_sdkroot: resolved, sdk_settings: settings, headers, tools,
    external_headers: external, consumer,
    dependencies: capture.dependencies, layout_evidence: capture.layout_evidence,
    layout: capture.layout, source_ref: capture.source_ref, collection: capture.collection};
}

export function association(recipe, capture) {
  const actual = snapshot(recipe.inputs.apple_sdkroot, capture);
  requireValue(recipe.apple_sdkroot === actual.apple_sdkroot && equal(recipe.layout, actual.layout), 'header-isysroot');
  const argv = recipe.steps[0].argv;
  requireValue(argv.filter(x => x === '-isysroot').length === 1 &&
    argv[argv.indexOf('-isysroot') + 1] === actual.apple_sdkroot &&
    fs.realpathSync(recipe.inputs.clang) === actual.tools.clang.path &&
    argv[1] === recipe.inputs.clang, 'header-isysroot');
  const consumer = actual.consumer;
  const sourceIndex = argv.indexOf('-c') + 1;
  requireValue(sourceIndex > 0 && hash(argv[sourceIndex]) === consumer.source.sha256,
    'apple-consumer-source');
  // Preparation relocates the identical source to output/source. Only that
  // source operand and output operand may differ from collection compilation.
  const collected = dependencyArgv(consumer.argv);
  const consumed = dependencyArgv(argv.slice(1));
  consumed[consumed.indexOf('-M') + 1] = consumer.source.path;
  requireValue(equal(collected, consumed) &&
    fs.realpathSync(recipe.steps[0].cwd) === consumer.cwd &&
    equal(recipe.environment, consumer.environment), 'apple-consumer-binding');
  requireValue(equal(recipe.apple_input, actual), 'apple-input-drift');
  return actual;
}
