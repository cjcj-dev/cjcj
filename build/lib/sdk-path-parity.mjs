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

export function compareSdkPathSets(officialRoot, candidateRoot) {
  const officialEntries = collectRelativePaths(officialRoot, {excludedSubtrees: OFFICIAL_PATH_EXCLUSIONS});
  const candidateEntries = collectRelativePaths(candidateRoot);
  const official = new Map(officialEntries.map(entry => [entry.relativePath, entry]));
  const candidate = new Map(candidateEntries.map(entry => [entry.relativePath, entry]));
  const officialPaths = Object.freeze([...official.keys()]);
  const candidatePaths = Object.freeze([...candidate.keys()]);
  const typeMismatches = officialEntries.flatMap(officialEntry => {
    const candidateEntry = candidate.get(officialEntry.relativePath);
    if (!candidateEntry) return [];
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

export async function assertSdkPathParity(candidateRoot, {officialRoot} = {}) {
  const referenceRoot = path.resolve(officialRoot || await pinnedOfficialSdkRoot());
  const result = compareSdkPathSets(referenceRoot, candidateRoot);
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
