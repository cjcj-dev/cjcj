import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';
import {pinnedOfficialSdkRoot} from './package-lineage.mjs';

// cjv writes installation metadata into an installed toolchain. It is not part
// of the release archive, so this exact subtree is the only official-path
// exclusion. Keep the table literal: a broader pattern could silently hide a
// real SDK directory with a similar name.
export const OFFICIAL_PATH_EXCLUSIONS = Object.freeze(['.cjv']);

function lexical(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function requireDirectory(root, label) {
  if (!fs.statSync(root, {throwIfNoEntry: false})?.isDirectory()) {
    throw new BuildError('package.sdk-path-parity', `${label} directory missing: ${root}`);
  }
}

function isExcluded(relative, excludedSubtrees) {
  return excludedSubtrees.some(subtree => relative === subtree || relative.startsWith(`${subtree}/`));
}

export function collectRelativePaths(root, {excludedSubtrees = []} = {}) {
  const absoluteRoot = path.resolve(root);
  requireDirectory(absoluteRoot, 'SDK');
  const entries = [];

  function walk(directory, relativeDirectory = '') {
    const children = fs.readdirSync(directory, {withFileTypes: true})
      .sort((left, right) => lexical(left.name, right.name));
    for (const entry of children) {
      const relative = relativeDirectory
        ? path.posix.join(relativeDirectory, entry.name)
        : entry.name;
      if (isExcluded(relative, excludedSubtrees)) continue;
      const absolute = path.join(directory, entry.name);
      const type = entry.isDirectory() ? 'dir' : entry.isSymbolicLink() ? 'symlink' : 'file';
      entries.push(Object.freeze({
        relativePath: relative,
        type,
        symlinkTarget: type === 'symlink' ? fs.readlinkSync(absolute) : null,
      }));
      if (type === 'dir') walk(absolute, relative);
    }
  }

  walk(absoluteRoot);
  return Object.freeze(entries);
}

export function compareSdkPathSets(officialRoot, candidateRoot, {target} = {}) {
  const exclusions = [...OFFICIAL_PATH_EXCLUSIONS];
  // Linux releases can contain optional Windows cross-target modules. The
  // native Linux SDK contract does not require those two exact target roots.
  // Windows and unspecified targets retain the complete reference inventory.
  if (['linux-x64', 'linux-aarch64'].includes(target)) {
    exclusions.push('lib/windows_x86_64_cjnative', 'modules/windows_x86_64_cjnative');
  }
  const officialEntries = collectRelativePaths(officialRoot, {excludedSubtrees: exclusions});
  const candidateEntries = collectRelativePaths(candidateRoot);
  const official = new Map(officialEntries.map(entry => [entry.relativePath, entry]));
  const candidate = new Map(candidateEntries.map(entry => [entry.relativePath, entry]));
  const officialPaths = Object.freeze([...official.keys()]);
  const candidatePaths = Object.freeze([...candidate.keys()]);
  const typeMismatches = officialEntries.flatMap(officialEntry => {
    const candidateEntry = candidate.get(officialEntry.relativePath);
    if (!candidateEntry) return [];
    // The managed compiler has two public entries into one authenticated
    // stage compiler. This exact relative relationship is the release ABI;
    // it does not exempt other symlinks (including pcre) from type parity.
    if (['bin/cjc', 'bin/cjc-frontend'].includes(officialEntry.relativePath)
      && candidateEntry.type === 'symlink' && candidateEntry.symlinkTarget === 'cjcj-stage1'
      && candidate.get('bin/cjcj-stage1')?.type === 'file'
      && candidate.get('bin/cjc')?.symlinkTarget === 'cjcj-stage1'
      && candidate.get('bin/cjc-frontend')?.symlinkTarget === 'cjcj-stage1') return [];
    if (officialEntry.type === candidateEntry.type
      && officialEntry.symlinkTarget === candidateEntry.symlinkTarget) return [];
    return [Object.freeze({
      relativePath: officialEntry.relativePath,
      officialType: officialEntry.type,
      candidateType: candidateEntry.type,
      officialSymlinkTarget: officialEntry.symlinkTarget,
      candidateSymlinkTarget: candidateEntry.symlinkTarget,
    })];
  });
  return Object.freeze({
    officialEntries,
    candidateEntries,
    officialPaths,
    candidatePaths,
    missingInCandidate: Object.freeze(officialPaths.filter(relative => !candidate.has(relative))),
    extraInCandidate: Object.freeze(candidatePaths.filter(relative => !official.has(relative))),
    typeMismatches: Object.freeze(typeMismatches),
  });
}

function describeEntry(type, symlinkTarget) {
  return type === 'symlink' ? `${type}->${symlinkTarget}` : type;
}

export async function assertSdkPathParity(candidateRoot, {officialRoot, target} = {}) {
  const referenceRoot = path.resolve(officialRoot || await pinnedOfficialSdkRoot());
  const depotLock = path.join(referenceRoot, 'SDK.lock.json');
  if (fs.existsSync(depotLock)
    && JSON.parse(fs.readFileSync(depotLock, 'utf8')).schema === 'sharedbuild-official-sdk-v1') {
    throw new BuildError('package.sdk-path-parity', 'REFERENCE_BOUNDARY: use the original archive payload, not a materialized sharedbuild depot');
  }
  const result = compareSdkPathSets(referenceRoot, candidateRoot, {target});
  for (const entry of result.candidateEntries) {
    if (entry.type !== 'symlink') continue;
    const file = path.join(candidateRoot, entry.relativePath);
    const root = fs.realpathSync(candidateRoot);
    let resolved;
    try { resolved = fs.realpathSync(file); } catch {
      throw new BuildError('package.sdk-path-parity', `package-link-invalid\t${entry.relativePath}\t${entry.symlinkTarget}`);
    }
    if (path.isAbsolute(entry.symlinkTarget) || !resolved.startsWith(`${root}${path.sep}`)) {
      throw new BuildError('package.sdk-path-parity', `package-link-outside\t${entry.relativePath}\t${entry.symlinkTarget}`);
    }
  }
  if (result.missingInCandidate.length || result.typeMismatches.length) {
    const differences = [
      ...result.missingInCandidate.map(relative => `missing-official-path\t${relative}`),
      ...result.typeMismatches.map(mismatch => (
        `type-mismatch\t${mismatch.relativePath}`
          + `\tofficial=${describeEntry(mismatch.officialType, mismatch.officialSymlinkTarget)}`
          + `\tcandidate=${describeEntry(mismatch.candidateType, mismatch.candidateSymlinkTarget)}`
      )),
    ];
    throw new BuildError(
      'package.sdk-path-parity',
      `candidate SDK differs from official SDK: missing=${result.missingInCandidate.length}`
        + ` type-mismatch=${result.typeMismatches.length}\n${differences.join('\n')}`,
    );
  }
  return Object.freeze({...result, officialRoot: referenceRoot, candidateRoot: path.resolve(candidateRoot)});
}
