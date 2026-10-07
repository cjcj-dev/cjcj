#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {read, write, entity, snapshot, association, requireValue} from './identity.mjs';
import {legacy} from './legacy.mjs';

export function prepare(source, output, inputs, legacyDirectory, capturePath, transportArchive = null) {
  requireValue(transportArchive === null || inputs.kind === 'SYNTHETIC_TRANSPORT_ONLY', 'transport-label');
  legacy(legacyDirectory, 'prepare', [source, output, inputs], transportArchive);
  const recipePath = path.join(output, 'build-recipe.json');
  const recipe = read(recipePath);
  const capture = read(capturePath);
  recipe.header_capture = entity(capturePath);
  recipe.apple_input = snapshot(inputs.apple_sdkroot, capture);
  association(recipe, capture);
  recipe.kind = transportArchive === null ? 'PREPARED_NOT_AUTHORIZED' : 'SYNTHETIC_TRANSPORT_ONLY';
  recipe.qualification = null;
  write(recipePath, recipe);
  return recipe;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [source, output, inputs, legacyDirectory, capture] = process.argv.slice(2);
  prepare(path.resolve(source), path.resolve(output), read(inputs), path.resolve(legacyDirectory), path.resolve(capture));
}
