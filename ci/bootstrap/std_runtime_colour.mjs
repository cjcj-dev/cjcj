#!/usr/bin/env zx
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {colourExports, assertColourPair, nativeSymbols} from './native_libraries.mjs';
export function checkColour(args) {
  const options = {};
  for (let i=0; i<args.length; i++) {
    if (args[i] === '--runtime-only') options['runtime-only'] = true;
    else if (['--colour-runtime','--host-runtime','--std-colour','--runtime','--std','--source'].includes(args[i]) && args[i+1]) options[args[i].slice(2)] = args[++i];
    else throw new Error(`invalid colour argument ${args[i]}`);
  }
  if (!options['colour-runtime'] || !options['host-runtime']) throw new Error('colour/host runtime references required');
  const exports = colourExports(options['colour-runtime'], options['host-runtime']);
  if (options['runtime-only']) {
    if (options['std-colour'] || options.runtime || options.std || options.source) throw new Error('--runtime-only cannot be combined with std or pair arguments');
    console.log(`RUNTIME-COLOUR-OK colour_only_count=${exports.size}`);
  } else if (options['std-colour']) {
    if (options.runtime || options.std || options.source) throw new Error('--std-colour cannot be combined with pair arguments');
    console.log(Number(nativeSymbols(options['std-colour'], {archive:true}).some(symbol => symbol.type === 'U' && exports.has(symbol.name))));
  } else {
    if (!options.runtime || !options.std || !options.source) throw new Error('pair check requires --runtime, --std and --source');
    assertColourPair(options.runtime, options.std, options.source, exports, options['host-runtime']);
  }
  return 0;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = checkColour(process.argv.slice(2)); }
  catch (error) { console.error(`STD-RUNTIME-CHECK-FAIL ${error.message}`); process.exitCode = 1; }
}
