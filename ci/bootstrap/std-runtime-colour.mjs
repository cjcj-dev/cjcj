#!/usr/bin/env zx
// One std/runtime export-difference predicate for the formal native consumers.
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {execute, fileDigest} from './sdk-io.mjs';
import {sdkPlatform} from './sdk-platform.mjs';

export function nativeSymbol(name, platform) {
  name = name.split('@', 1)[0];
  if (sdkPlatform(platform).os === 'darwin' && name.startsWith('_')) return name.slice(1);
  if (sdkPlatform(platform).os === 'win32' && name.startsWith('__imp_')) return name.slice(6);
  return name;
}
export async function nativeSymbolRows(file, {platform, runtime = false, defined = runtime,
  nm = 'nm', readobj = 'llvm-readobj'} = {}) {
  const {os} = sdkPlatform(platform);
  const found = [];
  if (runtime && os === 'win32') {
    const {stdout} = await execute(readobj, ['--coff-exports', file], {maxBuffer: 64 * 1024 * 1024});
    for (const match of stdout.matchAll(/^\s*Name: (\S+)\s*$/gm)) found.push(nativeSymbol(match[1], platform));
    return found;
  }
  const args = runtime ? os === 'darwin' ? ['-gU'] : ['-D', '--defined-only']
    : defined ? ['-A', '--defined-only'] : ['-A'];
  const {stdout} = await execute(nm, [...args, file], {maxBuffer: 64 * 1024 * 1024});
  for (const line of stdout.split('\n')) {
    const fields = line.trim().split(/\s+/);
    const kind = fields.at(-2), name = fields.at(-1);
    if (!kind || !/^[A-Za-z?]$/.test(kind)) continue;
    if ((defined && !['U', 'w', 'v'].includes(kind)) || (!defined && kind === 'U'))
      found.push(nativeSymbol(name, platform));
  }
  return found;
}
export async function nativeSymbols(file, options) {
  return new Set(await nativeSymbolRows(file, options));
}
const difference = (left, right) => new Set([...left].filter(name => !right.has(name)));

export async function verifyStdRuntimePair({colourRuntime, hostRuntime, runtime, std, source, platform, tools = {}}) {
  const [colourExports, hostExports] = await Promise.all([colourRuntime, hostRuntime]
    .map(file => nativeSymbols(file, {platform, runtime: true, ...tools})));
  const exports = difference(colourExports, hostExports);
  console.error(`STD-COLOUR-EXPORTS colour_runtime=${colourRuntime} colour_runtime_sha256=${await fileDigest(colourRuntime)} host_runtime=${hostRuntime} host_runtime_sha256=${await fileDigest(hostRuntime)} colour_only=${[...exports].sort().join(',') || 'none'}`);
  if (!exports.size) throw new Error('empty colour-only runtime export set');
  const [runtimeExports, stdImports] = await Promise.all([
    nativeSymbols(runtime, {platform, runtime: true, ...tools}), nativeSymbols(std, {platform, ...tools})]);
  const runtimeHits = difference(runtimeExports, hostExports);
  const stdHits = new Set([...stdImports].filter(name => exports.has(name)));
  const detail = `runtime=${runtime} runtime_sha256=${await fileDigest(runtime)} std=${std} std_sha256=${await fileDigest(std)} std_source=${source} runtime_symbols=${[...runtimeHits].sort().join(',') || 'none'} std_symbols=${[...stdHits].sort().join(',') || 'none'}`;
  if (Boolean(runtimeHits.size) !== Boolean(stdHits.size)) throw new Error(`STD-RUNTIME-COLOUR-MISMATCH ${detail}`);
  console.log(`STD-RUNTIME-PAIR-OK ${detail}`);
  return {colourOnly: [...exports].sort(), runtimeHits: [...runtimeHits].sort(), stdHits: [...stdHits].sort()};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const names = ['colour-runtime', 'host-runtime', 'runtime', 'std', 'source', 'platform'];
    const {values} = parseArgs({options: Object.fromEntries(names.map(name => [name, {type: 'string'}]))});
    if (names.some(name => !values[name])) throw new Error(`required: ${names.map(name => '--' + name).join(' ')}`);
    await verifyStdRuntimePair({colourRuntime: values['colour-runtime'], hostRuntime: values['host-runtime'],
      runtime: values.runtime, std: values.std, source: values.source, platform: values.platform});
  } catch (error) { console.error(`STD-RUNTIME-CHECK-FAIL ${error.message}`); process.exitCode = 1; }
}
