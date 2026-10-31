#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {read, hash, verify, association, requireValue} from './identity.mjs';
import {legacy} from './legacy.mjs';

export function prelaunch(recipePath, authorization, legacyDirectory, step, transportArchive = null) {
  const recipe = read(recipePath);
  requireValue(transportArchive === null || recipe.kind === 'SYNTHETIC_TRANSPORT_ONLY', 'transport-label');
  requireValue(authorization.stage === 'offline-launch-boundary' && authorization.count === 1 &&
    authorization.recipe_sha256 === hash(recipePath) && authorization.source_head === recipe.source_head &&
    authorization.input_manifest_sha256 === recipe.input_manifest_sha256 &&
    recipe.input_manifest_sha256 === hash(path.join(path.dirname(recipePath), 'input-manifest.json')), 'build-authorization-binding');
  requireValue(authorization.archive_reserve_seconds >= 30 &&
    Date.now() / 1000 < authorization.absolute_deadline_epoch - authorization.archive_reserve_seconds, 'build-deadline');
  verify(recipe.header_capture, 'apple-capture-drift');
  const capture = read(recipe.header_capture.path);
  requireValue(authorization.new_batch_id === capture.source_ref, 'new-header-batch');
  legacy(legacyDirectory, 'prelaunch', [recipePath], transportArchive);
  association(recipe, capture);
  requireValue(Number.isInteger(step) && step >= 0 && step < recipe.steps.length, 'build-step');
  // This is the actual admission result passed to the future launcher. No
  // compiler/native dispatch exists until the separate first-build contract.
  const admitted = {status: 'AUTHORIZED_BOUNDARY_NOT_LAUNCHED', step, argv: recipe.steps[step].argv,
    environment: recipe.environment, apple_input: recipe.apple_input, qualification: null};
  console.log('LAUNCH_BOUNDARY ' + JSON.stringify(admitted));
  return admitted;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [recipe, authorization, legacyDirectory, step = '0'] = process.argv.slice(2);
  prelaunch(path.resolve(recipe), read(authorization), path.resolve(legacyDirectory), Number(step));
}
