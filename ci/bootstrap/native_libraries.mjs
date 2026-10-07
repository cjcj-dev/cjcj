#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {nativeHost, execute} from './host_tools.mjs';
import {sha256File} from './sdk_verify.mjs';

export function nativeSymbols(file, {runtime = false, defined = false, archive = false} = {}) {
  const native = nativeHost();
  const args = native.os === 'darwin' ? ['nm', '-g', ...(defined || runtime ? ['-U'] : []), ...(archive ? ['-A'] : []), file] : [...(runtime ? ['-D'] : []), ...(defined || runtime ? ['--defined-only'] : []), ...(archive ? ['-A'] : []), file];
  const output = native.os === 'darwin' ? execute('xcrun', args).stdout : execute('nm', args).stdout;
  return output.split(/\r?\n/).map(line => {
    const fields = line.trim().split(/\s+/), type = fields.at(-2);
    let name = (fields.at(-1) || '').split('@', 1)[0];
    if (native.os === 'darwin' && name.startsWith('_')) name = name.slice(1);
    return {type, name, line};
  }).filter(symbol => /^[A-Za-z?]$/.test(symbol.type || '') && (!runtime || !['U','w','v'].includes(symbol.type)));
}
export function runtimeDir(root) {
  const native = nativeHost();
  if (fs.existsSync(path.join(root, native.runtimeLibrary))) return fs.realpathSync(root);
  const file = findFiles(root, name => name === native.runtimeLibrary)[0];
  return file ? path.dirname(fs.realpathSync(file)) : fs.realpathSync(root);
}
export function findFiles(root, predicate, maxDepth = Infinity, follow = false) {
  const files = [], seen = new Set();
  function visit(dir, depth) {
    if (depth >= maxDepth) return;
    const real = fs.realpathSync(dir);
    if (seen.has(real)) return;
    seen.add(real);
    for (const item of fs.readdirSync(dir, {withFileTypes:true})) {
      const file = path.join(dir, item.name);
      const stat = follow ? fs.statSync(file) : fs.lstatSync(file);
      if (stat.isDirectory()) visit(file, depth + 1);
      else if ((stat.isFile() || stat.isSymbolicLink()) && predicate(item.name, file)) files.push(file);
    }
  }
  if (fs.existsSync(root)) visit(root, 0);
  return files.sort();
}
export function tuplePayloads(native = nativeHost()) {
  return ['MANIFEST', 'bin/llc', 'bin/opt', `bin/${native.linker}`, 'lib/STATIC_LLVM.txt', 'fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/llc.gz', 'fixed-llc/opt.gz', `fixed-llc/${native.linker}.gz`, 'fixed-llc/llvm-tools.manifest'];
}
export function validateTuple(tuple) {
  const native = nativeHost(), sums = path.join(tuple, 'SHA256SUMS');
  if (!fs.existsSync(sums)) throw new Error(`llvm-tuple 缺 SHA256SUMS: ${tuple}`);
  const lines = fs.readFileSync(sums, 'utf8').split('\n');
  if (lines.at(-1) === '') lines.pop();
  const entries = lines.map(line => {
    const match = /^([0-9a-fA-F]{64})  \.\/(.+)$/.exec(line);
    if (!match || match[2].startsWith('/') || match[2].split('/').includes('..')) throw new Error('llvm-tuple SHA256SUMS 格式或相对路径非法');
    return [match[1], match[2]];
  });
  if (entries.length !== 10) throw new Error(`llvm-tuple SHA256SUMS 必须且只能登记 10 个 payload: entries=${entries.length}`);
  const names = new Set(entries.map(([,rel]) => rel));
  for (const rel of tuplePayloads(native)) if (!names.has(rel) || !fs.existsSync(path.join(tuple, rel))) throw new Error(`llvm-tuple 缺或未登记 ${rel}`);
  // Strict digest check replaces GNU/BSD sha command differences, without
  // accepting a wrong file or substituting a different manifest.
  for (const [expected,rel] of entries) if (sha256File(path.join(tuple,rel)) !== expected) throw new Error(`llvm-tuple SHA256SUMS strict 校验失败: ${rel}`);
  console.log('ASSERT colour-tuple-sums ruler=sha256sum--strict status=ok file=' + sums);
  return entries;
}
export function colourExports(colour, host) {
  const exports = new Set(nativeSymbols(colour, {runtime:true}).map(symbol => symbol.name));
  for (const symbol of nativeSymbols(host, {runtime:true})) exports.delete(symbol.name);
  console.error(`STD-COLOUR-EXPORTS colour_runtime=${colour} colour_runtime_sha256=${sha256File(colour)} host_runtime=${host} host_runtime_sha256=${sha256File(host)} colour_only=${[...exports].sort().join(',') || 'none'}`);
  if (!exports.size) throw new Error('empty colour-only runtime export set');
  return exports;
}
export function assertColourPair(runtime, std, source, exports, host) {
  const hostSymbols = new Set(nativeSymbols(host, {runtime:true}).map(symbol => symbol.name));
  const rtHits = nativeSymbols(runtime, {runtime:true}).map(symbol => symbol.name).filter(name => !hostSymbols.has(name));
  const stdHits = nativeSymbols(std, {archive:true}).filter(symbol => symbol.type === 'U' && exports.has(symbol.name)).map(symbol => symbol.name);
  const detail = `runtime=${runtime} runtime_sha256=${sha256File(runtime)} std=${std} std_sha256=${sha256File(std)} std_source=${source} runtime_symbols=${[...new Set(rtHits)].sort().join(',') || 'none'} std_symbols=${[...new Set(stdHits)].sort().join(',') || 'none'}`;
  if (!!rtHits.length !== !!stdHits.length) throw new Error(`STD-RUNTIME-COLOUR-MISMATCH ${detail}`);
  console.log('STD-RUNTIME-PAIR-OK ' + detail);
}
