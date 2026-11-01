import {resolveOfficialSdkRoot} from './config.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {nativeToolLibraries, retainedToolPath} from '../srcbuild/tool-layout.mjs';
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

// A relative link to a file inside the SDK is the same installed file
// interface as a regular file. Its storage type is not a loader ABI.
function installedFile(root, relative) {
  const file = path.join(root, relative);
  try {
    return fs.statSync(file).isFile()
      && fs.realpathSync(file).startsWith(fs.realpathSync(root) + path.sep);
  } catch { return false; }
}
function soname(file) {
  const result = spawnSync('readelf', ['-d', file], {encoding:'utf8', env:{...process.env, LC_ALL:'C'}});
  if (result.status !== 0) return null;
  const name = result.stdout.match(/\(SONAME\).*\[([^\]]+)\]/)?.[1];
  return name && !name.includes('/') && !name.includes('\\') ? name : null;
}
function installedTool(root, producer) {
  const to = 'tools/bin/' + producer;
  const retained = retainedToolPath({producer, name:producer, to});
  let recipe;
  try { recipe = fs.readFileSync(path.join(root, to + '.entry'), 'utf8').trimEnd().split('\n'); }
  catch { return false; }
  return recipe[0] === 'cjcj-sdk-entry-v1' && recipe[2] === retained
    && installedFile(root, to) && installedFile(root, retained);
}

export function compareSdkPathSets(officialRoot, candidateRoot, {target} = {}) {
  const exclusions = [...OFFICIAL_PATH_EXCLUSIONS];
  // This command packages one native target. Cross-target release assembly
  // separately requires its declared tuples (targets.mjs RELEASE_PLATFORMS).
  // Keep the Windows runtime, std/FFI and MinGW closure together; none is a
  // native Linux producer. Windows and unspecified targets retain them.
  if (['linux-x64', 'linux-aarch64'].includes(target)) {
    exclusions.push('lib/windows_x86_64_cjnative', 'modules/windows_x86_64_cjnative',
      'runtime/lib/windows_x86_64_cjnative', 'third_party/mingw', 'lib/libstdFFI.dll', 'lib/libstdFFI.dll.a');
  }
  const officialEntries = collectRelativePaths(officialRoot, {excludedSubtrees: exclusions});
  const candidateEntries = collectRelativePaths(candidateRoot);
  const official = new Map(officialEntries.map(entry => [entry.relativePath, entry]));
  const candidate = new Map(candidateEntries.map(entry => [entry.relativePath, entry]));
  const officialPaths = Object.freeze([...official.keys()]);
  const candidatePaths = Object.freeze([...candidate.keys()]);
  const nativeLinux = ['linux-x64', 'linux-aarch64'].includes(target);
  const lint = nativeLinux && installedTool(candidateRoot, 'cjlint');
  const prof = nativeLinux && installedTool(candidateRoot, 'cjprof');
  const missing = [], typeMismatches = [], counterparts = [];
  for (const officialEntry of officialEntries) {
    const relative = officialEntry.relativePath;
    let candidateEntry = candidate.get(relative);
    if (!candidateEntry && lint && relative.startsWith('tools/config/')) {
      const relocated = '.target-tools/tools/cjlint/config/' + relative.slice('tools/config/'.length);
      candidateEntry = candidate.get(relocated);
      if (candidateEntry) counterparts.push({official:relative, candidate:relocated});
    }
    // The current Cangjie producers have different payloads from the retired
    // C++ tools. Require their actual public entry and current dependencies.
    if (!candidateEntry && ((relative === 'tools/lib/libcjlint.so' && lint
        && candidate.get('.target-tools/tools/cjlint/modules')?.type === 'dir')
      || (relative === 'tools/lib/libcjprof.so' && prof
        && [...nativeToolLibraries('cjprof', 'linux').map(row => row.to), 'tools/share/java/cjprof.jar']
          .every(rel => installedFile(candidateRoot, rel))))) {
      counterparts.push({official:relative, candidate:'tools/bin/' + (relative.includes('cjlint') ? 'cjlint' : 'cjprof')});
      continue;
    }
    // A producer may change a versioned ELF filename while retaining its
    // actual loader name. Do not infer compatibility from a filename regex.
    if (!candidateEntry && nativeLinux && officialEntry.type === 'file' && relative.includes('.so')) {
      const name = soname(path.join(officialRoot, relative));
      const relocated = name && path.posix.join(path.posix.dirname(relative), name);
      if (relocated && installedFile(candidateRoot, relocated)
        && soname(path.join(candidateRoot, relocated)) === name) {
        candidateEntry = candidate.get(relocated);
        if (candidateEntry) counterparts.push({official:relative, candidate:relocated, soname:name});
      }
    }
    if (!candidateEntry) { missing.push(relative); continue; }
    // Both public compiler names intentionally select the same stage entry.
    if (['bin/cjc', 'bin/cjc-frontend'].includes(relative)
      && candidateEntry.type === 'symlink' && candidateEntry.symlinkTarget === 'cjcj-stage1'
      && candidate.get('bin/cjcj-stage1')?.type === 'file'
      && candidate.get('bin/cjc')?.symlinkTarget === 'cjcj-stage1'
      && candidate.get('bin/cjc-frontend')?.symlinkTarget === 'cjcj-stage1') continue;
    if (officialEntry.type === candidateEntry.type
      && officialEntry.symlinkTarget === candidateEntry.symlinkTarget) continue;
    if (officialEntry.type === 'file' && candidateEntry.type === 'symlink'
      && !['bin/cjc', 'bin/cjc-frontend'].includes(relative)
      && !path.isAbsolute(candidateEntry.symlinkTarget)
      && installedFile(candidateRoot, candidateEntry.relativePath)) continue;
    typeMismatches.push(Object.freeze({
      relativePath: relative,
      officialType: officialEntry.type,
      candidateType: candidateEntry.type,
      officialSymlinkTarget: officialEntry.symlinkTarget,
      candidateSymlinkTarget: candidateEntry.symlinkTarget,
    }));
  }
  return Object.freeze({
    officialEntries,
    candidateEntries,
    officialPaths,
    candidatePaths,
    missingInCandidate: Object.freeze(missing),
    counterparts: Object.freeze(counterparts),
    extraInCandidate: Object.freeze(candidatePaths.filter(relative => !official.has(relative))),
    typeMismatches: Object.freeze(typeMismatches),
  });
}

function describeEntry(type, symlinkTarget) {
  return type === 'symlink' ? `${type}->${symlinkTarget}` : type;
}

export async function assertSdkPathParity(candidateRoot, {officialRoot, target} = {}) {
  const referenceRoot = path.resolve(resolveOfficialSdkRoot(officialRoot) ?? await pinnedOfficialSdkRoot());
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
