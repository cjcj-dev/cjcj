#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {read, write, entity, dependencies, snapshot, requireValue} from './identity.mjs';

// Materialize an already authorized collection's original outputs. This entry
// does not authorize or execute clang, xcrun, a layout probe or a native target.
export function capture(spec, destination) {
  const root = fs.realpathSync(spec.apple_sdkroot);
  const raw = fs.readFileSync(spec.dependencies_path, 'utf8');
  const headers = [...new Set(dependencies(raw).map(p => fs.realpathSync(p)))]
    .filter(p => p.startsWith(root + path.sep)).sort().map(entity);
  const record = {kind: 'actual-header-layout-capture', apple_sdkroot: root,
    sdk_settings: entity(path.join(root, 'SDKSettings.json')), headers,
    external_headers: [...new Set(dependencies(raw).map(p => fs.realpathSync(p)))]
      .filter(p => !p.startsWith(root + path.sep)).sort().map(entity),
    tools: Object.fromEntries(Object.entries(spec.tools).map(([n, p]) => [n, entity(p)])),
    dependencies: entity(spec.dependencies_path), layout_evidence: entity(spec.layout_path),
    layout: spec.layout, xcode: spec.xcode, sdk_version: spec.sdk_version,
    source_ref: spec.batch, captured_at: spec.finished_at, qualification: null,
    collection: {argv: spec.argv, environment: spec.environment,
      started_at: spec.started_at, finished_at: spec.finished_at, batch: spec.batch,
      raw_outputs: spec.raw_outputs.map(entity)}};
  requireValue(spec.argv.some(argv => argv.includes('-isysroot') && argv[argv.indexOf('-isysroot') + 1] === root), 'capture-isysroot-argv');
  snapshot(root, record);
  write(destination, record);
  return record;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [spec, destination] = process.argv.slice(2);
  capture(read(spec), path.resolve(destination));
}
