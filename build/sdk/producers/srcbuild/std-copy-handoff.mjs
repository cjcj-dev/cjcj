import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest as hash} from '../../../../ci/bootstrap/sdk-flow.mjs';

// prepareStdDependencies copies these pinned inputs without their .git dirs.
// Only paths tracked by the donor are source; generated siblings remain payload.
export function stdCopySources(repos) {
  const sources = new Map();
  const work = '.srcbuild/workspace';
  for (const [name, directory] of [['bounds', 'boundscheck-v1.1.16'], ['pcre2', 'pcre2']]) {
    const donor = repos.find(repo => repo.prefix === work + '/native-sources/' + name);
    if (!donor) continue;
    for (const id of ['std0', 'stdBootstrap', 'std1']) {
      const checkout = repos.find(repo => repo.prefix === work + '/native-bootstrap/sources/' + id);
      if (!checkout) continue;
      for (const file of donor.tracked) {
        const rel = 'stdlib/third_party/' + directory + '/' + file;
        if (!checkout.tracked.has(rel)) sources.set(checkout.prefix + '/' + rel, donor.prefix + '/' + file);
      }
    }
  }
  return sources;
}
async function pinnedCopyFile(realRoot, source) {
  const file = path.join(realRoot, source);
  if (await fs.realpath(file) !== file || !(await fs.stat(file)).isFile())
    throw new Error(`handoff std dependency input is not a pinned regular file: ${source}`);
  return file;
}

export async function planStdCopies(root, files, repos) {
  const copies = stdCopySources(repos), stdCopies = [], kept = [];
  const realRoot = await fs.realpath(root);
  for (const rel of files) {
    const source = copies.get(rel);
    if (!source) { kept.push(rel); continue; }
    const file = path.join(root, rel);
    const stat = await fs.lstat(file);
    if (!stat.isFile() || await hash(file) !== await hash(await pinnedCopyFile(realRoot, source)))
      throw new Error(`handoff std dependency copy differs from pinned input: ${rel}`);
    stdCopies.push({path: rel, mode: stat.mode & 0o777});
  }
  return {kept, stdCopies};
}

export async function restoreStdCopies(root, rows, sources) {
  if (!Array.isArray(rows)) throw new Error('handoff invalid std dependency copies');
  const realRoot = await fs.realpath(root);
  for (const row of rows) {
    const source = sources.get(row?.path);
    if (!source || !Number.isInteger(row.mode) || row.mode < 0 || row.mode > 0o777)
      throw new Error(`handoff invalid std dependency copy: ${row?.path}`);
    const input = await pinnedCopyFile(realRoot, source);
    const dest = path.join(realRoot, row.path), parent = path.dirname(dest);
    if (await fs.realpath(parent) !== parent)
      throw new Error(`handoff std dependency copy outside checkout: ${row.path}`);
    // The producer made a private, dereferenced copy. Preserve that isolation
    // (including on reentry); never hardlink the writable copy to its donor.
    const existing = await fs.lstat(dest).catch(error => {
      if (error.code !== 'ENOENT') throw error;
    });
    if (existing) {
      if (!existing.isFile() || await hash(dest) !== await hash(input))
        throw new Error(`handoff std dependency copy differs from pinned input: ${row.path}`);
    } else await fs.copyFile(input, dest);
    await fs.chmod(dest, row.mode);
  }
}
