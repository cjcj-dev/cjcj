#!/usr/bin/env zx
// Bind a completed std installation to its actual source and compiler producer.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const sha = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const metadata = new Set(['std-producer.json', 'STDLIB_SOURCE_SHA', '.std-production.json']);
function sourceIdentity(source) {
  const git = (...args) => execFileSync('git', ['-C', source, ...args], {encoding: 'utf8'}).trim();
  const root = git('rev-parse', '--show-toplevel');
  const relative = path.relative(root, fs.realpathSync(source));
  if (!relative || relative.startsWith('..')) throw Error('STD_SOURCE_LOCATION_INVALID');
  if (git('status', '--porcelain', '--', relative)) throw Error('STD_SOURCE_DIRTY');
  return {source_commit: git('rev-parse', 'HEAD'), source_tree: git('rev-parse', `HEAD:${relative}`)};
}
export function prefixInventory(prefix) {
  const entries = [];
  function walk(relative) {
    for (const name of fs.readdirSync(path.join(prefix, relative)).sort()) {
      if (!relative && metadata.has(name)) continue;
      const item = path.posix.join(relative, name);
      const full = path.join(prefix, item);
      const stat = fs.lstatSync(full);
      if (stat.isSymbolicLink()) {
        const resolved = fs.realpathSync(full);
        const inside = path.relative(fs.realpathSync(prefix), resolved);
        if (inside === '..' || inside.startsWith(`..${path.sep}`) || path.isAbsolute(inside)) throw Error('STD_PREFIX_EXTERNAL_LINK');
        entries.push({path: item, type: 'symlink', target: fs.readlinkSync(full)});
      } else if (stat.isDirectory()) {
        entries.push({path: item, type: 'directory'});
        walk(item);
      } else if (stat.isFile()) {
        entries.push({path: item, type: 'file', mode: stat.mode & 0o777, sha256: sha(full)});
      } else throw Error('STD_PREFIX_UNSUPPORTED_ENTRY');
    }
  }
  walk('');
  return entries;
}
export function begin(prefix, source, compiler) {
  const identity = {...sourceIdentity(source), compiler_sha256: sha(compiler)};
  fs.mkdirSync(prefix, {recursive: true});
  // An existing prefix must belong to this same producer transaction. A
  // successful unchanged prefix supports normal rebuild; a pending same-input
  // transaction supports recovery. Unknown/changed inputs require a new prefix.
  if (fs.readdirSync(prefix).length) {
    const pendingPath = path.join(prefix, '.std-production.json');
    const previous = fs.existsSync(pendingPath)
      ? JSON.parse(fs.readFileSync(pendingPath)) : verify(prefix);
    for (const key of Object.keys(identity)) {
      if (previous[key] !== identity[key]) throw Error('STD_PREFIX_PRODUCER_MISMATCH');
    }
  }
  // This is the actual stdlib_build transaction, not a resume admission query.
  // Invalidate success only once same-producer ownership has been established.
  for (const name of metadata) fs.rmSync(path.join(prefix, name), {force: true});
  fs.writeFileSync(path.join(prefix, '.std-production.json'), `${JSON.stringify(identity)}\n`);
}
export function finish(prefix, source, compiler) {
  const pending = JSON.parse(fs.readFileSync(path.join(prefix, '.std-production.json')));
  const actual = {...sourceIdentity(source), compiler_sha256: sha(compiler)};
  if (JSON.stringify(pending) !== JSON.stringify(actual)) throw Error('STD_PRODUCER_CHANGED_DURING_BUILD');
  const files = prefixInventory(prefix);
  for (const root of ['lib', 'modules', 'runtime']) {
    if (!files.some(item => item.type === 'file' && item.path.startsWith(`${root}/`))) throw Error('STD_PREFIX_INCOMPLETE');
  }
  fs.writeFileSync(path.join(prefix, 'std-producer.json'), `${JSON.stringify({...actual, schema: 1, files}, null, 2)}\n`);
  fs.writeFileSync(path.join(prefix, 'STDLIB_SOURCE_SHA'), `${actual.source_commit}\n`);
  fs.rmSync(path.join(prefix, '.std-production.json'));
}
export function verify(prefix) {
  const receipt = JSON.parse(fs.readFileSync(path.join(prefix, 'std-producer.json')));
  if (receipt.schema !== 1 || !Array.isArray(receipt.files) || !receipt.files.length || fs.existsSync(path.join(prefix, '.std-production.json'))) throw Error('RESUME_STD_RECEIPT_INVALID');
  if (fs.readFileSync(path.join(prefix, 'STDLIB_SOURCE_SHA'), 'utf8').trim() !== receipt.source_commit) throw Error('RESUME_STD_SOURCE_RECEIPT_MISMATCH');
  const current = prefixInventory(prefix);
  if (JSON.stringify(current) !== JSON.stringify(receipt.files)) throw Error('RESUME_STD_PREFIX_MISMATCH');
  return receipt;
}
const index = process.argv.findIndex(value => path.resolve(value) === fileURLToPath(import.meta.url));
if (index >= 0) {
  const [mode, prefix, source, compiler] = process.argv.slice(index + 1);
  if (mode === 'begin') begin(prefix, source, compiler);
  else if (mode === 'finish') finish(prefix, source, compiler);
  else if (mode === 'verify') verify(prefix);
  else throw Error('STD_RECEIPT_MODE_INVALID');
}
