#!/usr/bin/env zx
// Complete a partial LLDB install using only its sealed native dependencies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {readJson, fileDigest, reject} from './sdk-manifest.mjs';

export async function exportCjdbPythonClosure(partial, install, execute) {
  const receiptFile = path.join(partial, 'output.json');
  const receipt = await readJson(receiptFile);
  if (receipt.status !== 'complete' || receipt.rc !== 0
      || await fileDigest(receiptFile) !== (await fs.readFile(path.join(partial, 'DONE'), 'utf8')).trim())
    reject('DEPENDENCY_DIGEST', 'llvm-cjdb', 'sealed dependency receipt');
  const root = path.join(partial, 'artifacts');
  const candidates = Object.keys(receipt.files).filter(rel =>
    /^(?:third_party\/llvm\/lib\/|tools\/lib\/|runtime\/lib\/)/.test(rel)
    && !rel.includes('/python') && !/^liblldb/.test(path.basename(rel)) && /\.so(?:\.|$)/.test(rel))
    // The loader searches the native lib directory. Prefer its formal alias
    // to an identically named runtime entity, then copy the alias target too.
    .sort((a,b) => Number(!a.startsWith('third_party/llvm/lib/'))
      - Number(!b.startsWith('third_party/llvm/lib/')) || a.localeCompare(b));
  const byName = new Map();
  for (const rel of candidates) {
    const name = path.basename(rel);
    if (!byName.has(name)) byName.set(name, rel);
    else if (receipt.files[byName.get(name)].sha256 !== receipt.files[rel].sha256)
      reject('DEPENDENCY_DIGEST', 'llvm-cjdb', `ambiguous sealed dependency ${name}`);
  }
  const copied = {}, edges = [], system = [], seen = new Set();
  const copy = async rel => {
    if (copied[rel]) return;
    const row = receipt.files[rel];
    if (!row || !candidates.includes(rel)) reject('DEPENDENCY_DIGEST', 'llvm-cjdb', `unsealed dependency ${rel}`);
    const from = path.join(root, rel), to = path.join(install, rel);
    if (await fileDigest(from) !== row.sha256) reject('DEPENDENCY_DIGEST', 'llvm-cjdb', rel);
    await fs.mkdir(path.dirname(to), {recursive:true});
    if (row.type === 'symlink') {
      if (await fs.readlink(from) !== row.target) reject('DEPENDENCY_DIGEST', 'llvm-cjdb', rel);
      await copy(path.normalize(path.join(path.dirname(rel), row.target)));
      await fs.symlink(row.target, to);
    } else {
      await fs.copyFile(from, to);
      await fs.chmod(to, row.mode);
    }
    copied[rel] = {from, sha256:row.sha256, type:row.type, target:row.target};
  };
  const inspect = async file => {
    const real = await fs.realpath(file);
    if (seen.has(real)) return;
    seen.add(real);
    const fd = await fs.open(real, 'r'), magic = Buffer.alloc(4);
    try { await fd.read(magic, 0, 4, 0); } finally { await fd.close(); }
    if (!magic.equals(Buffer.from([0x7f,0x45,0x4c,0x46]))) return;
    const {stdout} = await execute('/usr/bin/readelf', ['-d', real]);
    for (const match of stdout.matchAll(/\(NEEDED\).*\[([^\]]+)\]/g)) {
      const needed = match[1], rel = byName.get(needed);
      if (rel) {
        const to = path.join(install, rel);
        try { await fs.access(to); } catch (e) { if(e.code !== 'ENOENT')throw e; await copy(rel); }
        edges.push({file:real, needed, exported:rel});
        await inspect(to);
      } else {
        // Existing new LLDB/Python outputs remain owned by this build. Host
        // system libraries are recorded separately and checked by the loader.
        const local = path.join(install, 'third_party/llvm/lib', needed);
        try { await fs.access(local); await inspect(local); }
        catch (e) { if(e.code !== 'ENOENT')throw e; system.push({file:real, needed}); }
      }
    }
  };
  const walk = async directory => {
    for (const entry of await fs.readdir(directory, {withFileTypes:true})) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) await walk(file);
      else if (entry.isFile()) await inspect(file);
    }
  };
  await walk(path.join(install, 'third_party/llvm'));
  return {receiptFile, receiptSha256:await fileDigest(receiptFile), copied, edges, system};
}
