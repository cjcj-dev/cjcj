import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export const OPTIMIZED_STD_SUBDIR = 'cjcj-optimization';
export const STICKY_LLC_OPTION = '--cjcj-sticky-logged-map';

function requireDirectory(directory, label) {
  if (!fs.statSync(directory, {throwIfNoEntry: false})?.isDirectory()) {
    throw new Error(`${label} directory missing: ${directory}`);
  }
  return directory;
}

function requireFile(file, label) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new Error(`${label} file missing: ${file}`);
  }
  return file;
}

function shellSingleQuote(value) {
  return `'${String(value).replaceAll("'", "'\"'\"'")}'`;
}

export function createStickySdkOverlay(sdkRoot, overlayRoot) {
  const sdk = path.resolve(requireDirectory(sdkRoot, 'SDK'));
  const overlay = path.resolve(overlayRoot);
  fs.rmSync(overlay, {recursive: true, force: true});
  fs.mkdirSync(overlay, {recursive: true});

  for (const name of ['bin', 'include', 'lib', 'modules', 'runtime', 'tools']) {
    const source = requireDirectory(path.join(sdk, name), `SDK ${name}`);
    fs.symlinkSync(source, path.join(overlay, name), 'dir');
  }

  const llvm = requireDirectory(path.join(sdk, 'third_party', 'llvm'), 'SDK LLVM');
  const llvmOverlay = path.join(overlay, 'third_party', 'llvm');
  fs.mkdirSync(llvmOverlay, {recursive: true});
  for (const name of fs.readdirSync(llvm)) {
    if (name === 'bin') continue;
    const source = path.join(llvm, name);
    fs.symlinkSync(source, path.join(llvmOverlay, name), fs.statSync(source).isDirectory() ? 'dir' : 'file');
  }

  const llvmBin = requireDirectory(path.join(llvm, 'bin'), 'SDK LLVM bin');
  const llvmBinOverlay = path.join(llvmOverlay, 'bin');
  fs.mkdirSync(llvmBinOverlay, {recursive: true});
  for (const name of fs.readdirSync(llvmBin)) {
    if (name === 'llc') continue;
    const source = path.join(llvmBin, name);
    fs.symlinkSync(source, path.join(llvmBinOverlay, name), 'file');
  }
  const llc = requireFile(path.join(llvmBin, 'llc'), 'SDK llc');
  const wrapper = path.join(llvmBinOverlay, 'llc');
  fs.writeFileSync(wrapper, `#!/bin/sh\nexec ${shellSingleQuote(llc)} ${STICKY_LLC_OPTION} "$@"\n`);
  fs.chmodSync(wrapper, 0o755);
  return overlay;
}

function stdLibraryName(name) {
  return /^libcangjie-std(?:[-.].*)?\.(?:a|so|dylib)$/.test(name);
}

export function copyCompiledStdLibraries(sourceDirectory, destinationDirectory) {
  const source = requireDirectory(sourceDirectory, 'compiled std library');
  fs.mkdirSync(destinationDirectory, {recursive: true});
  const files = fs.readdirSync(source).filter(stdLibraryName).sort();
  if (files.length === 0) throw new Error(`no compiled std libraries found under ${source}`);
  let bytes = 0;
  for (const name of files) {
    const from = path.join(source, name);
    const to = path.join(destinationDirectory, name);
    fs.copyFileSync(from, to);
    fs.chmodSync(to, fs.statSync(from).mode);
    bytes += fs.statSync(to).size;
  }
  return {files, bytes};
}

function cjoFiles(directory) {
  const root = requireDirectory(directory, 'std CJO');
  return fs.readdirSync(root).filter(name => name.endsWith('.cjo')).sort();
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

export function compareStdCjos(flagOffDirectory, stickyDirectory) {
  const flagOffFiles = cjoFiles(flagOffDirectory);
  const stickyFiles = cjoFiles(stickyDirectory);
  if (flagOffFiles.length === 0) throw new Error('flag-off std build produced no CJO files');
  if (flagOffFiles.join('\n') !== stickyFiles.join('\n')) {
    throw new Error('flag-off and sticky std builds produced different CJO file sets');
  }
  const results = [];
  for (const name of flagOffFiles) {
    const flagOff = path.join(flagOffDirectory, name);
    const sticky = path.join(stickyDirectory, name);
    const flagOffSha256 = sha256(flagOff);
    const stickySha256 = sha256(sticky);
    results.push({name, flagOffSha256, stickySha256, identical: flagOffSha256 === stickySha256});
  }
  return results;
}

function readelf(args) {
  const result = spawnSync('readelf', args, {encoding: 'utf8', maxBuffer: 128 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`readelf ${args[0]} failed with exit ${result.status}: ${result.stderr}`);
  return result.stdout;
}

function matches(text, pattern) {
  return text.match(pattern)?.length ?? 0;
}

export function stickyPreflight(libraryDirectory) {
  const root = requireDirectory(libraryDirectory, 'sticky std library');
  const sharedLibraries = fs.readdirSync(root)
    .filter(name => /^libcangjie-std.*\.so$/.test(name)).sort().map(name => path.join(root, name));
  if (sharedLibraries.length === 0) throw new Error(`no sticky std shared libraries found under ${root}`);
  const symbols = readelf(['-Ws', ...sharedLibraries]);
  const relocations = readelf(['-rW', ...sharedLibraries]);
  return {
    sharedLibraries: sharedLibraries.length,
    loggedBaseSymbols: matches(symbols, /__cj_sticky_logged_base/g),
    stickySymbols: matches(symbols, /__cj_sticky/g),
    stickyRelocations: matches(relocations, /__cj_sticky/g),
  };
}
