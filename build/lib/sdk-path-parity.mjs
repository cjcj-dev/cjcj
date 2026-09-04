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
  const paths = [];

  function walk(directory, relativeDirectory = '') {
    const entries = fs.readdirSync(directory, {withFileTypes: true})
      .sort((left, right) => lexical(left.name, right.name));
    for (const entry of entries) {
      const relative = relativeDirectory
        ? path.posix.join(relativeDirectory, entry.name)
        : entry.name;
      if (isExcluded(relative, excludedSubtrees)) continue;
      paths.push(relative);
      if (entry.isDirectory()) walk(path.join(directory, entry.name), relative);
    }
  }

  walk(absoluteRoot);
  return paths;
}

export function compareSdkPathSets(officialRoot, candidateRoot) {
  const officialPaths = collectRelativePaths(officialRoot, {excludedSubtrees: OFFICIAL_PATH_EXCLUSIONS});
  const candidatePaths = collectRelativePaths(candidateRoot);
  const official = new Set(officialPaths);
  const candidate = new Set(candidatePaths);
  return Object.freeze({
    officialPaths: Object.freeze(officialPaths),
    candidatePaths: Object.freeze(candidatePaths),
    missingInCandidate: Object.freeze(officialPaths.filter(relative => !candidate.has(relative))),
    extraInCandidate: Object.freeze(candidatePaths.filter(relative => !official.has(relative))),
  });
}

export async function assertSdkPathParity(candidateRoot, {officialRoot} = {}) {
  const referenceRoot = path.resolve(officialRoot || await pinnedOfficialSdkRoot());
  const result = compareSdkPathSets(referenceRoot, candidateRoot);
  if (result.missingInCandidate.length) {
    throw new BuildError(
      'package.sdk-path-parity',
      `candidate SDK is missing ${result.missingInCandidate.length} official path(s):\n`
        + result.missingInCandidate.map(relative => `missing-official-path\t${relative}`).join('\n'),
    );
  }
  return Object.freeze({...result, officialRoot: referenceRoot, candidateRoot: path.resolve(candidateRoot)});
}
