#!/usr/bin/env zx
// Qualification-only export: new LLDB, private Python, and sealed dependencies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {readJson, fileDigest, inventory, reject} from './sdk-manifest.mjs';

const native = 'third_party/llvm';
const fail = (code, detail) => reject(code, 'llvm-cjdb', detail);
const inside = (root, file) => file === root || file.startsWith(`${root}${path.sep}`);
const relative = rel => {
  if (!rel || path.isAbsolute(rel) || path.normalize(rel) !== rel || rel === '..' || rel.startsWith('../'))
    fail('LINK_ESCAPE', rel);
  return rel;
};
const statIfPresent = async file => {
  try { return await fs.lstat(file); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
};
// Directory symlinks are never traversed, even when their bytes happen to match.
async function parents(root, rel, create = false) {
  if (await fs.realpath(root) !== path.resolve(root)) fail('LINK_ESCAPE', root);
  let directory = root;
  for (const part of path.dirname(relative(rel)).split(path.sep).filter(p => p !== '.')) {
    directory = path.join(directory, part);
    let stat = await statIfPresent(directory);
    if (!stat && create) { await fs.mkdir(directory); stat = await fs.lstat(directory); }
    if (!stat?.isDirectory() || stat.isSymbolicLink()) fail('LINK_ESCAPE', directory);
  }
}
async function describe(root, rel) {
  await parents(root, rel);
  const file = path.join(root, rel), stat = await fs.lstat(file);
  const row = {type:stat.isSymbolicLink() ? 'symlink' : 'file', mode:stat.mode & 0o777,
    size:stat.size, sha256:await fileDigest(file)};
  if (stat.isSymbolicLink()) {
    row.target = await fs.readlink(file);
    if (path.isAbsolute(row.target) || !inside(root, await fs.realpath(file))) fail('LINK_ESCAPE', file);
    row.size = Buffer.byteLength(row.target);
  } else if (!stat.isFile()) fail('FILE_TYPE', file);
  return row;
}

// Capture identities from the real CMake install manifest and Python producer
// root before merging either into a qualification destination.
export async function cjdbPythonClosureSources(lldbRoot, manifestFile, pythonRoot) {
  lldbRoot = path.resolve(lldbRoot); pythonRoot = path.resolve(pythonRoot);
  const lldb = {};
  for (const file of new Set((await fs.readFile(manifestFile, 'utf8')).trim().split('\n'))) {
    if (!inside(lldbRoot, path.resolve(file))) fail('LINK_ESCAPE', `install manifest ${file}`);
    const rel = relative(path.relative(lldbRoot, file));
    lldb[rel] = await describe(lldbRoot, rel);
  }
  return {lldb:{root:lldbRoot, manifestFile, manifestSha256:await fileDigest(manifestFile), files:lldb},
    python:{root:pythonRoot, files:await inventory(pythonRoot, {links:true})}};
}

export async function exportCjdbPythonClosure(partial, install, execute, sources) {
  if (!sources?.lldb?.files || !sources?.python?.files) fail('DEPENDENCY_SOURCE', 'explicit LLDB and Python identities required');
  const receiptFile = path.join(partial, 'output.json'), receipt = await readJson(receiptFile);
  const receiptSha256 = await fileDigest(receiptFile);
  if (receipt.status !== 'complete' || receipt.rc !== 0
      || receiptSha256 !== (await fs.readFile(path.join(partial, 'DONE'), 'utf8')).trim())
    fail('DEPENDENCY_DIGEST', 'sealed dependency receipt');
  await fs.mkdir(install, {recursive:true});
  install = path.resolve(install);
  if (await fs.realpath(install) !== install) fail('LINK_ESCAPE', install);
  const expected = new Map();
  for (const role of ['lldb','python']) {
    for (const [rel,row] of Object.entries(sources[role].files)) {
      const target = `${native}/${relative(rel)}`;
      if (expected.has(target)) fail('DEPENDENCY_SOURCE', `overlapping producer roles ${target}`);
      expected.set(target, {role,root:sources[role].root,rel,row});
    }
  }
  const sealedRoot = path.join(partial,'artifacts');
  const sealed = Object.keys(receipt.files).filter(rel =>
    /^(?:third_party\/llvm\/lib\/|tools\/lib\/|runtime\/lib\/)/.test(rel)
    && /\.so(?:\.|$)/.test(rel) && !expected.has(rel)
    && !rel.includes('/python') && !/^(?:liblldb|libpython|_lldb)/.test(path.basename(rel)))
    .sort((a,b) => Number(!a.startsWith(`${native}/lib/`)) - Number(!b.startsWith(`${native}/lib/`)) || a.localeCompare(b));
  for (const rel of sealed) expected.set(rel, {role:'sealed',root:sealedRoot,rel,row:receipt.files[rel]});
  const byName = new Map();
  // Roles take precedence over the old receipt. Same-name sealed aliases must
  // resolve to the same authenticated entity; names alone never authenticate.
  for (const [rel,entry] of expected) {
    if (!rel.startsWith(`${native}/lib/`) && entry.role !== 'sealed') continue;
    const name = path.basename(rel), old = byName.get(name);
    if (!old) byName.set(name, rel);
    else if (expected.get(old).role === 'sealed' && entry.role === 'sealed'
      && expected.get(old).row.sha256 !== entry.row.sha256) fail('DEPENDENCY_DIGEST', `ambiguous dependency ${name}`);
  }
  const copied = {}, verified = new Set(), copying = new Set(), edges = [], system = [], seen = new Set();
  async function verify(root, rel, row) {
    await parents(root, rel);
    const file = path.join(root,rel), stat = await fs.lstat(file);
    if ((row.type === 'symlink') !== stat.isSymbolicLink()
      || (row.type === 'file' && !stat.isFile()) || (stat.mode & 0o777) !== row.mode)
      fail('DEPENDENCY_DIGEST', `type/mode ${file}`);
    if (row.type === 'symlink') {
      const target = await fs.readlink(file);
      if (target !== row.target || path.isAbsolute(target)) fail('LINK_ESCAPE', `alias ${file}`);
      relative(path.normalize(path.join(path.dirname(rel), target)));
    }
    if (await fileDigest(file) !== row.sha256) fail('DEPENDENCY_DIGEST', `bytes ${file}`);
    if (!inside(root, await fs.realpath(file))) fail('LINK_ESCAPE', file);
  }
  async function copy(rel) {
    if (verified.has(rel)) return;
    if (copying.has(rel)) fail('LINK_CYCLE', rel);
    const entry = expected.get(rel);
    if (!entry) fail('DEPENDENCY_SOURCE', `unowned alias/dependency ${rel}`);
    const {root,row,role} = entry;
    copying.add(rel);
    await verify(root,entry.rel,row);
    await parents(install,rel,true);
    const to = path.join(install,rel), stat = await statIfPresent(to);
    if (row.type === 'symlink') {
      const target = relative(path.normalize(path.join(path.dirname(rel), row.target)));
      const targetEntry = expected.get(target);
      if (!targetEntry || (role === 'sealed' && targetEntry.role !== 'sealed')) fail('DEPENDENCY_SOURCE', `alias role ${rel} -> ${target}`);
      await copy(target);
    }
    if (stat) await verify(install,rel,row);
    else if (row.type === 'symlink') await fs.symlink(row.target,to);
    else {
      await fs.copyFile(path.join(root,entry.rel),to,fs.constants.COPYFILE_EXCL);
      await fs.chmod(to,row.mode);
    }
    await verify(install,rel,row);
    copied[rel] = {role,from:path.join(root,entry.rel),...row};
    verified.add(rel); copying.delete(rel);
  }
  let cache;
  async function resolveSystem(needed) {
    if (!cache) cache = (await execute('/sbin/ldconfig',['-p'])).stdout;
    const rows = [...cache.matchAll(/^\s*(\S+)\s+\([^\n]*x86-64[^\n]*\)\s+=>\s+(\S+)\s*$/gm)]
      .filter(m => m[1] === needed);
    if (!rows.length) fail('DEPENDENCY_MISSING', needed);
    const alias = rows[0][2], real = await fs.realpath(alias);
    if (!['/usr/lib','/lib'].some(root=>inside(root,real))) fail('DEPENDENCY_SOURCE', `system domain ${alias} -> ${real}`);
    const stat = await fs.stat(real);
    if (!stat.isFile()) fail('FILE_TYPE', real);
    return {role:'system',alias,real,sha256:await fileDigest(real),mode:stat.mode & 0o777};
  }
  async function inspect(file, role) {
    const real = await fs.realpath(file);
    if (seen.has(real)) return;
    seen.add(real);
    const handle = await fs.open(real,'r'), magic = Buffer.alloc(4);
    try { await handle.read(magic,0,4,0); } finally { await handle.close(); }
    if (!magic.equals(Buffer.from([0x7f,0x45,0x4c,0x46]))) return;
    const {stdout} = await execute('/usr/bin/readelf',['-d',real]);
    if (!/Dynamic section|There is no dynamic section/.test(stdout)) fail('DEPENDENCY_PARSE', real);
    for (const match of stdout.matchAll(/\(NEEDED\).*\[([^\]]+)\]/g)) {
      const needed = match[1];
      if (path.basename(needed) !== needed) fail('DEPENDENCY_SOURCE', `NEEDED path ${needed}`);
      // Host libraries resolve their own dependencies in the host domain.
      const rel = role === 'system' ? undefined : byName.get(needed);
      if (rel) {
        await copy(rel);
        edges.push({file:real,needed,exported:rel,role:expected.get(rel).role,sha256:expected.get(rel).row.sha256});
        await inspect(path.join(install,rel),expected.get(rel).role);
      } else {
        if (/^(?:libpython|liblldb|_lldb)/.test(needed)) fail('DEPENDENCY_SOURCE', `unowned Python/LLDB ${needed}`);
        const resolved = await resolveSystem(needed);
        system.push({file:real,needed,...resolved});
        await inspect(resolved.real,'system');
      }
    }
  }
  // Authenticate every existing destination, including non-ELF Python binding
  // files. Unknown old outputs and directory links are rejected, never skipped.
  async function walk(directory, prefix='') {
    for (const dirent of await fs.readdir(directory,{withFileTypes:true})) {
      const rel = prefix ? `${prefix}/${dirent.name}` : dirent.name;
      if (dirent.isDirectory()) await walk(path.join(directory,dirent.name),rel);
      else await copy(rel);
    }
  }
  await walk(install);
  for (const [rel,entry] of expected) if (entry.role !== 'sealed') await copy(rel);
  for (const [rel,entry] of expected) if (entry.role !== 'sealed') await inspect(path.join(install,rel),entry.role);
  return {receiptFile,receiptSha256,sources,copied,edges,system};
}
